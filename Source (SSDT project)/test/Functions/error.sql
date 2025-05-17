CREATE function [test].[error]()
returns nvarchar(max)
as
begin
	
	return test.throw_error('<<No error>>')

end