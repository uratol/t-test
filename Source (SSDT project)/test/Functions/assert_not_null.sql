CREATE function test.assert_not_null
(@message nvarchar(max)
,@value varbinary(max)
)
returns nvarchar(max)
as
begin

if @value is null
	return test.fail(@message)

return ''

end