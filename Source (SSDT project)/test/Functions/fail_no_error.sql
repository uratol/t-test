CREATE function [test].[fail_no_error]()
returns nvarchar(max)
as
begin
	return test.throw_error('<<No error>>')
end
