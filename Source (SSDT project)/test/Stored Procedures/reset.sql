CREATE proc [test].[reset]
as

set nocount on

declare @scope nvarchar(4000) = convert(nvarchar(4000), session_context(N'ttest:vectors:scope'))
if @scope is null set @scope = N'global'
if not (
	(@scope collate Latin1_General_100_BIN2 = N'session' and datalength(@scope) = 14)
	or (@scope collate Latin1_General_100_BIN2 = N'global' and datalength(@scope) = 12))
	exec test.throw @message = N'Vector scope must be exactly session or global.';

declare @table_name nvarchar(128) = case when @scope = N'session'
		then N'#test_vectors' else N'[test].[test_vectors]' end
	, @table_id int = case when @scope = N'session'
		then object_id(N'tempdb..#test_vectors') else object_id(N'[test].[test_vectors]', N'U') end
	, @sql nvarchar(max)

if @table_id is null return
set @sql = N'DELETE FROM ' + @table_name + N';'
exec sys.sp_executesql @sql
