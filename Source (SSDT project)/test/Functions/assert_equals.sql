CREATE function [test].[assert_equals]
( @message nvarchar(max)
, @expected nvarchar(max)
, @actual nvarchar(max)
)
returns nvarchar(max)
as
begin
	declare @return_value nvarchar(max)

	if [test].[is_equal](@expected, @actual) = 1
		set @return_value = N''
	else
		set @return_value = test.fail(@message + char(13)+char(10)+
						'expected: ' + isnull('<'+@expected+'>', 'null') +
						char(13)+char(10)+
						'but was : ' + isnull('<'+@actual+'>', 'null'))

	return @return_value
end