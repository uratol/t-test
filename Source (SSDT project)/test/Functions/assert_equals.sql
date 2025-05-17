CREATE function [test].[assert_equals]
( @message nvarchar(max)
, @expected nvarchar(max)
, @actual nvarchar(max)
)
returns nvarchar(max)
as
begin
	
	if [test].[is_equal](@expected, @actual) = 1
		return ''

	return test.fail(@message + char(13)+char(10)+
					'expected: ' + isnull('<'+@expected+'>', 'null') +
					char(13)+char(10)+
					'but was : ' + isnull('<'+@actual+'>', 'null'))
	
end