CREATE proc [test].[log]
  @message nvarchar(max) = null
, @data nvarchar(max) = null
, @severity nvarchar(8) = 'debug' -- debug, info, warning, error
, @p1 sql_variant = N'!unassigned'
, @p2 sql_variant = N'!unassigned'
, @p3 sql_variant = N'!unassigned'
, @p4 sql_variant = N'!unassigned'
, @p1_str nvarchar(max) = N'!unassigned' -- the same as @p1, cause varchar/nvarchar(max) can't be passed through sql_variant
, @p2_str nvarchar(max) = N'!unassigned' 
, @p3_str nvarchar(max) = N'!unassigned' 
, @p4_str nvarchar(max) = N'!unassigned' 
, @proc_id int = null
, @rowcount int = null
with execute as 'dbo'
as

declare @unassigned nvarchar(50) = N'!unassigned'
, @procedure_name nvarchar(max)

if @procedure_name is null and @proc_id is not null
	set @procedure_name = quotename(object_schema_name(@proc_id)) + '.' + quotename(object_name(@proc_id))

declare @tail nvarchar(max) = concat(
									  ' [ ' + cast(@rowcount as nvarchar(max)) + '  rows]'
									, ' (SP: ' + @procedure_name + ')'
										)

select 
	  @p1 = iif(@p1 = @unassigned, cast(@p1_str as nvarchar(4000)), @p1)
	, @p2 = iif(@p2 = @unassigned, cast(@p2_str as nvarchar(4000)), @p2)
	, @p3 = iif(@p3 = @unassigned, cast(@p3_str as nvarchar(4000)), @p3)
	, @p4 = iif(@p4 = @unassigned, cast(@p4_str as nvarchar(4000)), @p4)

select @message = test.format_message(@message, @p1, @p2, @p3, @p4)

set @message = concat(
					upper(@severity)
				, ': '
				, replace(@message, '%', '%%')
				)

declare @is_data_big bit = iif(len(@data) > 2048 - len(@message) or charindex(nchar(13), @data) > 0
								, 1, 0)

set @message = left(
				concat(
					@message
				, case when @data is not null then ': ' end
				, case when @is_data_big = 0 then replace(@data, '%', '%%') + ' ' end
				)
			, 2048 - len(@tail))
			+ @tail

raiserror(@message, 0, 1) with nowait

if @is_data_big = 1 begin
	declare @i int = 0
	while @i < len(@data) begin
		declare @data_chunk nvarchar(4000) = substring(@data, @i + 1, 4000)
		print(@data_chunk)
		set @i += 4000
	end
end