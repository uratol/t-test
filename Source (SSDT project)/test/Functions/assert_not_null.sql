CREATE function test.assert_not_null
(@message nvarchar(max)
,@value varbinary(max)
)
returns nvarchar(max)
as
begin
	declare @return_value nvarchar(max)

	if @value is null
		set @return_value = test.fail(@message)
	else
		set @return_value = N''

	return @return_value
end