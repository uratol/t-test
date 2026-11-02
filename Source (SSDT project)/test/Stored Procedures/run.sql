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

-- NULL names and duplicate results raise 50000 instead of table constraint errors.
declare @results nvarchar(max) = N'[]'
	, @test_list nvarchar(max)

declare @is_fail int
, @fail_message nvarchar(max)
, @fail_message_start int
, @fail_message_tag nvarchar(max) = 'Unit-test fail:'
, @fail_message_prefix nvarchar(max) = N'Conversion failed when converting the nvarchar value '''
, @fail_message_tail nvarchar(max) = ''' to data type int.'
, @start_time datetime
, @duration_millis int

	select @test_list = concat(N'[', string_agg(
		json_object('test_proc_full_name': t.test_proc_full_name), N','), N']')
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

while @test_no < @test_count begin
	select @full_proc_name = test_proc_full_name
	from openjson(@test_list, concat('$[', @test_no, ']'))
		with (test_proc_full_name nvarchar(max))

	set @test_no += 1
	
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
	
	begin try

		set @start_time = getutcdate()
	
		exec @full_proc_name

		set @duration_millis = datediff(millisecond, @start_time, getutcdate())
		
		if @full_proc_name is null
			raiserror('Test name cannot be NULL', 16, 2);

		if exists(select 1 from openjson(@results) with (test_name nvarchar(450)) where test_name = @full_proc_name)
			raiserror('Duplicate test result', 14, 1);

		set @results = json_modify(@results, 'append $', json_query(json_object(
			  'test_name': @full_proc_name
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
			raiserror('Test name cannot be NULL', 16, 2);
		else if exists(select 1 from openjson(@results) with (test_name nvarchar(450)) where test_name = @full_proc_name)
			raiserror('Duplicate test result', 14, 1);
		else
			set @results = json_modify(@results, 'append $', json_query(json_object(
				  'test_name': @full_proc_name
				, 'is_failed': @is_fail
				, 'is_error': 1 - @is_fail
				, 'is_success': 0
				, 'message': @fail_message
				, 'line_no': @error_line
				, 'duration_millis': @duration_millis)))

		declare @test_proc_id int = object_id(@full_proc_name)

		set @log_message = concat('[FAIL] Duration ',
			cast(@duration_millis / 1000.0 as decimal(12, 1)), 'sec %1: %2')
		exec @log_proc_name @message = @log_message, @p1_str = @full_proc_name, @p2_str = @fail_message, @proc_id = @test_proc_id, @severity = 'error'

		set @limit_failed -= 1

		if @limit_failed = 0
			break;
	end catch

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

select @log_message = concat(
	@all, ' tests of ', count(*), ' executed. Succeded: ', @succeded, ', failed: ', @failed,', errors: ', @errors)
from test.test

select t.test_proc_name as [test]
	, format(r.duration_millis / 1000.0, '#0.0') as [duration, s]
	, iif(r.is_success = 1, 'PASS', 'FAIL') as [status]
	, case when r.is_success = 0 then concat(
		iif(r.is_failed = 1, N'Assertion failed: ', N'Unexpected exception: '),
		ltrim(r.message)) end as [failure_reason]
from test.test as t
	join openjson(@results)
		with (test_name nvarchar(450), duration_millis int, is_success int, is_failed int, message nvarchar(max)) as r
		on r.test_name = t.test_proc_full_name
order by r.duration_millis desc

select t.tested_object_main_schema_name as [schema]
	, format(sum(r.duration_millis) / 1000.0, '#0.0') as [duration, s]
from test.test as t
		join openjson(@results)
			with (test_name nvarchar(450), duration_millis int) as r on r.test_name = t.test_proc_full_name
group by t.tested_object_main_schema_name
order by sum(r.duration_millis) desc

exec @log_proc_name @message = @log_message
	, @severity = 'Info'
	, @proc_id = @proc_id

if @error_message is not null 
	exec test.throw @message = @error_message
	              , @proc_id = @proc_id