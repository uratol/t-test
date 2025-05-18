SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;

SET NUMERIC_ROUNDABORT OFF;
GO

GO
PRINT N'Creating Schema [test]...';


GO
CREATE SCHEMA [test]
    AUTHORIZATION [dbo];


GO
PRINT N'Creating Schema [tests]...';


GO
CREATE SCHEMA [tests]
    AUTHORIZATION [dbo];


GO
PRINT N'Creating View [test].[test]...';


GO
CREATE view [test].[test]
as
select concat(quotename(s.name), '.', quotename(p.name))
	   as test_proc_full_name
	 , quotename(parsed.tested_object_schema_name) + '.' + quotename(parsed.tested_object_name)
	   as tested_object_full_name
	 , parsed.tested_object_schema_name
	 , parsed.tested_object_name
	 , iif(const.action_separator_index > 0, stuff(p.name, 1, const.action_separator_index, '')
	   , null
	   )	  as tested_action
	 , p.name as test_proc_name
	 , case 
			when parsed.tested_object_schema_name = 'private' then
				parsename(parsed.tested_object_name, 2)
			else parsed.tested_object_schema_name 
		end as tested_object_main_schema_name
from sys.procedures as p
	join sys.schemas as s
		on p.schema_id = s.schema_id
	outer apply (
		select charindex('.', p.name) as schema_separator_index
			 , charindex('@', p.name) as action_separator_index) as const
	outer apply (
		select iif(const.schema_separator_index > 0, left(p.name, const.schema_separator_index - 1), null) as tested_object_schema_name
			 , case when const.schema_separator_index > 0 then
			     substring(p.name
				   , const.schema_separator_index + 1
				   , len(p.name) - const.schema_separator_index
				   - iif(const.action_separator_index > 0
				   , len(p.name) - const.action_separator_index + 1
				   , 0)
				   )
			   end
			   as tested_object_name) as parsed
where s.name = 'tests'
GO
PRINT N'Creating Function [test].[throw_error]...';


GO
CREATE function [test].[throw_error](
 @error_message nvarchar(max)
)
-- Throws exception from a function
returns nvarchar(max)
as
begin
	if @error_message is not null
		return cast(left(@error_message, 4000) as int)

	return null
end
GO
PRINT N'Creating Function [test].[assert_error_like]...';


GO
CREATE function [test].[assert_error_like](
  @message nvarchar(max)
, @pattern nvarchar(max)
)
returns int
as
begin
	declare @actual_error_message nvarchar(max) = error_message()

	if @actual_error_message is null
			or @actual_error_message like '%<<No error>>%'
			or @actual_error_message not like @pattern
		return test.throw_error(
			concat(@message + '. '
				, 'Error pattern "', @pattern, '" expected. '
				, 'Got error: ', isnull('"' + @actual_error_message + '"', '<null>'))
			)
	return null
end
GO
PRINT N'Creating Function [test].[assert_error_number]...';
GO
create function [test].[assert_error_number]
(
    @message nvarchar(max) -- Human-friendly description
  , @expected_number int   -- Number you expect ERROR_NUMBER() to return
)
returns int
as
begin
    declare @actual_number int = error_number(); -- inside CATCH

    if @actual_number is null
	       or @actual_number is distinct from @expected_number
        return test.throw_error(concat(
                                          @message
                                        , '. '
                                        , 'Error number '
                                        , @expected_number
                                        , ' expected. '
                                        , 'Got '
                                        , isnull(cast(@actual_number as nvarchar), '<null>')
                                      )
                               );

    return null; -- assertion passed
end
GO

PRINT N'Creating Function [test].[error]...';


GO
CREATE function [test].[error]()
returns nvarchar(max)
as
begin
	
	return test.throw_error('<<No error>>')

end
GO
PRINT N'Creating Function [test].[fail]...';


GO
CREATE function [test].[fail](
@message nvarchar(max)
)
returns int
as
begin
	return test.throw_error(concat('Unit-test fail: ', @message))
end
GO
PRINT N'Creating Function [test].[normalize_json]...';


GO
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
GO
PRINT N'Creating Function [test].[format_message]...';


GO
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
GO
PRINT N'Creating Function [test].[assert_not_null]...';


GO
create function test.assert_not_null
(@message nvarchar(max)
,@value varbinary(max)
)
returns nvarchar(max)
as
begin

return iif(@value is null, test.fail(@message), '')

end
GO
PRINT N'Creating Function [test].[assert_null]...';


GO
create function [test].[assert_null]
(@message nvarchar(max)
,@value varbinary(max)
)
returns nvarchar(max)
as
begin

return iif(@value is not null, test.fail(@message), '')

end
GO
PRINT N'Creating Function [test].[is_equal]...';


GO
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
GO
PRINT N'Creating Function [test].[assert_equals]...';


GO
CREATE function [test].[assert_equals]
( @message nvarchar(max)
, @expected nvarchar(max)
, @actual nvarchar(max)
)
returns nvarchar(max)
as
begin
	
	if [test].[is_equal](@expected, @actual) = 1
		return ''

	return test.fail(@message + char(13)+char(10)+
					'expected: ' + isnull('<'+@expected+'>', 'null') +
					char(13)+char(10)+
					'but was : ' + isnull('<'+@actual+'>', 'null'))
	
end
GO
PRINT N'Creating Procedure [test].[log]...';


GO
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
GO
PRINT N'Creating Procedure [tests].[test.format_message]...';


GO
CREATE procedure [tests].[test.format_message]
as
begin tran
	
	select test.assert_equals('NULL should returns NULL'
		, null
		, test.format_message(null, 1, 2, 3, 4)
		)

	select test.assert_equals('String should be substituted'
		, 'Hello world'
		, test.format_message('Hello %1', 'world', null, null, null)
		)

	declare @now datetime = getutcdate()
	select test.assert_equals('Datetime should be substituted'
		, concat('Hello at ', convert(nvarchar(10), @now, 101), ' ', convert(nvarchar(5), @now, 114))
		, test.format_message('Hello at %2', null, @now, null, null)
		)

	select test.assert_equals('Binary should be substituted'
		, 'Hello binary: 0x010203'
		, test.format_message('Hello binary: %1', 0x010203, null, null, null)
		)


rollback
GO
PRINT N'Creating Procedure [tests].[test.test]...';


GO
CREATE procedure [tests].[test.test]
as
begin tran

	
	exec('create proc [tests].[temp-t-test.p1]
	as')

	exec('create proc [tests].[temp-t-test.p2]
	as')

	select test.assert_equals('View [test].[test] should return the tests (stored procedures in the schema [tests])'
		, (
			select *
			from (values
					( N'[tests].[temp-t-test.p1]', N'[temp-t-test].[p1]', N'temp-t-test', N'p1', NULL, N'temp-t-test.p1'),
					( N'[tests].[temp-t-test.p2]', N'[temp-t-test].[p2]', N'temp-t-test', N'p2', NULL, N'temp-t-test.p2')
				) as v(test_proc_full_name
					, tested_object_full_name
					, tested_object_schema_name
					, tested_object_name
					, tested_action
					, test_proc_name)
			for json path
			)
		, (
			select test_proc_full_name
				, tested_object_full_name
				, tested_object_schema_name
				, tested_object_name
				, tested_action
				, test_proc_name
			from test.test
			where tested_object_schema_name = 'temp-t-test'
			for json path
			)
	)

rollback
GO
PRINT N'Creating Procedure [tests].[test.test@name_convention]...';


GO
create proc [tests].[test.test@name_convention]
as

select test.fail('Every tests should refer to the existing objects: ' + string_agg(test_proc_full_name, ', '))
from test.test as t
where object_id(t.tested_object_full_name) is null
	and (
		not exists(
			select * from sys.triggers as tr where tr.name = t.tested_object_name
		)
		or t.tested_object_schema_name is distinct from 'DDL trigger'
		)
having count(*) > 0
GO
PRINT N'Creating Procedure [test].[throw]...';


GO
CREATE proc [test].[throw]
  @message nvarchar(max)
, @proc_id int = null
as

	declare @err_num int = 70000

	if @proc_id is not null
	begin
		set @message += concat('
<Procedure:> ', isnull(
		quotename(
		object_schema_name(@proc_id)
		)
		+ '.'
		+ quotename(
		object_name(@proc_id)
		)
		, @proc_id)
		);
	end

	exec test.log @message = @message, @severity = 'error', @proc_id = @proc_id;

	set @message = replace(@message, '%', '%%');

	throw @err_num, @message, 1;
GO
PRINT N'Creating Procedure [test].[run]...';


GO
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
GO
PRINT N'Creating Procedure [tests].[test.throw]...';


GO
CREATE proc [tests].[test.throw]
as
begin tran

begin try
	exec test.throw @message = 'Test exception!' -- nvarchar(max)
              , @proc_id = @@procid

    exec test.error
end try
begin catch

	select test.assert_error_like('Thrown exception should contain the message', 'Test exception!%')

	select test.assert_error_like('Thrown exception should contain the called procedure name separated by <Procedure:> tag'
		, concat('%'
			, '<Procedure:>' 
			, '%'
			, 
				quotename(object_schema_name(@@procid))
					, '.'
				, quotename(object_name(@@procid))
			, '%'
			)
		)

end catch

rollback
GO
PRINT N'Installation complete.';
GO
PRINT N'Run tests';
GO
exec test.run
GO
PRINT N'Installation and tests complete.';
GO
