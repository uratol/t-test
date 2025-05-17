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
set xact_abort off

declare @full_proc_name nvarchar(max)
, @log_message nvarchar(max) 

set @limit_failed = isnull(@limit_failed, 1000000)

if @log_proc_name is null set @log_proc_name = 'test.log'

if @@trancount > 0
	exec test.throw @message = 'Tests cannot be run in transaction'
	              , @proc_id = @@procid;

declare @results table(
    test_name nvarchar(450) primary key
  , is_failed int default 0
  , is_error int default 0
  , is_success int default 0
  , message nvarchar(max)
  , line_no int
  , check(is_failed + is_error + is_success = 1)
  , duration_millis int not null
)

declare @is_fail int
, @fail_message nvarchar(max)
, @fail_message_start int
, @fail_message_tag nvarchar(max) = 'Unit-test fail:'
, @fail_message_tail nvarchar(max) = ''' to data type int.'
, @start_time datetime

declare c cursor local fast_forward for
	select t.test_proc_full_name
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
open c
while 1 = 1 begin
	fetch c into @full_proc_name

	if @@fetch_status <> 0 break
	
	if @before_callback is not null begin
		exec sys.sp_executesql @stmt = @before_callback
		exec @log_proc_name @message = 'Call callbeck before test running', @data = @before_callback, @rowcount = @@rowcount, @proc_id = @@procid
	end

	print '################################################################################################
Running ' + @full_proc_name
	
	begin try

		set @start_time = getutcdate()
	
		exec @full_proc_name
		
		insert @results(test_name, is_success, duration_millis)
		select @full_proc_name, 1, datediff(millisecond, @start_time, getutcdate())
	end try
	begin catch
		
		if @@trancount > 0 
			rollback tran

		set @fail_message = error_message()

		set @fail_message_start = charindex(@fail_message_tag, @fail_message)

		if @fail_message_start > 0
			select @is_fail = 1
				, @fail_message = substring(@fail_message
											, @fail_message_start + len(@fail_message_tag)
											, len(@fail_message) - len(@fail_message_tail) - @fail_message_start - len(@fail_message_tag) + 1
											)
		else
			set @is_fail = 0

		insert @results(test_name, is_failed, is_error, message, line_no, duration_millis)
			select @full_proc_name, @is_fail, 1 - @is_fail, @fail_message, error_line(), datediff(millisecond, @start_time, getutcdate())

		declare @test_proc_id int = object_id(@full_proc_name)

		exec @log_proc_name @message = 'TEST FAILED %1: %2', @p1_str = @full_proc_name, @p2_str = @fail_message, @proc_id = @test_proc_id, @severity = 'error'

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
from @results
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
				, 'Line: ', right(concat('     ', line_no), 5)
				, ' | '
				, message
				)
		end
		, @brln
		)
from @results

select @log_message = concat(
	@all, ' tests of ', count(*), ' executed. Succeded: ', @succeded, ', failed: ', @failed,', errors: ', @errors)
from test.test

select t.test_proc_name as [test]
	, format(r.duration_millis / 1000.0, '#0.0') as [duration, s]
	, r.is_success
	, r.is_failed
	, r.is_error
from test.test as t
	join @results as r on r.test_name = t.test_proc_full_name
order by r.duration_millis desc

select t.tested_object_main_schema_name as [schema]
	, format(sum(r.duration_millis) / 1000.0, '#0.0') as [duration, s]
from test.test as t
		join @results as r on r.test_name = t.test_proc_full_name
group by t.tested_object_main_schema_name
order by sum(r.duration_millis) desc

exec @log_proc_name @message = @log_message
	, @severity = 'Info'
	, @proc_id = @@procid

if @error_message is not null 
	exec test.throw @message = @error_message
	              , @proc_id = @@procid