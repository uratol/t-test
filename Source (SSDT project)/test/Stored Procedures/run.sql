CREATE proc [test].[run]
  @test_names nvarchar(max) = null -- | separated
, @exclude_test_names nvarchar(max) = null -- | separated
, @schemas nvarchar(256) = null
, @exclude_schemas nvarchar(256) = null
, @limit_failed int = null
, @before_callback nvarchar(max) = null
, @log_proc_name nvarchar(256) = null
as

set nocount on

declare @proc_id int = object_id(N'[test].[run]')
	, @engine_edition int = cast(serverproperty('EngineEdition') as int)
	, @error_line int

declare @full_proc_name nvarchar(max)
, @log_message nvarchar(max) 

set @limit_failed = isnull(@limit_failed, 1000000)

if @log_proc_name is null set @log_proc_name = 'test.log'

if @@trancount > 0
	exec test.throw @message = 'Tests cannot be run in transaction'
	              , @proc_id = @proc_id;

declare @scope nvarchar(4000) = convert(nvarchar(4000), session_context(N'ttest:vectors:scope'))
if @scope is null set @scope = N'global'
if not (
	(@scope collate Latin1_General_100_BIN2 = N'session' and datalength(@scope) = 14)
	or (@scope collate Latin1_General_100_BIN2 = N'global' and datalength(@scope) = 12))
	exec test.throw @message = N'Vector scope must be exactly session or global.';

-- NULL names and duplicate results raise 50000 instead of table constraint errors.
declare @results nvarchar(max) = N'[]'
	, @test_list nvarchar(max)
	, @available_count int = (select count(*) from test.test)

declare @is_fail int
, @fail_message nvarchar(max)
, @fail_message_start int
, @fail_message_tag nvarchar(max) = 'Unit-test fail:'
, @fail_message_prefix nvarchar(max) = N'Conversion failed when converting the nvarchar value '''
, @fail_message_tail nvarchar(max) = ''' to data type int.'
, @start_time datetime
, @duration_millis int

	select @test_list = concat(N'[', string_agg(
		cast(json_object('test_proc_full_name': t.test_proc_full_name,
			'display_name': t.test_proc_name,
			'main_schema': t.tested_object_main_schema_name) as nvarchar(max)), N','), N']')
	from test.test as t
		full join string_split(@test_names, '|') as ss on coalesce(
															  object_id(trim(ss.value))
															, object_id(concat('[test].', trim(ss.value)))
															, object_id(concat('[test].', quotename(trim(ss.value))))
															) = object_id(t.test_proc_full_name)
		full join string_split(@exclude_test_names, '|') as ex on coalesce(
															  object_id(trim(ex.value))
															, object_id(concat('[test].', trim(ex.value)))
															, object_id(concat('[test].', quotename(trim(ex.value))))
															) = object_id(t.test_proc_full_name)
	where (@test_names is null
		or ss.value is not null
		)
		and (@schemas is null
			or exists(
				select *
				from string_split(@schemas, ',') as ss
				where trim(ss.value) = t.tested_object_main_schema_name
				)
			)
		and (@exclude_schemas is null
			or not exists(
				select *
				from string_split(@exclude_schemas, ',') as ss
				where trim(ss.value) = t.tested_object_main_schema_name
				)
			)
		and (
			@exclude_test_names is null
			or ex.value is null
			)
declare @test_no bigint = 0
	, @test_count bigint = (select count_big(*) from openjson(@test_list))
	, @snapshot nvarchar(max) = N'[]'
	, @rows nvarchar(max)
	, @snapshot_sql nvarchar(max)
	, @vector_table nvarchar(128) = case when @scope = N'session'
		then N'#test_vectors' else N'[test].[test_vectors]' end
	, @vector_table_id int = case when @scope = N'session'
		then object_id(N'tempdb..#test_vectors') else object_id(N'[test].[test_vectors]', N'U') end
	, @has_vectors bit = 0
	, @selected_count bigint = 0
	, @planned_count bigint = 0
	, @case_count bigint
	, @case_no bigint
	, @invocation_no bigint = 0
	, @parameters nvarchar(max)
	, @call nvarchar(max)
	, @display_name nvarchar(max)
	, @case_label nvarchar(max)
	, @main_schema nvarchar(max)
	, @is_vector bit
	, @stop bit = 0

-- Keep the registry snapshot in scalar JSON, independent of test-owned transactions.
if @vector_table_id is not null
	set @snapshot_sql = N'SELECT @rows = CONCAT(N''['', STRING_AGG(
		CAST(JSON_OBJECT(''parameters'': CONVERT(nvarchar(max), parameters)) AS nvarchar(max)),
		N'',''), N'']'') FROM ' + @vector_table + N'
		WHERE CONVERT(nvarchar(max), procedure_name) COLLATE Latin1_General_100_BIN2
			= @name COLLATE Latin1_General_100_BIN2;'

while @test_no < @test_count begin
	select @full_proc_name = test_proc_full_name
	from openjson(@test_list, concat('$[', @test_no, ']'))
		with (test_proc_full_name nvarchar(max))
	set @rows = null
	select @rows = cases
	from openjson(@snapshot)
		with (procedure_name nvarchar(max), cases nvarchar(max) as json)
	where procedure_name collate Latin1_General_100_BIN2
		= @full_proc_name collate Latin1_General_100_BIN2

	if @rows is null begin
		set @rows = N'[]'
		if @snapshot_sql is not null and @full_proc_name is not null
			exec sys.sp_executesql @snapshot_sql,
				N'@name nvarchar(max), @rows nvarchar(max) OUTPUT',
				@name = @full_proc_name, @rows = @rows output
		if @full_proc_name is not null begin
			set @selected_count += 1
			set @snapshot = json_modify(@snapshot, 'append $', json_query(json_object(
				'procedure_name': @full_proc_name, 'cases': json_query(@rows))))
		end
	end

	set @case_count = (select count_big(*) from openjson(@rows))
	if @case_count > 0 set @has_vectors = 1
	else set @case_count = 1
	if @planned_count > 9223372036854775807 - @case_count
		exec test.throw @message = N'Planned vector case count exceeds BIGINT.';
	set @planned_count += @case_count
	set @test_no += 1
end
set @test_no = 0

while @test_no < @test_count begin
	select @full_proc_name = test_proc_full_name, @display_name = display_name, @main_schema = main_schema
	from openjson(@test_list, concat('$[', @test_no, ']'))
		with (test_proc_full_name nvarchar(max), display_name nvarchar(max), main_schema nvarchar(max))

	set @test_no += 1
	set @rows = N'[]'
	select @rows = cases
	from openjson(@snapshot)
		with (procedure_name nvarchar(max), cases nvarchar(max) as json)
	where procedure_name collate Latin1_General_100_BIN2
		= @full_proc_name collate Latin1_General_100_BIN2
	set @case_count = (select count_big(*) from openjson(@rows))
	set @is_vector = iif(@case_count > 0, 1, 0)
	if @is_vector = 0 set @case_count = 1
	set @case_no = 0

	while @case_no < @case_count begin
		set @parameters = null
		if @is_vector = 1
			select @parameters = parameters
			from openjson(@rows, concat('$[', @case_no, ']'))
				with (parameters nvarchar(max))
		set @call = N'EXEC ' + @full_proc_name
			+ case when @is_vector = 1 then N' ' + @parameters else N'' end + N';'
		set @case_label = case when @is_vector = 1
			then concat(@display_name, N' (', @parameters, N')') else @display_name end
		set @case_no += 1
		if @invocation_no = 9223372036854775807
			exec test.throw @message = N'Vector invocation count exceeds BIGINT.';
		set @invocation_no += 1
	
	if @before_callback is not null begin
		begin try
			exec sys.sp_executesql @stmt = @before_callback
			exec @log_proc_name @message = 'Call callbeck before test running', @data = @before_callback, @rowcount = @@rowcount, @proc_id = @proc_id
		end try
		begin catch
			if @@trancount > 0 rollback;
			throw;
		end catch
	end

	print '################################################################################################
Running ' + @full_proc_name

	if @is_vector = 1 begin
		set @log_message = concat(N'Start exec source=explicit invocation=', @invocation_no)
		exec @log_proc_name @message = @log_message, @data = @call, @proc_id = @proc_id
	end
	
	begin try

		set @start_time = getutcdate()
	
		if @is_vector = 1
			exec sys.sp_executesql @stmt = @call
		else
			exec @full_proc_name

		set @duration_millis = datediff(millisecond, @start_time, getutcdate())
		
		if @full_proc_name is null
			raiserror('Test name cannot be NULL', 16, 2);

		if exists(select 1 from openjson(@results)
			with (test_name nvarchar(max), selection_entry_index bigint)
			where test_name collate Latin1_General_100_BIN2 = @full_proc_name collate Latin1_General_100_BIN2
				and selection_entry_index <> @test_no)
			raiserror('Duplicate test result', 14, 1);

		set @results = json_modify(@results, 'append $', json_query(json_object(
			  'test_name': @full_proc_name
			, 'selection_entry_index': @test_no
			, 'invocation_no': @invocation_no
			, 'source': iif(@is_vector = 1, N'explicit', N'static')
			, 'call': @call
			, 'display_name': @case_label
			, 'main_schema': @main_schema
			, 'is_failed': 0
			, 'is_error': 0
			, 'is_success': 1
			, 'duration_millis': @duration_millis)))

		set @log_message = concat('[PASS] Duration ',
			cast(@duration_millis / 1000.0 as decimal(12, 1)), 'sec')
		raiserror(@log_message, 0, 1) with nowait;
	end try
	begin catch

		set @duration_millis = datediff(millisecond, @start_time, getutcdate())
		
		if @@trancount > 0 
			rollback tran

		set @fail_message = error_message()
		set @error_line = null
		-- Keep unsupported diagnostics out of Fabric's compiled procedure body.
		if @engine_edition <> 11
			exec sys.sp_executesql N'SET @line_no = ERROR_LINE();',
				N'@line_no int OUTPUT', @line_no = @error_line output

		set @fail_message_start = charindex(@fail_message_tag, @fail_message)

		if error_number() = 245
			and @fail_message_start = len(@fail_message_prefix) + 1
			and left(@fail_message, len(@fail_message_prefix)) = @fail_message_prefix
			select @is_fail = 1
				, @fail_message = substring(@fail_message
											, @fail_message_start + len(@fail_message_tag)
											, len(@fail_message) - @fail_message_start - len(@fail_message_tag) + 1
												- case when right(@fail_message, len(@fail_message_tail)) = @fail_message_tail
													then len(@fail_message_tail) else 0 end
											)
		else
			set @is_fail = 0

		if @full_proc_name is null
		begin
			if @has_vectors = 1
				throw 50000, 'Test name cannot be NULL', 2;
			raiserror('Test name cannot be NULL', 16, 2);
		end
		else if exists(select 1 from openjson(@results)
			with (test_name nvarchar(max), selection_entry_index bigint)
			where test_name collate Latin1_General_100_BIN2 = @full_proc_name collate Latin1_General_100_BIN2
				and selection_entry_index <> @test_no)
		begin
			if @has_vectors = 1
				throw 50000, 'Duplicate test result', 1;
			raiserror('Duplicate test result', 14, 1);
		end
		else
			set @results = json_modify(@results, 'append $', json_query(json_object(
				  'test_name': @full_proc_name
				, 'selection_entry_index': @test_no
				, 'invocation_no': @invocation_no
				, 'source': iif(@is_vector = 1, N'explicit', N'static')
				, 'call': @call
				, 'display_name': @case_label
				, 'main_schema': @main_schema
				, 'is_failed': @is_fail
				, 'is_error': 1 - @is_fail
				, 'is_success': 0
				, 'message': @fail_message
				, 'line_no': @error_line
				, 'duration_millis': @duration_millis)))

		declare @test_proc_id int = object_id(@full_proc_name)

		set @log_message = concat('[FAIL] Duration ',
			cast(@duration_millis / 1000.0 as decimal(12, 1)), 'sec %1: %2')
		if @is_vector = 0
			exec @log_proc_name @message = @log_message, @p1_str = @full_proc_name, @p2_str = @fail_message, @proc_id = @test_proc_id, @severity = 'error'

		if @limit_failed > 0 begin
			set @limit_failed -= 1
			if @limit_failed = 0
				set @stop = 1
		end
	end catch

	if @is_vector = 1 begin
		declare @outcome nvarchar(8)
		select @outcome = case when is_success = 1 then N'PASS'
			when is_failed = 1 then N'FAILED' else N'ERROR' end
		from openjson(@results, concat('$[', @invocation_no - 1, ']'))
			with (is_success int, is_failed int)
		set @log_message = concat(N'Completed exec source=explicit invocation=', @invocation_no, N' ', @outcome)
		declare @completion_data nvarchar(max) = @call
		declare @completion_severity nvarchar(8) = iif(@outcome = N'PASS', N'debug', N'error')
		if @outcome <> N'PASS' set @completion_data += NCHAR(10) + N'Message: ' + @fail_message
		exec @log_proc_name @message = @log_message, @data = @completion_data,
			@proc_id = @proc_id, @severity = @completion_severity
	end
	if @stop = 1 break;
	end
	if @stop = 1 break;
end

if @has_vectors = 1 begin
	declare @vector_failed bigint, @vector_errors bigint, @vector_success bigint
	select @vector_failed = sum(convert(bigint, is_failed)),
		@vector_errors = sum(convert(bigint, is_error)), @vector_success = sum(convert(bigint, is_success))
	from openjson(@results)
		with (is_failed int, is_error int, is_success int)

	select display_name as [test],
		format(duration_millis / 1000.0, '#0.0') as [duration, s],
		iif(is_success = 1, 'PASS', 'FAIL') as [status],
		case when is_success = 0 then concat(
			iif(is_failed = 1, N'Assertion failed: ', N'Unexpected exception: '),
			ltrim(message)) end as [failure_reason]
	from openjson(@results)
		with (display_name nvarchar(max),
			duration_millis int, is_success int, is_failed int, message nvarchar(max))
	order by duration_millis desc

	select main_schema as [schema], format(sum(convert(bigint, duration_millis)) / 1000.0, '#0.0') as [duration, s]
	from openjson(@results)
		with (main_schema nvarchar(max), duration_millis int)
	group by main_schema
	order by sum(convert(bigint, duration_millis)) desc

	set @log_message = concat(@selected_count, N' procedures selected. Planned cases: ', @planned_count,
		N', executed cases: ', @invocation_no, N'. Succeded: ', @vector_success,
		N', failed: ', @vector_failed, N', errors: ', @vector_errors)
	exec @log_proc_name @message = @log_message, @severity = 'Info', @proc_id = @proc_id
	if @vector_failed + @vector_errors > 0
		exec test.throw @message = N'Vector test run failed; see result rows and completed-call logs.',
			@proc_id = @proc_id;
	return
end

declare 
  @all int
, @failed int
, @errors int
, @succeded int
, @error_message nvarchar(max)
, @max_len_fail_test_name int 
, @brln nvarchar(64) = '
'

select @max_len_fail_test_name = max(len(test_name)) 
from openjson(@results)
	with (test_name nvarchar(450), is_success int)
where is_success = 0

select @all = count(*)
	, @failed = sum(is_failed)
	, @errors = sum(is_error)
	, @succeded = sum(is_success)
	, @error_message = string_agg(
		case when is_success = 0 then 
			concat(
				  test_name
				, replicate(' ', @max_len_fail_test_name - len(test_name))
				, ' | '
				, iif(is_failed = 1, 'FAILED', 'ERROR ')
				, ' | '
				, 'Line: ', case when line_no is null then '  N/A' else right(concat('     ', line_no), 5) end
				, ' | '
				, message
				)
		end
		, @brln
		)
from openjson(@results)
	with (test_name nvarchar(450), is_failed int, is_error int, is_success int, message nvarchar(max), line_no int)

set @log_message = concat(
	@all, ' tests of ', @available_count, ' executed. Succeded: ', @succeded, ', failed: ', @failed,', errors: ', @errors)

select isnull(r.display_name, N'') as [test]
	, format(r.duration_millis / 1000.0, '#0.0') as [duration, s]
	, iif(r.is_success = 1, 'PASS', 'FAIL') as [status]
	, case when r.is_success = 0 then concat(
		iif(r.is_failed = 1, N'Assertion failed: ', N'Unexpected exception: '),
		ltrim(r.message)) end as [failure_reason]
from openjson(@results)
	with (display_name nvarchar(128), duration_millis int, is_success int, is_failed int, message nvarchar(max)) as r
order by r.duration_millis desc

select r.main_schema as [schema]
	, format(sum(r.duration_millis) / 1000.0, '#0.0') as [duration, s]
from openjson(@results)
	with (main_schema nvarchar(128), duration_millis int) as r
group by r.main_schema
order by sum(r.duration_millis) desc

exec @log_proc_name @message = @log_message
	, @severity = 'Info'
	, @proc_id = @proc_id

if @error_message is not null 
	exec test.throw @message = @error_message
	              , @proc_id = @proc_id