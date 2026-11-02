CREATE function [test].[throw_error](
 @error_message nvarchar(max)
)
-- Throws exception from a function
returns nvarchar(max)
as
begin
	declare @return_value nvarchar(max)

	if @error_message is not null
	begin
		if try_cast(left(@error_message, 4000) as int) is not null
			set @error_message = N'Error: ' + @error_message -- Ensure numeric messages like N'123' also throw an exception.

		set @return_value = cast(left(@error_message, 4000) as int)
	end

	return @return_value
end