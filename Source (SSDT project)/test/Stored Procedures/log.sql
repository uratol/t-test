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
				, @message
				)

declare @is_data_big bit = iif(datalength(@data) + datalength(@message) + datalength(@tail) + 6 > 2044 * 2
								or charindex(nchar(13), @data) > 0
								, 1, 0)

declare @message_limit int = 2044 - datalength(@tail) / 2
set @message = left(
				concat(
					@message
				, case when @data is not null then ': ' end
				, case when @is_data_big = 0 then @data + ' ' end
				) collate Latin1_General_100_BIN2
			, @message_limit)
if unicode(right(@message collate Latin1_General_100_BIN2, 1)) between 55296 and 56319
	set @message = left(@message collate Latin1_General_100_BIN2, datalength(@message) / 2 - 1)
set @message += @tail

raiserror(N'%s', 0, 1, @message) with nowait

if @is_data_big = 1 begin
	-- Count UTF-16 units explicitly and keep surrogate pairs within the same chunk.
	declare @i int = 0, @data_length int = datalength(@data) / 2
	while @i < @data_length begin
		declare @data_chunk nvarchar(4000) = substring(@data collate Latin1_General_100_BIN2, @i + 1, 4000)
		if @i + datalength(@data_chunk) / 2 < @data_length
			and unicode(right(@data_chunk collate Latin1_General_100_BIN2, 1)) between 55296 and 56319
			set @data_chunk = left(@data_chunk collate Latin1_General_100_BIN2, 3999)
		print(@data_chunk)
		set @i += datalength(@data_chunk) / 2
	end
end