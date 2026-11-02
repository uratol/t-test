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