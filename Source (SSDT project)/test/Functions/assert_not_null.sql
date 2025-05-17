create function test.assert_not_null
(@message nvarchar(max)
,@value varbinary(max)
)
returns nvarchar(max)
as
begin

return iif(@value is null, test.fail(@message), '')

end