CREATE proc [test].[vector]
  @test_name nvarchar(max)
, @parameters nvarchar(max)
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

if @table_id is null begin
	set @sql = concat(N'WARNING: test.vector skipped in ', @scope, N' scope: ',
		@table_name, N' was not found.')
	print @sql
	print case when @scope = N'session'
		then N'Run CREATE TABLE directly in the calling batch on this connection:'
		else N'Create the permanent table in this database:' end
	set @sql = concat(N'CREATE TABLE ', @table_name, N' (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);')
	print @sql
	return
end

declare @canonical_name nvarchar(max)
if parsename(@test_name, 2) is not null
	and parsename(@test_name, 3) is null and parsename(@test_name, 4) is null
	select @canonical_name = test_proc_full_name
	from test.test
	where object_id(test_proc_full_name) = object_id(@test_name)

if @canonical_name is null
	exec test.throw @message = N'Vector test must be a schema-qualified discovered test in this database.';
if @parameters is null or trim(replace(replace(replace(@parameters,
	nchar(9), N' '), nchar(10), N' '), nchar(13), N' ')) = N''
	exec test.throw @message = N'Vector parameters cannot be NULL or blank.';

set @sql = N'INSERT ' + @table_name + N' (procedure_name, parameters) VALUES (@name, @parameters);'
exec sys.sp_executesql @sql, N'@name nvarchar(max), @parameters nvarchar(max)',
	@name = @canonical_name, @parameters = @parameters
