CREATE function [test].[format_message]
(@msg nvarchar(max)
,@p1 sql_variant = N'[unassigned]'
,@p2 sql_variant = N'[unassigned]'
,@p3 sql_variant = N'[unassigned]'
,@p4 sql_variant = N'[unassigned]'
)
returns nvarchar(max)
as
begin

	declare @unassigned nvarchar(4000) = N'[unassigned]'
		, @null nvarchar(4000) = N'<null>'

	if charindex(N'date', cast(sql_variant_property(@p1, N'basetype') as nvarchar)) > 0
		set @p1 = convert(nvarchar(10), @p1, 101) 
			+ iif(cast(cast(@p1 as datetime) as time) != N'00:00:00:000', N' ' + convert(nvarchar(5), @p1, 114), N'')
	if charindex(N'date', cast(sql_variant_property(@p2, N'basetype') as nvarchar)) > 0
		set @p2 = convert(nvarchar(10), @p2, 101) 
			+ iif(cast(cast(@p2 as datetime) as time) != N'00:00:00:000', N' ' + convert(nvarchar(5), @p2, 114), N'')
	if charindex(N'date', cast(sql_variant_property(@p3, N'basetype') as nvarchar)) > 0
		set @p3 = convert(nvarchar(10), @p3, 101) 
			+ iif(cast(cast(@p3 as datetime) as time) != N'00:00:00:000', N' ' + convert(nvarchar(5), @p3, 114), N'')
	if charindex(N'date', cast(sql_variant_property(@p4, N'basetype') as nvarchar)) > 0
		set @p4 = convert(nvarchar(10), @p4, 101) 
			+ iif(cast(cast(@p4 as datetime) as time) != N'00:00:00:000', N' ' + convert(nvarchar(5), @p4, 114), N'')

	if charindex(N'binary', cast(sql_variant_property(@p1, N'basetype') as nvarchar)) > 0
		set @p1 = convert(nvarchar(4000), @p1, 1)
	if charindex(N'binary', cast(sql_variant_property(@p2, N'basetype') as nvarchar)) > 0
		set @p2 = convert(nvarchar(4000), @p2, 1)
	if charindex(N'binary', cast(sql_variant_property(@p3, N'basetype') as nvarchar)) > 0
		set @p3 = convert(nvarchar(4000), @p3, 1)
	if charindex(N'binary', cast(sql_variant_property(@p4, N'basetype') as nvarchar)) > 0
		set @p4 = convert(nvarchar(4000), @p4, 1)

	if @p1 is null set @p1 = @null
	if @p2 is null set @p2 = @null
	if @p3 is null set @p3 = @null
	if @p4 is null set @p4 = @null

	if @p1 <> @unassigned
		set @msg = replace(@msg, N'%1', cast(@p1 as nvarchar(4000)))
	if @p2 <> @unassigned
		set @msg = replace(@msg, N'%2', cast(@p2 as nvarchar(4000)))
	if @p3 <> @unassigned
		set @msg = replace(@msg, N'%3', cast(@p3 as nvarchar(4000)))
	if @p4 <> @unassigned
		set @msg = replace(@msg, N'%4', cast(@p4 as nvarchar(4000)))

	return @msg
end