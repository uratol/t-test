CREATE function [test].[assert_error_like](
  @message nvarchar(max)
, @pattern nvarchar(max)
)
returns int
as
begin
	declare @actual_error_message nvarchar(max) = error_message()

	if @actual_error_message is null
			or @actual_error_message like '%<<No error>>%'
			or @actual_error_message not like @pattern
		return test.throw_error(
			concat(@message + '. '
				, 'Error pattern "', @pattern, '" expected. '
				, 'Got error: ', isnull('"' + @actual_error_message + '"', '<null>'))
			)
	return null
end