/*
Reorganizar índices: Se a fragmentação do índice for baixa (geralmente entre 10% e 30%), pode ser suficiente reorganizá-lo, o que compacta as páginas de dados sem recriar todo o índice.
Reconstruir índices: Quando a fragmentação for alta (acima de 30%), é recomendável recriar o índice. Isso elimina fragmentação e melhora o desempenho de leitura, mas é um processo mais intensivo.
*/

USE [nome banco]
GO

SET NOCOUNT ON;
DECLARE @objectid int;
DECLARE @indexid int;
DECLARE @partitioncount bigint;
DECLARE @schemaname nvarchar(130);
DECLARE @objectname nvarchar(130);
DECLARE @indexname nvarchar(130);
DECLARE @partitionnum bigint;
DECLARE @partitions bigint;
DECLARE @frag float;
DECLARE @command nvarchar(4000);
DECLARE @dbid smallint;

-- Conditionally select tables and indexes from the sys.dm_db_index_physical_stats function
-- and convert object and index IDs to names.
SET @dbid = DB_ID();
SELECT
    [object_id] AS objectid,
    index_id AS indexid,
    partition_number AS partitionnum,
    avg_fragmentation_in_percent AS frag, page_count
INTO #work_to_do
FROM sys.dm_db_index_physical_stats (@dbid, NULL, NULL , NULL, N'LIMITED')
WHERE avg_fragmentation_in_percent > 5.0  -- Allow limited fragmentation
AND index_id > 0 -- Ignore heaps
AND page_count > 0; -- Ignore small tables
-- Declare the cursor for the list of partitions to be processed.
DECLARE partitions CURSOR FOR SELECT objectid,indexid, partitionnum,frag FROM #work_to_do;
-- Open the cursor.
OPEN partitions;
-- Loop through the partitions.
WHILE (1=1)
BEGIN
FETCH NEXT
FROM partitions
INTO @objectid, @indexid, @partitionnum, @frag;
IF @@FETCH_STATUS < 0 BREAK;
SELECT @objectname = QUOTENAME(o.name), @schemaname = QUOTENAME(s.name)
FROM sys.objects AS o
JOIN sys.schemas as s ON s.schema_id = o.schema_id
WHERE o.object_id = @objectid;
SELECT @indexname = QUOTENAME(name)
FROM sys.indexes
WHERE object_id = @objectid AND index_id = @indexid;
SELECT @partitioncount = count (*)
FROM sys.partitions
WHERE object_id = @objectid AND index_id = @indexid;
-- 30 is an arbitrary decision point at which to switch between reorganizing and rebuilding.
IF @frag < 30.0
SET @command = N'ALTER INDEX ' + @indexname + N' ON ' + @schemaname + N'.' + @objectname + N' REORGANIZE';
IF @frag >= 30.0
SET @command = N'ALTER INDEX ' + @indexname + N' ON ' + @schemaname + N'.' + @objectname + N' REBUILD';
IF @partitioncount > 1
SET @command = @command + N' PARTITION=' + CAST(@partitionnum AS nvarchar(10));
EXEC (@command);
PRINT N'Executed: ' + @command;
END
-- Close and deallocate the cursor.
CLOSE partitions;
DEALLOCATE partitions;
-- Drop the temporary table.
DROP TABLE #work_to_do;
GO
EXEC sp_updatestats 
GO