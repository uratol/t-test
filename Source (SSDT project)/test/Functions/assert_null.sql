create function [test].[assert_null]
(@message nvarchar(max)
,@value varbinary(max)
)
returns nvarchar(max)
as
begin

return iif(@value is not null, test.fail(@message), '')

end