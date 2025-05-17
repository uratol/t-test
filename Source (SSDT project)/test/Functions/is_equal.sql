CREATE function test.is_equal
( @expected nvarchar(max)
, @actual nvarchar(max)
)
returns bit
as
begin
	
	if (@expected is not distinct from @actual)
		return 1

	if len(@actual) + len(@expected) < 100 -- to avoid "string or binary data would be truncated" exception
		if try_cast(@expected as decimal(30, 20)) = try_cast(@actual as decimal(30, 20))
			return 1

	if isjson(@expected) = 1 
		if isjson(@actual) = 1
			if test.normalize_json(@expected) = test.normalize_json(@actual)
				return 1

    return 0
end