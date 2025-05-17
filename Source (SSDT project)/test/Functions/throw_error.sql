CREATE function [test].[throw_error](
 @error_message nvarchar(max)
)
-- Throws exception from a function
returns nvarchar(max)
as
begin
	if @error_message is not null
		return cast(left(@error_message, 4000) as int)

	return null
end