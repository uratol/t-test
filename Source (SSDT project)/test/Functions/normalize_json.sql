CREATE function test.normalize_json
(@json nvarchar(max))
returns varbinary(max)
as
begin
	declare @result varbinary(max) = 0x
		, @is_array bit = isjson(@json, array)

	declare @buffer table(i int identity primary key
		, data varbinary(max) not null)

	insert @buffer(data)
		select iif(@is_array = 0, cast([key] as varbinary(max)), 0x)
			+ 0x00
			+ cast(const.val as varbinary(max) )
			+ 0x00
			+ cast(type as varbinary(max))
			+ 0x00
		from openjson(@json) oj
			cross apply (
				select case 
					when oj.type = 1 and try_cast(left(oj.value, 4000) as datetime)  is not null
						then cast(cast(oj.value as datetime) as varbinary(max))
					when oj.type = 2 
						then cast(isnull(format(try_cast(left(oj.value, 4000) as decimal(30, 20)), 'g18'), oj.value) as varbinary(max))
					when oj.type in (4, 5)
						then test.normalize_json(oj.value)
					else
						isnull(cast(oj.value as varbinary(max)), 0x)
					end
			) as const(val)
		order by case when @is_array = 1 then cast(const.val as nvarchar(max)) else cast(oj.[key] as nvarchar(max)) end 

	select @result += data
	from @buffer as b
	order by i

	return cast(@is_array as binary(1)) + @result
end