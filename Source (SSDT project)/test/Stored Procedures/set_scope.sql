CREATE proc [test].[set_scope]
  @scope nvarchar(max)
as

set nocount on

if @scope is null or not (
	(@scope collate Latin1_General_100_BIN2 = N'session' and datalength(@scope) = 14)
	or (@scope collate Latin1_General_100_BIN2 = N'global' and datalength(@scope) = 12))
	exec test.throw @message = N'Vector scope must be exactly session or global.';

declare @value nvarchar(7) = @scope
exec sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @value, @read_only = 0
