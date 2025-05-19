CREATE function [test].[assert_null]
(@message nvarchar(max)
,@value varbinary(max)
)
returns nvarchar(max)
as
begin

if @value is not null
	return test.fail(@message)

return ''

end