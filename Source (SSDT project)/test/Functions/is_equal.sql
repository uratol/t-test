CREATE function test.is_equal
( @expected nvarchar(max)
, @actual nvarchar(max)
)
returns bit
as
begin
	declare @return_value bit = 0

	if (@expected is not distinct from @actual)
		set @return_value = 1
	else
	begin
		if len(@actual) + len(@expected) < 100 -- to avoid "string or binary data would be truncated" exception
			if try_cast(@expected as decimal(30, 20)) = try_cast(@actual as decimal(30, 20))
				set @return_value = 1

		if @return_value = 0
			if isjson(@expected) = 1
				if isjson(@actual) = 1
					-- Inlining can evaluate UDF calls before their enclosing branch.
					if test.is_json_equal(
						case when @return_value = 0 and isjson(@expected) = 1 and isjson(@actual) = 1 then @expected end,
						case when @return_value = 0 and isjson(@expected) = 1 and isjson(@actual) = 1 then @actual end) = 1
						set @return_value = 1
	end

	return @return_value
end