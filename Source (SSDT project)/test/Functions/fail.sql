CREATE function [test].[fail](
@message nvarchar(max)
)
returns int
as
begin
	return test.throw_error(concat('Unit-test fail: ', @message))
end