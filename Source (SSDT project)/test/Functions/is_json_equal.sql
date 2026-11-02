CREATE function test.is_json_equal
(@expected nvarchar(max), @actual nvarchar(max))
returns bit
as
begin
	declare @result bit = 0,
		@compare bit = iif(isjson(@expected) = 1 and isjson(@actual) = 1
			and isjson(@expected, array) = isjson(@actual, array), 1, 0)
	declare @left nvarchar(max) = case when @compare = 0 then N'[]'
			when isjson(@expected, object) = 1 then N'[' + @expected + N']' else @expected end,
		@right nvarchar(max) = case when @compare = 0 then N'[]'
			when isjson(@actual, object) = 1 then N'[' + @actual + N']' else @actual end

	if @compare = 1
		select @result = case when exists (
			select 1
			from (
				select cast(r.[key] as int) as row_key, p.[key],
					case when r.type = 5 then p.value else r.value end as value,
					coalesce(p.type, r.type) as type
				from openjson(@left) r
				outer apply openjson(case when r.type = 5 then r.value end) p
			) e
			full outer join (
				select cast(r.[key] as int) as row_key, p.[key],
					case when r.type = 5 then p.value else r.value end as value,
					coalesce(p.type, r.type) as type
				from openjson(@right) r
				outer apply openjson(case when r.type = 5 then r.value end) p
			) a on a.row_key = e.row_key and a.[key] is not distinct from e.[key]
			where e.row_key is null or a.row_key is null
				or e.type is distinct from a.type
				or e.value is distinct from a.value
		) then 0 else 1 end

	return @result
end
