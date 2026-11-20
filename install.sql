-- Existing framework objects are updated; existing user tests are retained.
-- Isolate native XACT_ABORT while raising guards caught by an outer TRY/CATCH.
IF @@TRANCOUNT > 0
BEGIN
	IF CAST(SERVERPROPERTY('EngineEdition') AS int) = 11
		RAISERROR(N'Run install.sql outside a transaction.', 16, 1);
	ELSE
		EXEC sys.sp_executesql N'SET XACT_ABORT OFF; RAISERROR(N''Run install.sql outside a transaction.'', 16, 1);';
	RETURN;
END;
SET ANSI_NULLS, ANSI_PADDING, ANSI_WARNINGS, ARITHABORT, CONCAT_NULL_YIELDS_NULL, QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

IF SCHEMA_ID(N'test') IS NULL
	EXEC(N'CREATE SCHEMA [test] AUTHORIZATION [dbo];');
IF SCHEMA_ID(N'tests') IS NULL
	EXEC(N'CREATE SCHEMA [tests] AUTHORIZATION [dbo];');
GO

IF OBJECT_ID(N'[test].[test_vectors]', N'U') IS NULL
	CREATE TABLE [test].[test_vectors] (
		procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
		parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
	);
GO

CREATE OR ALTER view [test].[test_procedures]
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
	 , s.name as test_proc_schema_name
	 , p.object_id as test_proc_id
from sys.procedures as p
	join sys.schemas as s
		on p.schema_id = s.schema_id
	outer apply (
		select charindex('.', left(p.name, charindex('@', p.name + '@') - 1)) as schema_separator_index
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
			   else left(p.name, iif(const.action_separator_index > 0, const.action_separator_index - 1, len(p.name)))
			   end
			   as tested_object_name) as parsed
GO

CREATE OR ALTER view [test].[test]
as
select test_proc_full_name, tested_object_full_name, tested_object_schema_name,
	tested_object_name, tested_action, test_proc_name, tested_object_main_schema_name
from test.test_procedures
where test_proc_schema_name = N'tests'
GO

IF OBJECT_ID(N'[test].[assert_equals]', N'FN') IS NOT NULL
	DROP FUNCTION [test].[assert_equals];
GO

IF OBJECT_ID(N'[test].[assert_float_equals]', N'FN') IS NOT NULL
	DROP FUNCTION [test].[assert_float_equals];
GO

IF OBJECT_ID(N'[test].[assert_null]', N'FN') IS NOT NULL
	DROP FUNCTION [test].[assert_null];
GO

IF OBJECT_ID(N'[test].[assert_not_null]', N'FN') IS NOT NULL
	DROP FUNCTION [test].[assert_not_null];
GO

IF OBJECT_ID(N'[test].[assert_error]', N'FN') IS NOT NULL
	DROP FUNCTION [test].[assert_error];
GO

IF OBJECT_ID(N'[test].[fail_no_error]', N'FN') IS NOT NULL
	DROP FUNCTION [test].[fail_no_error];
GO

CREATE OR ALTER function [test].[throw_error](
 @error_message nvarchar(max)
)
-- Throws exception from a function
returns nvarchar(max)
as
begin
	declare @return_value nvarchar(max)

	if @error_message is not null
	begin
		if try_cast(left(@error_message, 4000) as int) is not null
			set @error_message = N'Error: ' + @error_message -- Ensure numeric messages like N'123' also throw an exception.

		set @return_value = cast(left(@error_message, 4000) as int)
	end

	return @return_value
end
GO

CREATE OR ALTER function [test].[fail](
@message nvarchar(max)
)
returns int
as
begin
	return test.throw_error(concat('Unit-test fail: ', @message))
end
GO

CREATE OR ALTER function [test].[format_message]
(@message nvarchar(max)
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
		set @message = replace(@message, N'%1', cast(@p1 as nvarchar(4000)))
	if @p2 <> @unassigned
		set @message = replace(@message, N'%2', cast(@p2 as nvarchar(4000)))
	if @p3 <> @unassigned
		set @message = replace(@message, N'%3', cast(@p3 as nvarchar(4000)))
	if @p4 <> @unassigned
		set @message = replace(@message, N'%4', cast(@p4 as nvarchar(4000)))

	return @message
end
GO

CREATE OR ALTER function test.is_json_equal
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
GO

CREATE OR ALTER function test.is_equal
( @expected nvarchar(max)
, @actual nvarchar(max)
)
returns bit
as
begin
	declare @return_value bit = 0

	if (@expected is not distinct from @actual)
		set @return_value = 1
	else
	begin
		if len(@actual) + len(@expected) < 100 -- to avoid "string or binary data would be truncated" exception
			if try_cast(@expected as decimal(30, 20)) = try_cast(@actual as decimal(30, 20))
				-- Reject comparisons that lose nonzero fractional digits during conversion.
				and @expected not like N'%.' + replicate(N'[0-9]', 20) + N'%[1-9]%'
				and @actual not like N'%.' + replicate(N'[0-9]', 20) + N'%[1-9]%'
				set @return_value = 1

		if @return_value = 0
			if isjson(@expected) = 1
				if isjson(@actual) = 1
					-- Inlining can evaluate UDF calls before their enclosing branch.
					if test.is_json_equal(
						case when @return_value = 0 and isjson(@expected) = 1 and isjson(@actual) = 1 then @expected end,
						case when @return_value = 0 and isjson(@expected) = 1 and isjson(@actual) = 1 then @actual end) = 1
						set @return_value = 1
	end

	return @return_value
end
GO

CREATE OR ALTER FUNCTION [test].[is_equals]
(@expected nvarchar(max), @actual nvarchar(max))
RETURNS bit
AS
BEGIN
	RETURN test.is_equal(@expected, @actual);
END;
GO

CREATE OR ALTER FUNCTION [test].[is_float_equal]
(@expected float, @actual float, @tolerance float)
RETURNS bit
AS
BEGIN
	DECLARE @equal bit = 0;
	IF @tolerance IS NOT NULL AND @tolerance >= 0
	BEGIN
		IF @expected IS NULL AND @actual IS NULL
			SET @equal = 1;
		ELSE IF @expected IS NOT NULL AND @actual IS NOT NULL
		BEGIN
			IF (@expected < 0 AND @actual > 0) OR (@expected > 0 AND @actual < 0)
			BEGIN
				-- Subtracting opposite-sign values can overflow FLOAT.
				IF ABS(@actual) <= @tolerance - ABS(@expected)
					AND ABS(@expected) <= @tolerance - ABS(@actual)
					SET @equal = 1;
			END
			ELSE IF ABS(@expected - @actual) <= @tolerance
				SET @equal = 1;
		END;
	END;
	RETURN @equal;
END;
GO

CREATE OR ALTER FUNCTION [test].[is_null](@value varbinary(max))
RETURNS bit
AS
BEGIN
	RETURN CASE WHEN @value IS NULL THEN 1 ELSE 0 END;
END;
GO

CREATE OR ALTER FUNCTION [test].[is_not_null](@value varbinary(max))
RETURNS bit
AS
BEGIN
	RETURN CASE WHEN @value IS NOT NULL THEN 1 ELSE 0 END;
END;
GO

CREATE OR ALTER proc [test].[throw]
  @message nvarchar(max)
, @proc_id int = null
, @error_number int = 70000
as

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

	set @message = replace(@message, '%', '%%');

	throw @error_number, @message, 1;
GO

CREATE OR ALTER PROC [test].[fail_no_error]
AS
BEGIN
	SET NOCOUNT ON;
	EXEC test.throw @message = N'Unit-test fail: <<No error>>', @error_number = 70001;
END;
GO

CREATE OR ALTER PROC [test].[assert_equals]
	@message nvarchar(max),
	@expected nvarchar(max),
	@actual nvarchar(max)
AS
BEGIN
	SET NOCOUNT ON;
	IF test.is_equal(@expected, @actual) <> 1
	BEGIN
		SET @message = CONCAT(N'Unit-test fail: ', @message, CHAR(13), CHAR(10),
			N'expected: ', COALESCE(N'<' + @expected + N'>', N'null'), CHAR(13), CHAR(10),
			N'but was : ', COALESCE(N'<' + @actual + N'>', N'null'));
		EXEC test.throw @message = @message, @error_number = 70001;
	END;
END;
GO

CREATE OR ALTER PROC [test].[assert_float_equals]
	@message nvarchar(max),
	@expected float,
	@actual float,
	@tolerance float
AS
BEGIN
	SET NOCOUNT ON;
	IF test.is_float_equal(@expected, @actual, @tolerance) <> 1
	BEGIN
		IF @tolerance IS NULL OR @tolerance < 0
			SET @message = CONCAT(N'Unit-test fail: ', @message, CHAR(13), CHAR(10),
				N'Absolute tolerance must be non-negative and not NULL.');
		ELSE
			SET @message = CONCAT(N'Unit-test fail: ', @message, CHAR(13), CHAR(10),
				N'expected: ', COALESCE(N'<' + CONVERT(nvarchar(32), @expected, 3) + N'>', N'null'),
				CHAR(13), CHAR(10),
				N'but was : ', COALESCE(N'<' + CONVERT(nvarchar(32), @actual, 3) + N'>', N'null'),
				CHAR(13), CHAR(10),
				N'absolute tolerance: <', CONVERT(nvarchar(32), @tolerance, 3), N'>');
		EXEC test.throw @message = @message, @error_number = 70001;
	END;
END;
GO

CREATE OR ALTER PROC [test].[assert_null]
	@message nvarchar(max),
	@value varbinary(max)
AS
BEGIN
	SET NOCOUNT ON;
	IF test.is_null(@value) <> 1
	BEGIN
		SET @message = CONCAT(N'Unit-test fail: ', @message);
		EXEC test.throw @message = @message, @error_number = 70001;
	END;
END;
GO

CREATE OR ALTER PROC [test].[assert_not_null]
	@message nvarchar(max),
	@value varbinary(max)
AS
BEGIN
	SET NOCOUNT ON;
	IF test.is_not_null(@value) <> 1
	BEGIN
		SET @message = CONCAT(N'Unit-test fail: ', @message);
		EXEC test.throw @message = @message, @error_number = 70001;
	END;
END;
GO

CREATE OR ALTER PROC [test].[assert_error]
	@message nvarchar(max),
	@expected_number int = NULL,
	@expected_message_pattern nvarchar(max) = NULL,
	@expected_state int = NULL
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @actual_number int = ERROR_NUMBER(), @actual_message nvarchar(max) = ERROR_MESSAGE(),
		@actual_state int = ERROR_STATE(), @failure nvarchar(max);

	IF @actual_number IS NULL OR @actual_message LIKE N'%<<No error>>%'
		SET @failure = CONCAT(@message, N'. Expected a caught error; none was caught.');
	ELSE IF (@expected_number IS NOT NULL AND @actual_number IS DISTINCT FROM @expected_number)
		OR (@expected_message_pattern IS NOT NULL
			AND (@actual_message IS NULL OR @actual_message NOT LIKE @expected_message_pattern))
		OR (@expected_state IS NOT NULL AND @actual_state IS DISTINCT FROM @expected_state)
		SET @failure = CONCAT(@message,
			N'. Expected error number: ', COALESCE(CONVERT(nvarchar(12), @expected_number), N'<any>'),
			N'; message pattern: ', COALESCE(N'<' + @expected_message_pattern + N'>', N'<any>'),
			N'; state: ', COALESCE(CONVERT(nvarchar(12), @expected_state), N'<any>'),
			N'. Got error number: ', @actual_number,
			N'; message: <', @actual_message, N'>; state: ', @actual_state, N'.');

	IF @failure IS NOT NULL
	BEGIN
		SET @failure = CONCAT(N'Unit-test fail: ', @failure);
		EXEC test.throw @message = @failure, @error_number = 70001;
	END;
END;
GO

CREATE OR ALTER PROC [test].[assert_resultset_equals]
	@message nvarchar(max),
	@expected_query nvarchar(max),
	@actual_query nvarchar(max)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @expected nvarchar(max), @actual nvarchar(max), @sql nvarchar(max),
		@whitespace nvarchar(4) = N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13);

	SET @expected_query = TRIM(@whitespace FROM @expected_query);
	SET @actual_query = TRIM(@whitespace FROM @actual_query);
	IF RIGHT(@expected_query, 1) = N';'
		SET @expected_query = TRIM(@whitespace FROM LEFT(@expected_query, LEN(@expected_query) - 1));
	IF RIGHT(@actual_query, 1) = N';'
		SET @actual_query = TRIM(@whitespace FROM LEFT(@actual_query, LEN(@actual_query) - 1));

	IF @expected_query IS NULL OR @expected_query = N''
	BEGIN
		SET @message = CONCAT(@message, N': expected query must not be NULL or empty.');
		EXEC test.assert_not_null @message, NULL;
		RETURN;
	END;
	IF @actual_query IS NULL OR @actual_query = N''
	BEGIN
		SET @message = CONCAT(@message, N': actual query must not be NULL or empty.');
		EXEC test.assert_not_null @message, NULL;
		RETURN;
	END;

	SET @sql = N'SET @json = (' + NCHAR(10) + @expected_query
		+ NCHAR(10) + N'FOR JSON PATH, INCLUDE_NULL_VALUES);';
	EXEC sys.sp_executesql @sql, N'@json nvarchar(max) OUTPUT', @json = @expected OUTPUT;

	SET @sql = N'SET @json = (' + NCHAR(10) + @actual_query
		+ NCHAR(10) + N'FOR JSON PATH, INCLUDE_NULL_VALUES);';
	EXEC sys.sp_executesql @sql, N'@json nvarchar(max) OUTPUT', @json = @actual OUTPUT;

	EXEC test.assert_equals @message, @expected, @actual;
END;
GO

CREATE OR ALTER PROC [test].[get_query_schema]
	@message nvarchar(max),
	@query nvarchar(max),
	@schema_signature nvarchar(max) OUTPUT
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @whitespace nvarchar(4) = N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13),
		@view_name sysname = N'_query_schema_' + REPLACE(CONVERT(nvarchar(36), NEWID()), N'-', N''),
		@view nvarchar(258), @sql nvarchar(max), @object_id int, @created bit = 0;

	SET @schema_signature = NULL;
	SET @query = TRIM(@whitespace FROM @query);
	IF LEFT(@query, 1) = N';'
		SET @query = TRIM(@whitespace FROM SUBSTRING(@query, 2, LEN(@query)));
	IF RIGHT(@query, 1) = N';'
		SET @query = TRIM(@whitespace FROM LEFT(@query, LEN(@query) - 1));
	IF @query IS NULL OR @query = N''
	BEGIN
		SET @message = CONCAT(@message, N': query must not be NULL or empty.');
		EXEC test.assert_not_null @message, NULL;
		RETURN;
	END;

	SET @view = N'[test].' + QUOTENAME(@view_name);
	IF OBJECT_ID(@view) IS NOT NULL
		THROW 51090, 'Schema probe name already exists; it was not overwritten.', 1;
	BEGIN TRY
		SET @sql = N'CREATE VIEW ' + @view + N' AS ' + NCHAR(10) + @query + NCHAR(10) + N';';
		EXEC sys.sp_executesql @sql;
		SET @created = 1;
		SET @object_id = OBJECT_ID(@view);

		SELECT @schema_signature = STRING_AGG(CONVERT(nvarchar(max), QUOTENAME(c.name) + N' ' + t.name
			+ CASE
				WHEN t.name IN (N'varchar', N'char', N'varbinary', N'binary')
					THEN N'(' + CASE WHEN c.max_length = -1 THEN N'max'
						ELSE CONVERT(nvarchar(10), c.max_length) END + N')'
				WHEN t.name IN (N'nvarchar', N'nchar')
					THEN N'(' + CASE WHEN c.max_length = -1 THEN N'max'
						ELSE CONVERT(nvarchar(10), c.max_length / 2) END + N')'
				WHEN t.name IN (N'decimal', N'numeric')
					THEN N'(' + CONVERT(nvarchar(10), c.precision) + N','
						+ CONVERT(nvarchar(10), c.scale) + N')'
				WHEN t.name IN (N'datetime2', N'datetimeoffset', N'time')
					THEN N'(' + CONVERT(nvarchar(10), c.scale) + N')'
				ELSE N'' END), N', ') WITHIN GROUP (ORDER BY c.column_id)
		FROM sys.columns c
		JOIN sys.types t ON t.user_type_id =
			CASE WHEN c.system_type_id = 240 THEN c.user_type_id ELSE c.system_type_id END
		WHERE c.object_id = @object_id;

		SET @sql = N'DROP VIEW ' + @view + N';';
		EXEC sys.sp_executesql @sql;
	END TRY
	BEGIN CATCH
		IF @created = 1
		BEGIN
			SET @sql = N'DROP VIEW IF EXISTS ' + @view + N';';
			EXEC sys.sp_executesql @sql;
		END;
		THROW;
	END CATCH;
END;
GO

CREATE OR ALTER PROC [test].[assert_schema_signature]
	@message nvarchar(max),
	@expected_schema_signature nvarchar(max),
	@actual_query nvarchar(max)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @actual_schema nvarchar(max), @matches bit, @context nvarchar(max),
		@whitespace nvarchar(4) = N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13);
	IF @expected_schema_signature IS NULL OR TRIM(@whitespace FROM @expected_schema_signature) = N''
	BEGIN
		SET @message = CONCAT(@message, N': expected schema must not be NULL or empty.');
		EXEC test.assert_not_null @message, NULL;
		RETURN;
	END;

	SET @context = CONCAT(@message, N': actual query');
	EXEC test.get_query_schema @context, @actual_query, @actual_schema OUTPUT;
	SET @matches = CASE WHEN @actual_schema IS NOT NULL
		AND CONVERT(varbinary(max), @expected_schema_signature) = CONVERT(varbinary(max), @actual_schema)
		THEN 1 ELSE 0 END;
	SET @message = CONCAT(@message, N': schema', CHAR(10),
		N'Expected: ', @expected_schema_signature, CHAR(10), N'Actual: ', COALESCE(@actual_schema, N'<missing>'));
	EXEC test.assert_equals @message, 1, @matches;
END;
GO

CREATE OR ALTER PROC [test].[assert_query_schemas_equal]
	@message nvarchar(max),
	@expected_query nvarchar(max),
	@actual_query nvarchar(max)
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_schema_signature nvarchar(max), @context nvarchar(max);
	SET @context = CONCAT(@message, N': expected query');
	EXEC test.get_query_schema @context, @expected_query, @expected_schema_signature OUTPUT;
	EXEC test.assert_schema_signature @message, @expected_schema_signature, @actual_query;
END;
GO

CREATE OR ALTER proc [test].[log]
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
GO

CREATE OR ALTER proc [test].[set_registration_scope]
  @scope nvarchar(max)
as

set nocount on

if @scope is null or not (
	(@scope collate Latin1_General_100_BIN2 = N'session' and datalength(@scope) = 14)
	or (@scope collate Latin1_General_100_BIN2 = N'global' and datalength(@scope) = 12))
	exec test.throw @message = N'Vector scope must be exactly session or global.';

if cast(serverproperty('EngineEdition') as int) = 11 begin
	if @scope = N'session'
		exec test.throw @message = N'Session scope for vectors and dimensions is not available on Fabric Warehouse. Use global scope.';
	return
end

declare @value nvarchar(7) = @scope
exec sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @value, @read_only = 0
GO

CREATE OR ALTER proc [test].[vector]
  @test_name nvarchar(max)
, @arguments_sql nvarchar(max)
as

set nocount on

declare @scope nvarchar(4000) = N'global'
if cast(serverproperty('EngineEdition') as int) <> 11
	exec sys.sp_executesql N'SELECT @scope = CONVERT(nvarchar(4000), SESSION_CONTEXT(N''ttest:vectors:scope''));',
		N'@scope nvarchar(4000) OUTPUT', @scope = @scope output
if @scope is null set @scope = N'global'
if not (
	(@scope collate Latin1_General_100_BIN2 = N'session' and datalength(@scope) = 14)
	or (@scope collate Latin1_General_100_BIN2 = N'global' and datalength(@scope) = 12))
	exec test.throw @message = N'Vector scope must be exactly session or global.';

declare @table_name nvarchar(128) = case when @scope = N'session'
		then N'#test_vectors' else N'[test].[test_vectors]' end
	, @table_id int = case when @scope = N'session'
		then object_id(N'tempdb..#test_vectors') else object_id(N'[test].[test_vectors]', N'U') end
	, @sql nvarchar(max)

if @table_id is null begin
	set @sql = concat(N'WARNING: test.vector skipped in ', @scope, N' scope: ',
		@table_name, N' was not found.')
	print @sql
	print case when @scope = N'session'
		then N'Run CREATE TABLE directly in the calling batch on this connection:'
		else N'Create the permanent table in this database:' end
	set @sql = concat(N'CREATE TABLE ', @table_name, N' (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);')
	print @sql
	return
end

declare @canonical_name nvarchar(max)
if parsename(@test_name, 2) is not null
	and parsename(@test_name, 3) is null and parsename(@test_name, 4) is null
	select @canonical_name = test_proc_full_name
	from test.test_procedures
	where object_id(test_proc_full_name) = object_id(@test_name)
		and test_proc_schema_name <> N'test'

if @canonical_name is null
	exec test.throw @message = N'Vector test must be a schema-qualified discovered test in this database.';
if @arguments_sql is null or trim(replace(replace(replace(@arguments_sql,
	nchar(9), N' '), nchar(10), N' '), nchar(13), N' ')) = N''
	exec test.throw @message = N'Vector parameters cannot be NULL or blank.';

if convert(varbinary(max), @canonical_name) <> convert(varbinary(max),
	convert(nvarchar(max), convert(varchar(max), @canonical_name collate Latin1_General_100_BIN2_UTF8)))
	or convert(varbinary(max), @arguments_sql) <> convert(varbinary(max),
		convert(nvarchar(max), convert(varchar(max), @arguments_sql collate Latin1_General_100_BIN2_UTF8)))
	exec test.throw @message = N'Vector test name and parameters must contain valid Unicode text.';

set @sql = N'INSERT ' + @table_name + N' (procedure_name, parameters) VALUES (@name, @arguments_sql);'
exec sys.sp_executesql @sql, N'@name nvarchar(max), @arguments_sql nvarchar(max)',
	@name = @canonical_name, @arguments_sql = @arguments_sql
GO

CREATE OR ALTER proc [test].[dimension]
  @test_name nvarchar(max)
, @parameter_name nvarchar(max)
, @values_json nvarchar(max)
as

set nocount on

declare @scope nvarchar(4000) = N'global'
if cast(serverproperty('EngineEdition') as int) <> 11
	exec sys.sp_executesql N'SELECT @scope = CONVERT(nvarchar(4000), SESSION_CONTEXT(N''ttest:vectors:scope''));',
		N'@scope nvarchar(4000) OUTPUT', @scope = @scope output
if @scope is null set @scope = N'global'
if not (
	(@scope collate Latin1_General_100_BIN2 = N'session' and datalength(@scope) = 14)
	or (@scope collate Latin1_General_100_BIN2 = N'global' and datalength(@scope) = 12))
	exec test.throw @message = N'Vector scope must be exactly session or global.';

declare @table_name nvarchar(128) = case when @scope = N'session'
		then N'#test_dimension_values' else N'[test].[test_dimension_values]' end
	, @table_id int = case when @scope = N'session'
		then object_id(N'tempdb..#test_dimension_values') else object_id(N'[test].[test_dimension_values]', N'U') end
	, @sql nvarchar(max)

if @table_id is null begin
	set @sql = concat(N'WARNING: test.dimension skipped in ', @scope, N' scope: ',
		@table_name, N' was not found.')
	print @sql
	print case when @scope = N'session'
		then N'Run CREATE TABLE directly in the calling batch on this connection:'
		else N'Create the permanent table in this database:' end
	set @sql = concat(N'CREATE TABLE ', @table_name, N' (
    procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
    value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
);')
	print @sql
	return
end

declare @canonical_name nvarchar(max), @canonical_parameter nvarchar(128), @inserted int
if parsename(@test_name, 2) is not null
	and parsename(@test_name, 3) is null and parsename(@test_name, 4) is null
	select @canonical_name = test_proc_full_name
	from test.test_procedures
	where object_id(test_proc_full_name) = object_id(@test_name)
		and test_proc_schema_name <> N'test'

if @canonical_name is null
	exec test.throw @message = N'Dimension test must be a schema-qualified discovered test in this database.';
if convert(varbinary(max), @canonical_name) <> convert(varbinary(max),
	convert(nvarchar(max), convert(varchar(max), @canonical_name collate Latin1_General_100_BIN2_UTF8)))
	exec test.throw @message = N'Dimension test name must contain valid Unicode text.';
select @canonical_parameter = name
from sys.parameters
where object_id = object_id(@canonical_name) and parameter_id > 0
	and name collate database_default = @parameter_name collate database_default
if @canonical_parameter is null
	exec test.throw @message = N'Dimension parameter must name a declared test parameter, including @.';
if @values_json is null or isjson(@values_json) <> 1
	or left(ltrim(replace(replace(replace(@values_json, nchar(9), N' '), nchar(10), N' '), nchar(13), N' ')), 1) <> N'['
	exec test.throw @message = N'Dimension values must be a nonempty JSON array.';

-- Invalid/lossy literals fail the same atomic NOT NULL insert; 16 MiB fits Warehouse storage.
set @sql = N'BEGIN TRY
IF EXISTS (SELECT 1 FROM ' + @table_name + N'
	WHERE CONVERT(nvarchar(max), procedure_name) COLLATE Latin1_General_100_BIN2 = @name COLLATE Latin1_General_100_BIN2
		AND CONVERT(nvarchar(max), parameter_name) COLLATE Latin1_General_100_BIN2 = @parameter COLLATE Latin1_General_100_BIN2)
	EXEC test.throw @message = N''Dimension is already registered; reset the selected store before changing it.'';
INSERT ' + @table_name + N' (procedure_name, parameter_name, value)
SELECT CONVERT(varchar(max), @name COLLATE Latin1_General_100_BIN2_UTF8),
	CONVERT(varchar(max), @parameter COLLATE Latin1_General_100_BIN2_UTF8),
	CASE WHEN CHARINDEX(NCHAR(0), literal COLLATE Latin1_General_100_BIN2) > 0
		OR CONVERT(varbinary(max), literal) <> CONVERT(varbinary(max), CONVERT(nvarchar(max), encoded))
		OR DATALENGTH(encoded) > 16777216 THEN NULL ELSE encoded END
FROM OPENJSON(@values_json)
CROSS APPLY (SELECT CASE [type]
		WHEN 0 THEN CAST(N''NULL'' AS nvarchar(max))
		WHEN 1 THEN N''N'' + NCHAR(39)
			-- SQL consumes backslash/newline pairs; insert a continuation to preserve the original pair.
			+ REPLACE(REPLACE(REPLACE(CONVERT(nvarchar(max), [value]) COLLATE Latin1_General_100_BIN2_UTF8,
				NCHAR(39), NCHAR(39) + NCHAR(39)),
				NCHAR(92) + NCHAR(10), NCHAR(92) + NCHAR(92) + NCHAR(10) + NCHAR(10)),
				NCHAR(92) + NCHAR(13), NCHAR(92) + NCHAR(92) + NCHAR(10) + NCHAR(13)) + NCHAR(39)
		WHEN 2 THEN [value]
	END AS literal) AS l
CROSS APPLY (SELECT CONVERT(varchar(max), literal COLLATE Latin1_General_100_BIN2_UTF8) AS encoded) AS e;
SET @inserted = @@ROWCOUNT;
END TRY
BEGIN CATCH
	THROW;
END CATCH;'
exec sys.sp_executesql @sql,
	N'@name nvarchar(max), @parameter nvarchar(128), @values_json nvarchar(max), @inserted int OUTPUT',
	@name = @canonical_name, @parameter = @canonical_parameter, @values_json = @values_json, @inserted = @inserted output
if @inserted = 0
	exec test.throw @message = N'Dimension values cannot be an empty array.';
GO

CREATE OR ALTER proc [test].[clear_registrations]
  @test_name nvarchar(max) = null
as

set nocount on

declare @scope nvarchar(4000) = N'global'
if cast(serverproperty('EngineEdition') as int) <> 11
	exec sys.sp_executesql N'SELECT @scope = CONVERT(nvarchar(4000), SESSION_CONTEXT(N''ttest:vectors:scope''));',
		N'@scope nvarchar(4000) OUTPUT', @scope = @scope output
if @scope is null set @scope = N'global'
if not (
	(@scope collate Latin1_General_100_BIN2 = N'session' and datalength(@scope) = 14)
	or (@scope collate Latin1_General_100_BIN2 = N'global' and datalength(@scope) = 12))
	exec test.throw @message = N'Vector scope must be exactly session or global.';

declare @canonical_name nvarchar(max)
if @test_name is not null begin
	if parsename(@test_name, 2) is not null
		and parsename(@test_name, 3) is null and parsename(@test_name, 4) is null
		select @canonical_name = test_proc_full_name
		from test.test_procedures
		where object_id(test_proc_full_name) = object_id(@test_name)
			and test_proc_schema_name <> N'test'
	if @canonical_name is null
		exec test.throw @message = N'Reset test must be a schema-qualified discovered test in this database.';
end

declare @table_name nvarchar(128) = case when @scope = N'session'
		then N'#test_vectors' else N'[test].[test_vectors]' end
	, @table_id int = case when @scope = N'session'
		then object_id(N'tempdb..#test_vectors') else object_id(N'[test].[test_vectors]', N'U') end
	, @sql nvarchar(max)

if @table_id is not null begin
	set @sql = N'DELETE FROM ' + @table_name
		+ case when @test_name is null then N';' else N'
		WHERE CONVERT(nvarchar(max), procedure_name) COLLATE Latin1_General_100_BIN2 = @name COLLATE Latin1_General_100_BIN2;' end
	exec sys.sp_executesql @sql, N'@name nvarchar(max)', @name = @canonical_name
end

set @table_name = case when @scope = N'session'
	then N'#test_dimension_values' else N'[test].[test_dimension_values]' end
set @table_id = case when @scope = N'session'
	then object_id(N'tempdb..#test_dimension_values') else object_id(N'[test].[test_dimension_values]', N'U') end
if @table_id is not null begin
	set @sql = N'DELETE FROM ' + @table_name
		+ case when @test_name is null then N';' else N'
		WHERE CONVERT(nvarchar(max), procedure_name) COLLATE Latin1_General_100_BIN2 = @name COLLATE Latin1_General_100_BIN2;' end
	exec sys.sp_executesql @sql, N'@name nvarchar(max)', @name = @canonical_name
end
GO

CREATE OR ALTER proc [test].[run]
  @test_names nvarchar(max) = null -- | separated exact names or LIKE patterns
, @exclude_test_names nvarchar(max) = null -- | separated exact names or LIKE patterns
, @test_schemas nvarchar(max) = null -- test-procedure schemas; defaults to tests
, @exclude_test_schemas nvarchar(max) = null
, @max_failures int = null
, @before_each_sql nvarchar(max) = null
, @log_proc_name nvarchar(256) = null
, @test_object_schemas nvarchar(max) = null
, @exclude_test_object_schemas nvarchar(max) = null
as

set nocount on

declare @proc_id int = object_id(N'[test].[run]')
	, @engine_edition int = cast(serverproperty('EngineEdition') as int)
	, @error_line int

declare @full_proc_name nvarchar(max)
, @log_message nvarchar(max)

set @max_failures = isnull(@max_failures, 1000000)

if @log_proc_name is null set @log_proc_name = 'test.log'

if @@trancount > 0
	exec test.throw @message = 'Tests cannot be run in transaction'
	              , @proc_id = @proc_id;

if @engine_edition <> 11
	exec sys.sp_executesql N'IF (@@OPTIONS & 2) = 2
		EXEC test.throw @message = N''Tests cannot be run with implicit transactions enabled'', @proc_id = @id;',
		N'@id int', @id = @proc_id

declare @scope nvarchar(4000) = N'global'
if @engine_edition <> 11
	exec sys.sp_executesql N'SELECT @scope = CONVERT(nvarchar(4000), SESSION_CONTEXT(N''ttest:vectors:scope''));',
		N'@scope nvarchar(4000) OUTPUT', @scope = @scope output
if @scope is null set @scope = N'global'
if not (
	(@scope collate Latin1_General_100_BIN2 = N'session' and datalength(@scope) = 14)
	or (@scope collate Latin1_General_100_BIN2 = N'global' and datalength(@scope) = 12))
	exec test.throw @message = N'Vector scope must be exactly session or global.';

-- NULL names and duplicate results raise 50000 instead of table constraint errors.
declare @results nvarchar(max) = N'[]'
	, @test_list nvarchar(max)
	, @available_count int

declare @is_fail int
, @fail_message nvarchar(max)
, @fail_message_start int
, @fail_message_tag nvarchar(max) = 'Unit-test fail:'
, @fail_message_prefix nvarchar(max) = N'Conversion failed when converting the nvarchar value '''
, @fail_message_tail nvarchar(max) = ''' to data type int.'
, @start_time datetime
, @duration_millis int

if @test_schemas is not null and not exists (
	select 1 from test.test_procedures t
	join string_split(@test_schemas, ',') s on trim(s.value) = t.test_proc_schema_name)
	exec test.throw @message = N'No test procedures found in the requested schemas.';

;with tokens as (
	select N'include' as kind, trim(value) as token, ordinal
	from string_split(@test_names, '|', 1)
	union all
	select N'exclude', trim(value), ordinal
	from string_split(@exclude_test_names, '|', 1)
	union all
	select N'include', N'', cast(1 as bigint) where @test_names = N''
		and not exists (select 1 from string_split(@test_names, '|', 1))
), resolved as (
	select kind, token, ordinal,
		case when parsename(token, 3) is null and parsename(token, 4) is null
			then object_id(token, N'P') end as proc_id
	from tokens
), matches as (
	select t.test_proc_id, n.kind, n.token, n.ordinal
	from test.test_procedures t
	cross join resolved n
	cross apply (select quotename(t.test_proc_schema_name) + N'.' as prefix) q
	cross apply (select substring(n.token, len(q.prefix) + 1, len(n.token)) as suffix) s
	cross apply (select case
		when left(n.token, len(q.prefix)) = q.prefix then
			replace(replace(replace(t.test_proc_schema_name, N'[', N'[[]'), N'%', N'[%]'), N'_', N'[_]')
			+ N'.' + s.suffix
		when left(n.token, 1) = N'[' and charindex(N'].', n.token) > 0 then null
		else n.token end as pattern) p
	where (n.proc_id is not null and n.proc_id = t.test_proc_id)
		or (n.proc_id is null
			and t.test_proc_schema_name + N'.' + t.test_proc_name like p.pattern)
), selected as (
	select t.test_proc_id, t.test_proc_full_name, t.test_proc_name,
		t.test_proc_schema_name, t.tested_object_main_schema_name, m.ordinal
	from test.test_procedures t
	left join matches m on m.test_proc_id = t.test_proc_id and m.kind = N'include'
	where @test_names is null or m.token is not null
	union all
	select null, null, null, null, null, n.ordinal
	from resolved n
	where n.kind = N'include' and not exists (
		select 1 from matches m where m.kind = n.kind and m.ordinal = n.ordinal)
)
select @test_list = concat(N'[', string_agg(
	cast(json_object('test_proc_full_name': t.test_proc_full_name,
		'display_name': t.test_proc_name, 'test_schema': t.test_proc_schema_name,
		'main_schema': t.tested_object_main_schema_name) as nvarchar(max)), N',')
	within group (order by isnull(t.ordinal, 0), t.test_proc_full_name), N']')
from selected t
where (t.test_proc_id is null or (
	(@test_schemas is null and (@test_names is not null or t.test_proc_schema_name = N'tests')
		or exists (select 1 from string_split(@test_schemas, ',') s
			where trim(s.value) = t.test_proc_schema_name))
	and not exists (select 1 from string_split(@exclude_test_schemas, ',') s
		where trim(s.value) = t.test_proc_schema_name)
	and (@test_object_schemas is null or exists (
		select 1 from string_split(@test_object_schemas, ',') s
		where trim(s.value) = t.tested_object_main_schema_name))
	and not exists (select 1 from string_split(@exclude_test_object_schemas, ',') s
		where trim(s.value) = t.tested_object_main_schema_name)))
	and not exists (select 1 from matches m
		where m.kind = N'exclude' and m.test_proc_id = t.test_proc_id);

select @available_count = count(*)
from test.test_procedures t
where (@test_schemas is not null and exists (
	select 1 from string_split(@test_schemas, ',') s where trim(s.value) = t.test_proc_schema_name))
	or (@test_schemas is null and (
		t.test_proc_schema_name in (
			select test_schema from openjson(@test_list) with (test_schema nvarchar(128)))
		or (t.test_proc_schema_name = N'tests' and not exists (
			select 1 from openjson(@test_list) with (test_schema nvarchar(128))
			where test_schema is not null))));
declare @test_no bigint = 0
	, @test_count bigint = (select count_big(*) from openjson(@test_list))
	, @snapshot nvarchar(max) = N'[]'
	, @rows nvarchar(max)
	, @snapshot_sql nvarchar(max)
	, @dimension_sql nvarchar(max)
	, @dimension_rows nvarchar(max)
	, @domains nvarchar(max)
	, @domain_no int
	, @domain_count int
	, @parameter_name nvarchar(128)
	, @value_count bigint
	, @product bigint
	, @procedure_count bigint
	, @arguments nvarchar(max)
	, @joins nvarchar(max)
	, @alias nvarchar(32)
	, @phase int = 1
	, @source nvarchar(9)
	, @vector_table nvarchar(128) = case when @scope = N'session'
		then N'#test_vectors' else N'[test].[test_vectors]' end
	, @vector_table_id int = case when @scope = N'session'
		then object_id(N'tempdb..#test_vectors') else object_id(N'[test].[test_vectors]', N'U') end
	, @dimension_table nvarchar(128) = case when @scope = N'session'
		then N'#test_dimension_values' else N'[test].[test_dimension_values]' end
	, @dimension_table_id int = case when @scope = N'session'
		then object_id(N'tempdb..#test_dimension_values') else object_id(N'[test].[test_dimension_values]', N'U') end
	, @has_cases bit = 0
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
	, @is_registered bit
	, @stop bit = 0

create table #test_run_dimension_values (
	procedure_name varchar(2048) collate Latin1_General_100_BIN2_UTF8 not null,
	parameter_name varchar(512) collate Latin1_General_100_BIN2_UTF8 not null,
	value varchar(max) collate Latin1_General_100_BIN2_UTF8 not null
)
create table #test_run_cases (
	work_no bigint not null,
	parameters varchar(max) collate Latin1_General_100_BIN2_UTF8 not null
)

-- Read each store separately; Warehouse storage queries must not join private temp tables.
if @vector_table_id is not null
	set @snapshot_sql = N'SELECT @rows = CONCAT(N''['', STRING_AGG(
		CAST(JSON_OBJECT(''parameters'': CONVERT(nvarchar(max), parameters)) AS nvarchar(max)),
		N'',''), N'']'') FROM ' + @vector_table + N'
		WHERE CONVERT(nvarchar(max), procedure_name) COLLATE Latin1_General_100_BIN2
			= @name COLLATE Latin1_General_100_BIN2;'
if @dimension_table_id is not null
	set @dimension_sql = N'SELECT @rows = CONCAT(N''['', STRING_AGG(
		CAST(JSON_OBJECT(''parameter_name'': CONVERT(nvarchar(max), parameter_name),
			''value'': CONVERT(nvarchar(max), value)) AS nvarchar(max)),
		N'',''), N'']'') FROM ' + @dimension_table + N'
		WHERE CONVERT(nvarchar(max), procedure_name) COLLATE Latin1_General_100_BIN2
			= @name COLLATE Latin1_General_100_BIN2;'

while @test_no < @test_count begin
	select @full_proc_name = test_proc_full_name
	from openjson(@test_list, concat('$[', @test_no, ']'))
		with (test_proc_full_name nvarchar(max))
	set @procedure_count = null
	select @procedure_count = case_count
	from openjson(@snapshot)
		with (procedure_name nvarchar(max), case_count bigint)
	where procedure_name collate Latin1_General_100_BIN2
		= @full_proc_name collate Latin1_General_100_BIN2

	if @procedure_count is null begin
		set @rows = N'[]'
		set @dimension_rows = N'[]'
		begin try
			if @snapshot_sql is not null and @full_proc_name is not null
				exec sys.sp_executesql @snapshot_sql,
					N'@name nvarchar(max), @rows nvarchar(max) OUTPUT',
					@name = @full_proc_name, @rows = @rows output
			if @dimension_sql is not null and @full_proc_name is not null
				exec sys.sp_executesql @dimension_sql,
					N'@name nvarchar(max), @rows nvarchar(max) OUTPUT',
					@name = @full_proc_name, @rows = @dimension_rows output
		end try
		begin catch
			throw;
		end catch

		insert #test_run_dimension_values (procedure_name, parameter_name, value)
		select convert(varchar(max), @full_proc_name collate Latin1_General_100_BIN2_UTF8),
			convert(varchar(max), parameter_name collate Latin1_General_100_BIN2_UTF8),
			convert(varchar(max), value collate Latin1_General_100_BIN2_UTF8)
		from openjson(@dimension_rows)
			with (parameter_name nvarchar(128), value nvarchar(max))

		select @domains = concat(N'[', string_agg(cast(json_object(
			'parameter_name': parameter_name, 'value_count': value_count) as nvarchar(max)), N',')
			within group (order by parameter_name collate Latin1_General_100_BIN2), N']')
		from (
			select parameter_name collate Latin1_General_100_BIN2 as parameter_name, count_big(*) as value_count
			from openjson(@dimension_rows) with (parameter_name nvarchar(128))
			group by parameter_name collate Latin1_General_100_BIN2
		) as d
		set @domain_count = (select count(*) from openjson(@domains))
		set @product = iif(@domain_count = 0, 0, 1)
		set @domain_no = 0
		while @domain_no < @domain_count begin
			select @value_count = value_count
			from openjson(@domains, concat('$[', @domain_no, ']')) with (value_count bigint)
			if @product > 9223372036854775807 / @value_count
				exec test.throw @message = N'Dimension case count exceeds BIGINT.';
			set @product *= @value_count
			set @domain_no += 1
		end
		set @procedure_count = (select count_big(*) from openjson(@rows))
		if @procedure_count > 0 or @product > 0 set @has_cases = 1
		if @procedure_count > 9223372036854775807 - @product
			exec test.throw @message = N'Planned case count exceeds BIGINT.';
		set @procedure_count += @product
		if @procedure_count = 0 set @procedure_count = 1
		if @full_proc_name is not null begin
			set @selected_count += 1
			set @snapshot = json_modify(@snapshot, 'append $', json_query(json_object(
				'procedure_name': @full_proc_name, 'cases': json_query(@rows),
				'domains': json_query(@domains), 'case_count': @procedure_count)))
		end
	end

	if @planned_count > 9223372036854775807 - @procedure_count
		exec test.throw @message = N'Planned case count exceeds BIGINT.';
	set @planned_count += @procedure_count
	set @test_no += 1
end
while @phase <= 2 and @stop = 0 begin
set @test_no = 0

while @test_no < @test_count begin
	select @full_proc_name = test_proc_full_name, @display_name = display_name, @main_schema = main_schema
	from openjson(@test_list, concat('$[', @test_no, ']'))
		with (test_proc_full_name nvarchar(max), display_name nvarchar(max), main_schema nvarchar(max))

	set @test_no += 1
	set @rows = N'[]'
	set @domains = N'[]'
	select @rows = cases, @domains = domains
	from openjson(@snapshot)
		with (procedure_name nvarchar(max), cases nvarchar(max) as json, domains nvarchar(max) as json)
	where procedure_name collate Latin1_General_100_BIN2
		= @full_proc_name collate Latin1_General_100_BIN2
	delete from #test_run_cases
	set @is_registered = 1
	set @source = iif(@phase = 1, N'explicit', N'dimension')
	if @phase = 1 begin
		insert #test_run_cases (work_no, parameters)
		select convert(bigint, [key]) + 1,
			convert(varchar(max), parameters collate Latin1_General_100_BIN2_UTF8)
		from openjson(@rows)
			cross apply openjson(value) with (parameters nvarchar(max)) as v
		if not exists (select 1 from #test_run_cases) and @domains = N'[]' begin
			insert #test_run_cases values (1, '')
			set @is_registered = 0
			set @source = N'static'
		end
	end
	else begin
		set @domain_no = 0
		set @domain_count = (select count(*) from openjson(@domains))
		set @arguments = N'CAST(N'''' AS nvarchar(max))'
		set @joins = N''
		while @domain_no < @domain_count begin
			select @parameter_name = parameter_name
			from openjson(@domains, concat('$[', @domain_no, ']'))
				with (parameter_name nvarchar(128))
			set @alias = concat(N'd', @domain_no + 1)
			set @arguments += N' + N''' + iif(@domain_no = 0, N'', N', ')
				+ replace(@parameter_name, N'''', N'''''') + N' = '' + CONVERT(nvarchar(max), ' + @alias + N'.value)'
			set @joins += iif(@domain_no = 0, N'', N' CROSS JOIN ')
				+ N'(SELECT value FROM #test_run_dimension_values
					WHERE procedure_name = @name COLLATE Latin1_General_100_BIN2_UTF8
						AND parameter_name = N''' + replace(@parameter_name, N'''', N'''''')
				+ N''' COLLATE Latin1_General_100_BIN2_UTF8) AS ' + @alias
			set @domain_no += 1
		end
		if @domain_count > 0 begin
			set @snapshot_sql = N'BEGIN TRY
				INSERT #test_run_cases (work_no, parameters)
				SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
					CASE WHEN DATALENGTH(encoded) > 16777216 THEN NULL ELSE encoded END
				FROM ' + @joins + N'
				CROSS APPLY (SELECT CONVERT(varchar(max), (' + @arguments
				+ N') COLLATE Latin1_General_100_BIN2_UTF8) AS encoded) AS args;
			END TRY
			BEGIN CATCH
				THROW;
			END CATCH;'
			exec sys.sp_executesql @snapshot_sql, N'@name nvarchar(max)', @name = @full_proc_name
		end
	end
	set @case_count = (select count_big(*) from #test_run_cases)
	set @case_no = 0

	while @case_no < @case_count begin
		set @case_no += 1
		select @parameters = convert(nvarchar(max), parameters)
		from #test_run_cases where work_no = @case_no
		set @call = N'EXEC ' + @full_proc_name
			+ case when @is_registered = 1 then N' ' + @parameters else N'' end + N';'
		set @case_label = case when @is_registered = 1
			then concat(@display_name, N' (', @parameters, N')') else @display_name end
		if @invocation_no = 9223372036854775807
			exec test.throw @message = N'Case invocation count exceeds BIGINT.';
		set @invocation_no += 1

	if @before_each_sql is not null begin
		begin try
			exec sys.sp_executesql @stmt = @before_each_sql
			exec @log_proc_name @message = 'Call callbeck before test running', @data = @before_each_sql, @rowcount = @@rowcount, @proc_id = @proc_id
		end try
		begin catch
			if @@trancount > 0 rollback;
			throw;
		end catch
	end

	print '################################################################################################
Running ' + @full_proc_name

	if @is_registered = 1 begin
		set @log_message = concat(N'Start exec source=', @source, N' invocation=', @invocation_no)
		begin try
			exec @log_proc_name @message = @log_message, @data = @call, @proc_id = @proc_id
		end try
		begin catch
			if @@trancount > 0 rollback;
			throw;
		end catch
	end

	begin try

		set @start_time = getutcdate()

		if @is_registered = 1
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
			, 'source': @source
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

		if error_number() = 70001
			and left(@fail_message, len(@fail_message_tag)) = @fail_message_tag
			select @is_fail = 1
				, @fail_message = substring(@fail_message, len(@fail_message_tag) + 1, len(@fail_message))
		else if error_number() = 245
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
			if @has_cases = 1
				throw 50000, 'Test name cannot be NULL', 2;
			raiserror('Test name cannot be NULL', 16, 2);
		end
		else if exists(select 1 from openjson(@results)
			with (test_name nvarchar(max), selection_entry_index bigint)
			where test_name collate Latin1_General_100_BIN2 = @full_proc_name collate Latin1_General_100_BIN2
				and selection_entry_index <> @test_no)
		begin
			if @has_cases = 1
				throw 50000, 'Duplicate test result', 1;
			raiserror('Duplicate test result', 14, 1);
		end
		else
			set @results = json_modify(@results, 'append $', json_query(json_object(
				  'test_name': @full_proc_name
				, 'selection_entry_index': @test_no
				, 'invocation_no': @invocation_no
				, 'source': @source
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
		if @is_registered = 0 begin
			begin try
				exec @log_proc_name @message = @log_message, @p1_str = @full_proc_name, @p2_str = @fail_message, @proc_id = @test_proc_id, @severity = 'error'
			end try
			begin catch
				if @@trancount > 0 rollback;
				throw;
			end catch
		end

		if @max_failures > 0 begin
			set @max_failures -= 1
			if @max_failures = 0
				set @stop = 1
		end
	end catch

	if @is_registered = 1 begin
		declare @outcome nvarchar(8)
		select @outcome = case when is_success = 1 then N'PASS'
			when is_failed = 1 then N'FAILED' else N'ERROR' end
		from openjson(@results, concat('$[', @invocation_no - 1, ']'))
			with (is_success int, is_failed int)
		set @log_message = concat(N'Completed exec source=', @source, N' invocation=', @invocation_no, N' ', @outcome)
		declare @completion_data nvarchar(max) = @call
		declare @completion_severity nvarchar(8) = iif(@outcome = N'PASS', N'debug', N'error')
		if @outcome <> N'PASS' set @completion_data += NCHAR(10) + N'Message: ' + @fail_message
		begin try
			exec @log_proc_name @message = @log_message, @data = @completion_data,
				@proc_id = @proc_id, @severity = @completion_severity
		end try
		begin catch
			if @@trancount > 0 rollback;
			throw;
		end catch
	end
	if @stop = 1 break;
	end
	if @stop = 1 break;
end
set @phase += 1
end
drop table #test_run_cases
drop table #test_run_dimension_values

if @has_cases = 1 begin
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
	begin try
		exec @log_proc_name @message = @log_message, @severity = 'Info', @proc_id = @proc_id
	end try
	begin catch
		if @@trancount > 0 rollback;
		throw;
	end catch
	if @vector_failed + @vector_errors > 0
		exec test.throw @message = N'Parameterized test run failed; see result rows and completed-call logs.',
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

begin try
	exec @log_proc_name @message = @log_message
		, @severity = 'Info'
		, @proc_id = @proc_id
end try
begin catch
	if @@trancount > 0 rollback;
	throw;
end catch

if @error_message is not null
	exec test.throw @message = @error_message
	              , @proc_id = @proc_id
GO
GO
GO
GO

GO

GO

GO

GO

GO

GO

GO

GO

GO

GO

GO

CREATE OR ALTER PROC [tests].[test.format_message]
AS
PRINT N'Check placeholders and explicit date/hex formatting.';
PRINT N'Expect: exact substitutions; ordinary text is unchanged.';
SET NOCOUNT ON;

DECLARE @actual nvarchar(max);

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(NULL, 1, 2, 3, 4);

-- Assert
IF @actual IS NOT NULL
	THROW 51091, 'NULL format message changed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N'Hello %1', N'world', NULL, NULL, NULL);

-- Assert
IF CONVERT(varbinary(max), @actual)
	IS DISTINCT FROM CONVERT(varbinary(max), N'Hello world')
	THROW 51091, 'Text substitution failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N'Hello at %2', NULL,
	CONVERT(nvarchar(33), CAST('2026-03-04T05:06:07.123456' AS datetime2(6)), 126), NULL, NULL);

-- Assert
IF CONVERT(varbinary(max), @actual)
	IS DISTINCT FROM CONVERT(varbinary(max), N'Hello at 2026-03-04T05:06:07.123456')
	THROW 51091, 'Explicit ISO date substitution failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N'Hello binary: %1',
	CONVERT(nvarchar(4000), 0x010203, 1), NULL, NULL, NULL);

-- Assert
IF CONVERT(varbinary(max), @actual)
	IS DISTINCT FROM CONVERT(varbinary(max), N'Hello binary: 0x010203')
	THROW 51091, 'Explicit hexadecimal substitution failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N'%1|%2', N'10/31/26', N'0xabcdef', DEFAULT, DEFAULT);

-- Assert
IF CONVERT(varbinary(max), @actual)
	IS DISTINCT FROM CONVERT(varbinary(max), N'10/31/26|0xabcdef')
	THROW 51091, 'Date-like or hexadecimal text changed.', 1;

EXEC test.log @message = N'Basic logger smoke: %1', @p1 = N'ok', @severity = 'debug';
GO

-- Refresh the existing coverage test for the explicit date/hex formatting contract.
IF OBJECT_ID(N'[tests].[test.format_message@fc_parameters]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.format_message@fc_parameters]
AS
PRINT N''Check placeholders, Unicode and explicit ISO/hex text.'';
PRINT N''Expect: exact text, NULLs and repeated placeholders.'';

DECLARE @actual nvarchar(max), @date datetime2(6), @date_text nvarchar(33), @hex nvarchar(4000),
	@raw_date sql_variant, @raw_binary sql_variant, @plain nvarchar(max);

-- Arrange
SET @date = CAST(''2026-03-04T05:06:07.123456'' AS datetime2(6));
SET @hex = CONVERT(nvarchar(4000), 0xAB, 1);
SET @date_text = CONVERT(nvarchar(33), @date, 126);

-- Each parameter arrangement has its own exact reference.
-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', @date_text, CONVERT(nvarchar(4000), 0x010203, 1), 42, NULL);

-- Assert
IF @actual IS DISTINCT FROM N''2026-03-04T05:06:07.123456|0x010203|42|<null>''
	THROW 51091, ''Explicit ISO/hex/numeric/NULL substitution failed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', NULL, 42, @hex, @date_text);

-- Assert
IF @actual IS DISTINCT FROM N''<null>|42|0xAB|2026-03-04T05:06:07.123456''
	THROW 51091, ''Formatting in alternate parameter positions failed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', 42, @date_text, NULL, @hex);

-- Assert
IF @actual IS DISTINCT FROM N''42|2026-03-04T05:06:07.123456|<null>|0xAB''
	THROW 51091, ''Second date/fourth binary parameter formatting failed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', @hex, NULL, @date_text, 42);

-- Assert
IF @actual IS DISTINCT FROM N''0xAB|<null>|2026-03-04T05:06:07.123456|42''
	THROW 51091, ''Third date/first binary parameter formatting failed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2|%3|%4'', DEFAULT, DEFAULT, DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM N''%1|%2|%3|%4'' THROW 51091, ''Unassigned placeholders changed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2'', N''10/31/26'', N''0xabcdef'', DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM N''10/31/26|0xabcdef'' THROW 51091, ''Text was reclassified as date/binary.'', 1;

-- Arrange
SET @date = CAST(''2026-03-04T00:00:00'' AS datetime2(6));

-- Act
SET @actual = test.format_message(N''%1'', CONVERT(nvarchar(33), @date, 126), DEFAULT, DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM N''2026-03-04T00:00:00'' THROW 51091, ''ISO midnight text changed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1|%2'', CONVERT(nvarchar(4000), 0x, 1),
	CONVERT(nvarchar(33), CAST(NULL AS datetime2(6)), 126), DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM N''0x|<null>'' THROW 51091, ''Empty hex or NULL ISO substitution failed.'', 1;

-- Arrange
SET @raw_date = @date;
SET @raw_binary = 0x41004200;
SET @plain = CONCAT(CAST(@raw_date AS nvarchar(4000)), N''|'', CAST(@raw_binary AS nvarchar(4000)));

-- Act
SET @actual = test.format_message(N''%1|%2'', @raw_date, @raw_binary, DEFAULT, DEFAULT);

-- Assert
IF CONVERT(varbinary(max), @actual) IS DISTINCT FROM CONVERT(varbinary(max), @plain)
	THROW 51091, ''Formatter still applies implicit date/binary formatting.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(NULL, 1, 2, 3, 4);

-- Assert
IF @actual IS NOT NULL THROW 51091, ''NULL message changed.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.format_message(N''%1:%1:100%'', NCHAR(381), DEFAULT, DEFAULT, DEFAULT);

-- Assert
IF @actual IS DISTINCT FROM NCHAR(381) + N'':'' + NCHAR(381) + N'':100%''
	THROW 51091, ''Unicode/repeated placeholder/percent formatting failed.'', 1;');
GO

-- Refresh only installed framework-owned equality coverage.
IF OBJECT_ID(N'[tests].[test.is_equal@fc_values]', N'P') IS NOT NULL
    EXEC(N'CREATE OR ALTER   PROC [tests].[test.is_equal@fc_values]
AS
PRINT N''Compare strings, NULLs, numbers and ordered JSON.'';
PRINT N''Expect: row order/types matter; column order does not.'';

DECLARE @cases nvarchar(max), @i int, @n int,
	@l nvarchar(max), @r nvarchar(max), @expected bit, @actual bit, @name nvarchar(100),
	@message nvarchar(2048);

-- Arrange
SET @i = 0;
SET @cases = N''[
 {"name":"nulls","l":null,"r":null,"eq":1},
 {"name":"null/string","l":null,"r":"","eq":0},
 {"name":"equal strings","l":"hello","r":"hello","eq":1},
 {"name":"different strings","l":"hello","r":"world","eq":0},
 {"name":"numeric spelling","l":"001.50","r":"1.5","eq":1},
 {"name":"scalar tiny decimal","l":"0.000000000000000000001","r":"0","eq":0},
 {"name":"scalar negative tiny decimal","l":"-0.000000000000000000001","r":"0","eq":0},
 {"name":"scalar precise decimal","l":"1.000000000000000000001","r":"1.000000000000000000002","eq":0},
 {"name":"scalar decimal rounding boundary","l":"0.000000000000000000005","r":"0.00000000000000000001","eq":0},
 {"name":"scalar decimal truncated tail","l":"0.1234567890123456789012","r":"0.12345678901234567890","eq":0},
 {"name":"scalar lossy alternative spelling","l":"0.0000000000000000000012","r":"0.00000000000000000000120","eq":0},
 {"name":"lossless decimal boundary","l":"09999999999.99999999999999999999","r":"9999999999.99999999999999999999","eq":1},
 {"name":"scalar negative zero","l":"-0","r":"0","eq":1},
 {"name":"scalar leading plus","l":"+1","r":"1","eq":1},
 {"name":"scalar surrounding spaces","l":" 1 ","r":"1","eq":1},
 {"name":"scalar omitted integer zero","l":".5","r":"0.5","eq":1},
 {"name":"scalar scientific notation unsupported","l":"1e2","r":"100","eq":0},
 {"name":"scalar integer range boundary","l":"10000000000","r":"10000000000.0","eq":0},
 {"name":"raw exponent spelling","l":"[1,1.0,1e0]","r":"[1.000,1e+0,1]","eq":0},
 {"name":"raw negative exponent","l":"[-1.25e-4]","r":"[-0.000125]","eq":0},
 {"name":"raw large exponent","l":"[1e1000]","r":"[10e999]","eq":0},
 {"name":"raw exponent above BIGINT","l":"[1e9223372036854775808]","r":"[10e9223372036854775807]","eq":0},
 {"name":"raw exponent below BIGINT","l":"[1e-9223372036854775809]","r":"[0.1e-9223372036854775808]","eq":0},
 {"name":"raw zero spelling","l":"[-0e99999999999999999999999999999]","r":"[0]","eq":0},
 {"name":"raw numeric sequence","l":"[10e99,0.1e-99,-0,12.3400]","r":" [10e99,0.1e-99,-0,12.3400]","eq":1},
 {"name":"tiny nonzero number","l":"[1e-1000]","r":"[0]","eq":0},
 {"name":"exact high precision","l":"[0.123456789012345678901]","r":"[0.123456789012345678902]","eq":0},
 {"name":"negative zero spelling","l":"[-0,0e1000]","r":"[0,0.0]","eq":0},
 {"name":"different numbers","l":"1","r":"2","eq":0},
 {"name":"object order","l":"{\"a\":1,\"b\":2}","r":"{\"b\":2,\"a\":1}","eq":1},
 {"name":"array order","l":"[1,2,3]","r":"[3,1,2]","eq":0},
 {"name":"multiplicity","l":"[1,1,2]","r":"[1,2,2]","eq":0},
 {"name":"empty containers","l":"{}","r":"[]","eq":0},
 {"name":"null property","l":"{\"a\":null}","r":"{}","eq":0},
 {"name":"number/string types","l":"[1]","r":"[\"1\"]","eq":0},
 {"name":"boolean/number types","l":"[true]","r":"[1]","eq":0},
 {"name":"column order","l":"[{\"id\":1,\"value\":\"a\"},{\"id\":2,\"value\":\"b\"}]","r":"[{\"value\":\"a\",\"id\":1},{\"value\":\"b\",\"id\":2}]","eq":1},
 {"name":"row order","l":"[{\"id\":1,\"value\":\"a\"},{\"id\":2,\"value\":\"b\"}]","r":"[{\"value\":\"b\",\"id\":2},{\"value\":\"a\",\"id\":1}]","eq":0},
 {"name":"row association","l":"[{\"id\":1,\"value\":\"a\"},{\"id\":2,\"value\":\"b\"}]","r":"[{\"id\":1,\"value\":\"b\"},{\"id\":2,\"value\":\"a\"}]","eq":0},
 {"name":"duplicate rows","l":"[{\"id\":1},{\"id\":1}]","r":"[{\"id\":1}]","eq":0},
 {"name":"empty row","l":"[{}]","r":"[]","eq":0},
 {"name":"NULL column versus absent column","l":"[{\"id\":null}]","r":"[{}]","eq":0},
 {"name":"raw date spelling","l":"[\"2026-03-04\"]","r":"[\"2026-03-04T00:00:00\"]","eq":0},
 {"name":"unicode/control","l":"[\"\\u017d\\n\\t\"]","r":"[\"\\u017d\\n\\t\"]","eq":1},
 {"name":"invalid JSON strings","l":"{bad","r":"{different","eq":0}
]'';
SET @n = (SELECT COUNT(*) FROM OPENJSON(@cases));

-- Shortcuts must not evaluate JSON parsing.
-- Act
SET @actual = test.is_equal(NULL, N'''');

-- Assert
IF @actual IS DISTINCT FROM 0 THROW 51091, ''Literal NULL/string comparison evaluated JSON parsing.'', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N''{bad JSON'', N''{bad JSON'');

-- Assert
IF @actual IS DISTINCT FROM 1 THROW 51091, ''Equal literal strings evaluated JSON parsing.'', 1;

WHILE @i < @n
BEGIN
	-- Arrange
	SELECT @l = l, @r = r, @expected = eq, @name = name
	FROM OPENJSON(@cases, CONCAT(''$['', @i, '']''))
	WITH (name nvarchar(100), l nvarchar(max), r nvarchar(max), eq bit);

	-- Act
	SET @actual = test.is_equal(@l, @r);

	-- Assert
	IF @actual IS DISTINCT FROM @expected
	BEGIN
		SET @message = N''is_equal scenario failed: '' + @name;
		THROW 51091, @message, 1;
	END;
	SET @i += 1;
END;');
GO

IF OBJECT_ID(N'[tests].[test.normalize_json@fc_normalization]', N'P') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.normalize_json@fc_numbers]', N'P') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.normalize_number@fc_numbers]', N'P') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.is_equal_openjson@fc_json]', N'P') IS NOT NULL
    OR OBJECT_ID(N'[tests].[test.is_json_equal@fc_json]', N'P') IS NOT NULL
BEGIN
    EXEC(N'CREATE OR ALTER   PROC [tests].[test.is_json_equal@fc_json]
AS
PRINT N''Compare long JSON values, Unicode and escape forms.'';
PRINT N''Expect: no truncation; equivalent decoded text matches.'';

DECLARE @text nvarchar(max), @left nvarchar(max), @right nvarchar(max), @equal bit,
	@unicode nvarchar(max);

-- Arrange
SET @text = REPLICATE(CAST(N''x'' AS nvarchar(max)), 6000);
SET @left = JSON_OBJECT(''text'': @text, ''id'': 1);
SET @right = JSON_OBJECT(''id'': 1, ''text'': @text);

-- Act
SET @equal = test.is_json_equal(@left, @right);

-- Assert
IF @equal IS DISTINCT FROM 1 THROW 51091, ''Long JSON values or column ordering failed.'', 1;

-- Arrange
SET @right = JSON_OBJECT(''id'': 1, ''text'': @text + N''y'');

-- Act
SET @equal = test.is_json_equal(@left, @right);

-- Assert
IF @equal IS DISTINCT FROM 0 THROW 51091, ''Long JSON values were truncated.'', 1;

-- Arrange
SET @unicode = NCHAR(0x0416) + NCHAR(0x4E2D)
	+ CONVERT(nvarchar(2), 0x3DD800DE);
SET @left = JSON_ARRAY(@unicode);
SET @right = N''["\u0416\u4e2d\ud83d\ude00"]'';

-- Act
SET @equal = test.is_json_equal(@left, @right);

-- Assert
IF @equal IS DISTINCT FROM 1 THROW 51091, ''Raw and escaped Unicode differ.'', 1;

-- Arrange
SET @left = JSON_ARRAY(NCHAR(8) + NCHAR(12) + NCHAR(10)
	+ NCHAR(13) + NCHAR(9) + N''/\"'');
SET @right = N''["\b\f\n\r\t\/\\\""]'';

-- Act
SET @equal = test.is_json_equal(@left, @right);

-- Assert
IF @equal IS DISTINCT FROM 1 THROW 51091, ''JSON escape decoding differs.'', 1;');
	DROP PROCEDURE IF EXISTS [tests].[test.is_equal_openjson@fc_json];
END;
GO

IF OBJECT_ID(N'[tests].[test.normalize_json@fc_normalization]', N'P') IS NOT NULL
    DROP PROCEDURE [tests].[test.normalize_json@fc_normalization];
IF OBJECT_ID(N'[tests].[test.normalize_json@fc_numbers]', N'P') IS NOT NULL
    DROP PROCEDURE [tests].[test.normalize_json@fc_numbers];
IF OBJECT_ID(N'[tests].[test.normalize_number@fc_numbers]', N'P') IS NOT NULL
    DROP PROCEDURE [tests].[test.normalize_number@fc_numbers];
IF OBJECT_ID(N'[test].[normalize_json]', N'FN') IS NOT NULL
    DROP FUNCTION [test].[normalize_json];
IF OBJECT_ID(N'[test].[normalize_number]', N'FN') IS NOT NULL
    DROP FUNCTION [test].[normalize_number];
IF OBJECT_ID(N'[test].[openjson_compare_value]', N'FN') IS NOT NULL
    DROP FUNCTION [test].[openjson_compare_value];
GO

CREATE OR ALTER procedure [tests].[test.test]
as
print N'Check discovery and metadata for two temporary test procs.'
print N'Expect: both procedures appear with the correct names.'
set nocount on
if @@trancount > 0 throw 51091, 'Discovery self-test requires no active transaction.', 1;

declare @expected nvarchar(max), @actual nvarchar(max)

-- Arrange
set @expected =
		N'[{"test_proc_full_name":"[tests].[temp-t-test.p1]","tested_object_full_name":"[temp-t-test].[p1]","tested_object_schema_name":"temp-t-test","tested_object_name":"p1","test_proc_name":"temp-t-test.p1"},'
		+ N'{"test_proc_full_name":"[tests].[temp-t-test.p2]","tested_object_full_name":"[temp-t-test].[p2]","tested_object_schema_name":"temp-t-test","tested_object_name":"p2","test_proc_name":"temp-t-test.p2"}]'
begin try
	begin tran
	exec(N'create proc [tests].[temp-t-test.p1] as return 0;')
	exec(N'create proc [tests].[temp-t-test.p2] as return 0;')

	-- Act
	set @actual = (
		select test_proc_full_name, tested_object_full_name,
			tested_object_schema_name, tested_object_name, tested_action, test_proc_name
		from test.test
		where tested_object_schema_name = 'temp-t-test'
		order by test_proc_name
		for json path
	)

	-- Assert
	EXEC test.assert_equals 'Discovery must return both temporary procedures and their metadata'
		, @expected
		, @actual;

	rollback
end try
begin catch
	if @@trancount > 0 rollback;
	throw;
end catch
GO

CREATE OR ALTER proc [tests].[test.test@name_convention]
as
print N'Check test names and referenced database objects.'
print N'Expect: every registered test has a valid name.'

set nocount on

declare @message nvarchar(max)
	, @assertion_result int

-- Arrange
--N/A

-- Act
select @message = 'Schema-qualified tests must reference existing objects; conceptual tests must use object@action: ' + string_agg(convert(nvarchar(max), test_proc_full_name), ', ')
from test.test as t
where object_id(t.tested_object_full_name) is null
	and not (t.tested_object_schema_name is null
		and coalesce(len(t.tested_object_name), 0) > 0
		and coalesce(len(t.tested_action), 0) > 0)
having count(*) > 0

-- Assert
if @message is not null
	set @assertion_result = test.fail(@message)
GO

GO

GO

GO

GO

GO

GO

CREATE OR ALTER PROC [tests].[test.throw]
AS
PRINT N'Check THROW, fail and missing-error sentinel helpers.';
PRINT N'Expect: 4 exceptions caught; NULL message stays NULL.';
SET NOCOUNT ON;

DECLARE @result nvarchar(max), @bytes varbinary(max),
	@proc_id int = OBJECT_ID(N'[tests].[test.throw]');

-- Arrange
--N/A

-- Act
SET @result = test.throw_error(NULL);
SET @bytes = CONVERT(varbinary(max), @result);

-- Assert
EXEC test.assert_null N'NULL error message stays NULL', @bytes;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.throw @message = N'Test exception!', @proc_id = @proc_id;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Thrown exception metadata', 70000,
		N'Test exception!%<Procedure:> [[]tests].[[]test.throw]%', 1;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	SET @result = test.throw_error(N'basic raw error');
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Raw error must be raised', 245,
		N'%basic raw error%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	SET @result = test.fail(N'basic explicit failure');
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Explicit failure must be raised', 245,
		N'%Unit-test fail: basic explicit failure%', DEFAULT;
END CATCH;

-- assert_error deliberately rejects the no-error sentinel.
-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.fail_no_error;
	THROW 51091, 'The no-error sentinel did not throw.', 1;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE N'Unit-test fail: <<No error>>%'
		THROW;
END CATCH;
GO

IF OBJECT_ID(N'[tests].[test.throw@fc_throwing]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.throw@fc_throwing]
AS
PRINT N''Throw 3 exceptions: no ID, valid ID, invalid ID.'';
PRINT N''Expect: all 3 caught; message and procedure ID verified.'';

DECLARE @id int, @caught bit, @i int, @message nvarchar(max), @scenario nvarchar(128);

SET @id = OBJECT_ID(N''[tests].[test.throw@fc_throwing]'');
SET @i = 0;
WHILE @i < 3
BEGIN
	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		IF @i = 0 EXEC test.throw @message = N''fc thrown exception'';
		ELSE IF @i = 1 EXEC test.throw @message = N''fc thrown exception'', @proc_id = @id;
		ELSE EXEC test.throw @message = N''fc thrown exception'', @proc_id = -1;
	END TRY
	BEGIN CATCH
		-- Assert
		SET @message = ERROR_MESSAGE();
		IF ERROR_NUMBER() = 70000 AND CHARINDEX(N''fc thrown exception'', @message) = 1
			AND ((@i = 0 AND @message = N''fc thrown exception'')
				OR (@i = 1 AND CHARINDEX(N''[tests].[test.throw@fc_throwing]'', @message) > 0)
				OR (@i = 2 AND CHARINDEX(N''<Procedure:> -1'', @message) > 0)) SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''throw code/message/procedure annotation changed.'', 1;
	SET @scenario = CASE @i
		WHEN 0 THEN N''no procedure ID supplied''
		WHEN 1 THEN N''valid procedure ID; name resolved''
		ELSE N''invalid procedure ID (-1); numeric fallback verified''
	END;
	RAISERROR(''[CAUGHT EXPECTED EXCEPTION] %s: %s'', 0, 1, @scenario, @message) WITH NOWAIT;
	SET @i += 1;
END;');
GO

CREATE OR ALTER PROC [tests].[stdev@basic]
AS
PRINT N'Check sample STDEV for four, one and zero values.';
PRINT N'Expect: reference result for four; NULL for one/zero.';
SET NOCOUNT ON;

DECLARE @four_samples float, @one_sample float, @empty_set float,
	@bytes varbinary(max);

-- Arrange
--N/A

-- Act
SELECT @four_samples = STDEV(CONVERT(float, n)) FROM (VALUES (1), (2), (3), (4)) v(n);
SELECT @one_sample = STDEV(CONVERT(float, n)) FROM (VALUES (1)) v(n);
SELECT @empty_set = STDEV(CONVERT(float, n)) FROM (VALUES (1)) v(n) WHERE n < 0;

-- Assert
EXEC test.assert_float_equals
	N'STDEV of 1,2,3,4 must match the reference within 1E-12',
	1.2909944487358056E0, @four_samples, 1E-12;
SET @bytes = CONVERT(varbinary(max), @one_sample);
EXEC test.assert_null N'STDEV of one sample must be NULL', @bytes;
SET @bytes = CONVERT(varbinary(max), @empty_set);
EXEC test.assert_null N'STDEV of an empty set must be NULL', @bytes;
GO

CREATE OR ALTER PROC [tests].[sys.objects@tables]
AS
PRINT N'Compare sys.objects user tables with sys.tables.';
PRINT N'Expect: all common columns match, including NULLs.';
SET NOCOUNT ON;

DECLARE @expected nvarchar(max), @actual nvarchar(max);

-- Arrange
SET @expected = (
	SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
		o.object_id, o.principal_id, o.schema_id, o.parent_object_id,
		o.type, o.type_desc, o.create_date, o.modify_date,
		o.is_ms_shipped, o.is_published, o.is_schema_published
	FROM sys.objects o
	WHERE o.type = N'U' AND o.is_ms_shipped = 0
	ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
		o.name COLLATE Latin1_General_100_BIN2
	FOR JSON PATH, INCLUDE_NULL_VALUES
);

-- Act
SET @actual = (
	SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
		o.object_id, o.principal_id, o.schema_id, o.parent_object_id,
		o.type, o.type_desc, o.create_date, o.modify_date,
		o.is_ms_shipped, o.is_published, o.is_schema_published
	FROM sys.tables o
	WHERE o.is_ms_shipped = 0
	ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
		o.name COLLATE Latin1_General_100_BIN2
	FOR JSON PATH, INCLUDE_NULL_VALUES
);

-- Assert
EXEC test.assert_equals N'sys.objects tables must match sys.tables', @expected, @actual;
GO

CREATE OR ALTER PROC [tests].[test.assert_equals]
AS
PRINT N'Check text, NULL, numeric, bit and date equality.';
PRINT N'Expect: equal values pass; text/float mismatches caught.';
SET NOCOUNT ON;

DECLARE @expected nvarchar(max), @actual nvarchar(max);

-- Arrange
--N/A

-- Act
EXEC test.assert_equals N'Equal text', N'value', N'value';
EXEC test.assert_equals N'Equal NULLs', NULL, NULL;
SET @expected = CAST(42 AS int);
SET @actual = 6 * 7;
EXEC test.assert_equals N'Equal integers', @expected, @actual;
SET @expected = CAST(9007199254740993 AS bigint);
SET @actual = CAST(9007199254740992 AS bigint) + 1;
EXEC test.assert_equals N'Equal big integers', @expected, @actual;
SET @expected = CAST(123.125 AS decimal(18, 4));
SET @actual = CAST(123 + 0.125 AS decimal(18, 4));
EXEC test.assert_equals N'Equal decimals', @expected, @actual;
SET @expected = CONVERT(nvarchar(32), 1.25E0, 3);
SET @actual = CONVERT(nvarchar(32), 0.5E0 + 0.75E0, 3);
EXEC test.assert_equals N'Equal floats without tolerance', @expected, @actual;
SET @expected = CAST(1 AS bit);
SET @actual = CAST(1 AS bit);
EXEC test.assert_equals N'Equal bits', @expected, @actual;
SET @expected = CAST('2026-03-04' AS date);
SET @actual = DATEFROMPARTS(2026, 3, 4);
EXEC test.assert_equals N'Equal dates', @expected, @actual;

-- Assert
IF test.is_equals(N'value', N'value') IS DISTINCT FROM 1
	OR test.is_equals(N'left', N'right') IS DISTINCT FROM 0
	OR test.is_equals(NULL, NULL) IS DISTINCT FROM 1
	OR test.is_equals(NULL, N'value') IS DISTINCT FROM 0
	OR test.is_equals(N'value', NULL) IS DISTINCT FROM 0
	THROW 51091, 'Equality predicate returned an incorrect result.', 1;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_equals N'basic equality mismatch', N'left', N'right';
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Mismatched values must fail', 70001,
		N'%Unit-test fail: basic equality mismatch%expected: <left>%but was : <right>%',
		DEFAULT;
END CATCH;

BEGIN TRY
	-- Arrange
	SET @expected = CONVERT(nvarchar(32), 1.25E0, 3);
	SET @actual = CONVERT(nvarchar(32), 1.2500000000000002E0, 3);

	-- Act
	EXEC test.assert_equals N'basic exact float mismatch', @expected, @actual;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Different floats must fail without tolerance', 70001,
		N'%Unit-test fail: basic exact float mismatch%expected:%but was :%', DEFAULT;
END CATCH;
GO

CREATE OR ALTER PROC [tests].[test.assert_not_null]
AS
PRINT N'Check non-NULL bytes, empty bytes and NULL.';
PRINT N'Expect: both byte values pass; NULL failure is caught.';
SET NOCOUNT ON;

-- Arrange
--N/A

-- Act
EXEC test.assert_not_null N'Non-NULL bytes', 0x01;
EXEC test.assert_not_null N'Empty bytes are not NULL', 0x;

-- Assert
IF test.is_not_null(NULL) IS DISTINCT FROM 0
	OR test.is_not_null(0x) IS DISTINCT FROM 1
	OR test.is_not_null(0x01) IS DISTINCT FROM 1
	THROW 51091, 'Non-NULL predicate returned an incorrect result.', 1;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_not_null N'basic NULL rejection', NULL;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'NULL must be rejected', 70001,
		N'%Unit-test fail: basic NULL rejection%', DEFAULT;
	RAISERROR('[CAUGHT EXPECTED EXCEPTION] NULL rejected.', 0, 1) WITH NOWAIT;
END CATCH;
GO

CREATE OR ALTER PROC [tests].[test.assert_null]
AS
PRINT N'Check NULLs, empty scalar SELECTs and empty aggregates.';
PRINT N'Expect: NULLs pass; empty bytes and zero are rejected.';
SET NOCOUNT ON;

DECLARE @empty_value nvarchar(128), @empty_sum int, @empty_count int,
	@bytes varbinary(max);

-- Arrange
SET @empty_value = (SELECT name FROM sys.tables WHERE 1 = 0);
SELECT @empty_sum = SUM(v.value), @empty_count = COUNT(*)
FROM (VALUES (1)) v(value)
WHERE 1 = 0;

-- Act
EXEC test.assert_null N'Literal NULL', NULL;
SET @bytes = CONVERT(varbinary(max), NULLIF(1, 1));
EXEC test.assert_null N'NULLIF returns NULL', @bytes;
SET @bytes = CONVERT(varbinary(max), @empty_value);
EXEC test.assert_null N'Empty scalar SELECT returns NULL', @bytes;
SET @bytes = CONVERT(varbinary(max), @empty_sum);
EXEC test.assert_null N'SUM of an empty set is NULL', @bytes;

-- Assert
IF test.is_null(NULL) IS DISTINCT FROM 1
	OR test.is_null(0x) IS DISTINCT FROM 0
	OR test.is_null(0x00) IS DISTINCT FROM 0
	THROW 51091, 'NULL predicate returned an incorrect result.', 1;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_null N'basic non-NULL rejection', 0x;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Empty bytes are not NULL', 70001,
		N'%Unit-test fail: basic non-NULL rejection%', DEFAULT;
	RAISERROR('[CAUGHT EXPECTED EXCEPTION] non-NULL bytes rejected.', 0, 1) WITH NOWAIT;
END CATCH;

BEGIN TRY
	-- Arrange
	SET @bytes = CONVERT(varbinary(max), @empty_count);

	-- Act
	EXEC test.assert_null N'COUNT of an empty set is zero', @bytes;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Zero is not NULL', 70001,
		N'%Unit-test fail: COUNT of an empty set is zero%', DEFAULT;
	RAISERROR('[CAUGHT EXPECTED EXCEPTION] zero rejected.', 0, 1) WITH NOWAIT;
END CATCH;
GO

CREATE OR ALTER PROC [tests].[test.is_equal]
AS
PRINT N'Check scalar equality and shallow ordered JSON.';
PRINT N'Expect: column order ignored; rows/types stay exact.';
SET NOCOUNT ON;

DECLARE @actual bit;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(NULL, NULL);

-- Assert
IF @actual IS DISTINCT FROM 1
	THROW 51091, 'NULL equality failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(NULL, N'');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'NULL versus text failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'value', N'value');

-- Assert
IF @actual IS DISTINCT FROM 1
	THROW 51091, 'Literal equality failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'left', N'right');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Different text failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'001.50', N'1.5');

-- Assert
IF @actual IS DISTINCT FROM 1
	THROW 51091, 'Scalar numeric shortcut failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'[{"id":1,"v":"a"}]', N'[{"v":"a","id":1}]');

-- Assert
IF @actual IS DISTINCT FROM 1
	THROW 51091, 'Column order failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'[{"id":1},{"id":2}]', N'[{"id":2},{"id":1}]');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Row order failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'[1]', N'[1.0]');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Numeric spelling failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'0.000000000000000000001', N'0');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Tiny nonzero decimal rounded to zero.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equals(N'1.000000000000000000001', N'1.000000000000000000002');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Equality alias rounded different high-precision decimals.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'0.000000000000000000005', N'0.00000000000000000001');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Decimal rounding boundary produced false equality.', 1;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_equals N'Tiny decimal regression.', N'0', N'0.000000000000000000001';
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() <> 70001 OR ERROR_MESSAGE() NOT LIKE N'%Tiny decimal regression.%'
		THROW 51091, 'assert_equals accepted a rounded decimal or raised the wrong error.', 1;
END CATCH;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'[1]', N'["1"]');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'JSON types failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_equal(N'[{"id":null}]', N'[{}]');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'NULL versus absent property failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_json_equal(N'[{"id":1,"v":"a"}]', N'[{"v":"a","id":1}]');

-- Assert
IF @actual IS DISTINCT FROM 1
	THROW 51091, 'Direct JSON column order failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_json_equal(N'[{"id":1},{"id":2}]', N'[{"id":2},{"id":1}]');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Direct JSON row order failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_json_equal(N'[1]', N'[1.0]');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Direct JSON numeric spelling failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_json_equal(N'[1]', N'["1"]');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Direct JSON types failed.', 1;

-- Arrange
--N/A

-- Act
SET @actual = test.is_json_equal(N'[{"id":null}]', N'[{}]');

-- Assert
IF @actual IS DISTINCT FROM 0
	THROW 51091, 'Direct JSON NULL versus absent failed.', 1;
GO

CREATE OR ALTER PROC [tests].[data_types@basic]
AS
PRINT N'Compare one row of numeric, text, date and spatial types.';
PRINT N'Expect: equal values; spatial WKT and SRID match.';
SET NOCOUNT ON;

DECLARE @expected nvarchar(max), @actual nvarchar(max),
	@geometry geometry, @geography geography;

-- Arrange
SET @geometry = geometry::Point(12.5, 45.25, 0);
SET @geography = geography::Point(45.25, 12.5, 4326);

SET @expected = (
	SELECT
		CAST(1 AS bit) AS bit_value,
		CAST(255 AS tinyint) AS tinyint_value,
		CAST(-12345 AS smallint) AS smallint_value,
		CAST(123456789 AS int) AS int_value,
		CAST(9007199254740993 AS bigint) AS bigint_value,
		CAST(12345678901234567890.12345678 AS decimal(28, 8)) AS decimal_value,
		CAST(-1234567890.1250 AS numeric(18, 4)) AS numeric_value,
		CAST(1234.1250 AS money) AS money_value,
		CAST(-123.1250 AS smallmoney) AS smallmoney_value,
		CAST(1.23456789012345E100 AS float) AS float_value,
		CAST(1.25E0 AS real) AS real_value,
		CAST('A' AS char(4)) AS char_value,
		CAST('quote " slash \' AS varchar(100)) AS varchar_value,
		REPLICATE(CAST('x' AS varchar(max)), 5000) AS varchar_max_value,
		CAST(NCHAR(381) AS nchar(4)) AS nchar_value,
		CAST(NCHAR(0x0416) + NCHAR(0x4E2D) + NCHAR(13) + NCHAR(10) AS nvarchar(100)) AS nvarchar_value,
		REPLICATE(CAST(NCHAR(381) AS nvarchar(max)), 5000) AS nvarchar_max_value,
		CAST(0x01020304 AS binary(4)) AS binary_value,
		CAST(0x00FF1020 AS varbinary(8)) AS varbinary_value,
		CAST(0x AS varbinary(max)) AS varbinary_max_value,
		CAST('2026-03-04' AS date) AS date_value,
		CAST('05:06:07.123456' AS time(6)) AS time_value,
		CAST('2026-03-04T05:06:07.123' AS datetime) AS datetime_value,
		CAST('2026-03-04T05:06:00' AS smalldatetime) AS smalldatetime_value,
		CAST('2026-03-04T05:06:07.123456' AS datetime2(6)) AS datetime2_value,
		CAST('2026-03-04T05:06:07.123456+02:00' AS datetimeoffset(6)) AS datetimeoffset_value,
		CAST('01234567-89AB-CDEF-0123-456789ABCDEF' AS uniqueidentifier) AS uniqueidentifier_value,
		CAST(NULL AS int) AS null_value,
		CAST(N'POINT (12.5 45.25)' AS nvarchar(100)) AS geometry_wkt,
		CAST(0 AS int) AS geometry_srid,
		CAST(N'POINT (12.5 45.25)' AS nvarchar(100)) AS geography_wkt,
		CAST(4326 AS int) AS geography_srid
	FOR JSON PATH, INCLUDE_NULL_VALUES
);

-- Act
SET @actual = (
	SELECT
		@geography.STSrid AS geography_srid,
		@geography.STAsText() AS geography_wkt,
		@geometry.STSrid AS geometry_srid,
		@geometry.STAsText() AS geometry_wkt,
		CAST(NULL AS int) AS null_value,
		CAST('01234567-89AB-CDEF-0123-456789ABCDEF' AS uniqueidentifier) AS uniqueidentifier_value,
		CAST('2026-03-04T05:06:07.123456+02:00' AS datetimeoffset(6)) AS datetimeoffset_value,
		CAST('2026-03-04T05:06:07.123456' AS datetime2(6)) AS datetime2_value,
		CAST('2026-03-04T05:06:00' AS smalldatetime) AS smalldatetime_value,
		CAST('2026-03-04T05:06:07.123' AS datetime) AS datetime_value,
		CAST('05:06:07.123456' AS time(6)) AS time_value,
		CAST('2026-03-04' AS date) AS date_value,
		CAST(0x AS varbinary(max)) AS varbinary_max_value,
		CAST(0x00FF1020 AS varbinary(8)) AS varbinary_value,
		CAST(0x01020304 AS binary(4)) AS binary_value,
		REPLICATE(CAST(NCHAR(381) AS nvarchar(max)), 5000) AS nvarchar_max_value,
		CAST(NCHAR(0x0416) + NCHAR(0x4E2D) + NCHAR(13) + NCHAR(10) AS nvarchar(100)) AS nvarchar_value,
		CAST(NCHAR(381) AS nchar(4)) AS nchar_value,
		REPLICATE(CAST('x' AS varchar(max)), 5000) AS varchar_max_value,
		CAST('quote " slash \' AS varchar(100)) AS varchar_value,
		CAST('A' AS char(4)) AS char_value,
		CAST(1.25E0 AS real) AS real_value,
		CAST(1.23456789012345E100 AS float) AS float_value,
		CAST(-123.1250 AS smallmoney) AS smallmoney_value,
		CAST(1234.1250 AS money) AS money_value,
		CAST(-1234567890.1250 AS numeric(18, 4)) AS numeric_value,
		CAST(12345678901234567890.12345678 AS decimal(28, 8)) AS decimal_value,
		CAST(9007199254740993 AS bigint) AS bigint_value,
		CAST(123456789 AS int) AS int_value,
		CAST(-12345 AS smallint) AS smallint_value,
		CAST(255 AS tinyint) AS tinyint_value,
		CAST(1 AS bit) AS bit_value
	FOR JSON PATH, INCLUDE_NULL_VALUES
);

-- Assert
EXEC test.assert_equals N'Inline rows must match across supported scalar types', @expected, @actual;
GO

CREATE OR ALTER PROC [tests].[test.assert_float_equals]
AS
PRINT N'Check FLOAT equality, tolerance, NULLs and extreme values.';
PRINT N'Expect: valid pairs pass; invalid comparisons are caught.';
SET NOCOUNT ON;

-- Arrange
--N/A

-- Act
EXEC test.assert_float_equals N'Exact, zero tolerance', 1.25, 1.25, 0;
EXEC test.assert_float_equals N'Within tolerance', 1, 1.0625, 0.125;
EXEC test.assert_float_equals N'Inclusive boundary', 1, 1.125, 0.125;
EXEC test.assert_float_equals N'Negative values', -1, -1.125, 0.125;
EXEC test.assert_float_equals N'Both NULL', NULL, NULL, 0;
EXEC test.assert_float_equals N'Opposite signs at boundary', 1, -1, 2;
EXEC test.assert_float_equals N'Large opposite signs within tolerance', 1E308, -7E307, 1.79E308;
EXEC test.assert_float_equals N'Large equal values', 1.7E308, 1.7E308, 0;
EXEC test.assert_float_equals N'Large same-sign values within tolerance', 1.7E308, 1.6E308, 2E307;

-- Assert
IF test.is_float_equal(1, 1, NULL) IS DISTINCT FROM 0
	OR test.is_float_equal(1, 1, -1) IS DISTINCT FROM 0
	OR test.is_float_equal(NULL, NULL, -1) IS DISTINCT FROM 0
	OR test.is_float_equal(NULL, NULL, NULL) IS DISTINCT FROM 0
	OR test.is_float_equal(NULL, NULL, 0) IS DISTINCT FROM 1
	OR test.is_float_equal(NULL, 1, 0) IS DISTINCT FROM 0
	OR test.is_float_equal(1, NULL, 0) IS DISTINCT FROM 0
	THROW 51091, 'FLOAT predicate mishandled tolerance or NULLs.', 1;
IF test.is_float_equal(1E308, -7E307, 1.79E308) IS DISTINCT FROM 1
	OR test.is_float_equal(1E308, -1E308, 1.79E308) IS DISTINCT FROM 0
	OR test.is_float_equal(-1E308, 1E308, 1.79E308) IS DISTINCT FROM 0
	OR test.is_float_equal(1, -1E-300, 1) IS DISTINCT FROM 0
	OR test.is_float_equal(-1E-300, 1, 1) IS DISTINCT FROM 0
	THROW 51091, 'FLOAT predicate mishandled opposite-sign arithmetic.', 1;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'Outside tolerance', 1, 1.25, 0.125;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Outside tolerance must fail', 70001,
		N'%Unit-test fail: Outside tolerance%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'Unequal, zero tolerance', 1, 1.125, 0;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Zero tolerance requires equality', 70001,
		N'%Unit-test fail: Unequal, zero tolerance%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'NULL expected', NULL, 1, 0.125;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'NULL expected must fail', 70001,
		N'%Unit-test fail: NULL expected%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'NULL actual', 1, NULL, 0.125;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'NULL actual must fail', 70001,
		N'%Unit-test fail: NULL actual%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'Negative tolerance', 1, 1, -1;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Negative tolerance must fail', 70001,
		N'%Unit-test fail: Negative tolerance%Absolute tolerance must be non-negative and not NULL.%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'NULL tolerance', 1, 1, NULL;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'NULL tolerance must fail', 70001,
		N'%Unit-test fail: NULL tolerance%Absolute tolerance must be non-negative and not NULL.%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'NULL pair, invalid tolerance', NULL, NULL, -1;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'NULL pair must not hide an invalid tolerance', 70001,
		N'%Unit-test fail: NULL pair, invalid tolerance%Absolute tolerance must be non-negative and not NULL.%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'Opposite signs outside tolerance', 1, -1, 1.5;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Opposite signs outside tolerance must fail', 70001,
		N'%Unit-test fail: Opposite signs outside tolerance%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'Opposite signs near zero', 1, -1E-300, 1;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Opposite signs near zero must differ', 70001,
		N'%Unit-test fail: Opposite signs near zero%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'Opposite signs near zero reversed', -1E-300, 1, 1;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Reversed opposite signs near zero must differ', 70001,
		N'%Unit-test fail: Opposite signs near zero reversed%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'Difference would overflow', 1E308, -1E308, 1.79E308;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Overflowing difference must fail as an assertion', 70001,
		N'%Unit-test fail: Difference would overflow%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'Large same-sign values outside tolerance', 1.7E308, 1E308, 1E307;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Large same-sign values outside tolerance must fail', 70001,
		N'%Unit-test fail: Large same-sign values outside tolerance%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_float_equals N'Tiny unequal values', 1E-300, 2E-300, 0;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Tiny unequal values must fail with zero tolerance', 70001,
		N'%Unit-test fail: Tiny unequal values%expected:%but was :%absolute tolerance:%', DEFAULT;
END CATCH;
GO

GO

CREATE OR ALTER PROC [tests].[test.assert_query_schemas_equal]
AS
PRINT N'Compare query schemas, not their returned data.';
PRINT N'Expect: names, order and SQL types must match.';
SET NOCOUNT ON;

DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max), @expected_schema_signature nvarchar(max);

-- Arrange
SET @expected_query = N'SELECT CAST(1 AS int) AS id, CAST(NULL AS varchar(20)) AS name WHERE 1 = 0;';

-- Act
SET @actual_query = N'SELECT CAST(99 AS int) AS id, CAST(''alpha'' AS varchar(20)) AS name;';

-- Assert
EXEC test.assert_query_schemas_equal N'Empty and populated results may have the same schema',
	@expected_query, @actual_query;

-- Arrange
SET @expected_schema_signature = N'[id] int, [amount] decimal(18,2)';

-- Act
SET @actual_query = N';WITH p AS (SELECT CAST(1 AS int) AS id, CAST(10.50 AS decimal(18,2)) AS amount)
	SELECT p.* FROM p;';

-- Assert
EXEC test.assert_schema_signature N'CTE projection matches its explicit schema', @expected_schema_signature, @actual_query;

-- Arrange
SET @expected_query = N'SELECT CAST(1 AS int) AS id, CAST(NULL AS varchar(20)) AS name;';

-- Act
SET @actual_query = N'SELECT CAST(NULL AS varchar(20)) AS name, CAST(1 AS int) AS id;';

-- Assert
BEGIN TRY
	EXEC test.assert_query_schemas_equal N'Column order must differ', @expected_query, @actual_query;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	EXEC test.assert_error N'Column order mismatch fails', 70001, N'%schema%';
END CATCH;

-- Arrange
SET @expected_schema_signature = N'[id] int';

-- Act
SET @actual_query = N'SELECT CAST(1 AS bigint) AS id;';

-- Assert
BEGIN TRY
	EXEC test.assert_schema_signature N'Column type must differ', @expected_schema_signature, @actual_query;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	EXEC test.assert_error N'Column type mismatch fails', 70001, N'%schema%';
END CATCH;

-- Arrange
SET @expected_schema_signature = N'[ID] int';

-- Act
SET @actual_query = N'SELECT CAST(1 AS int) AS id;';

-- Assert
BEGIN TRY
	EXEC test.assert_schema_signature N'Column name case must differ', @expected_schema_signature, @actual_query;
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	EXEC test.assert_error N'Case-sensitive column names fail', 70001, N'%schema%';
END CATCH;
GO

CREATE OR ALTER PROC [tests].[test.assert_resultset_equals]
AS
PRINT N'Compare catalog results and reject different data.';
PRINT N'Expect: values and explicit NULL columns matter.';
SET NOCOUNT ON;

DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max), @caught bit;

-- Arrange
SET @expected_query = N'
		SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
			o.object_id, o.principal_id, o.schema_id, o.parent_object_id,
			o.type, o.type_desc, o.create_date, o.modify_date,
			o.is_ms_shipped, o.is_published, o.is_schema_published
		FROM sys.objects o
		WHERE o.type = N''U'' AND o.is_ms_shipped = 0
		ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
			o.name COLLATE Latin1_General_100_BIN2';

-- Act
SET @actual_query = N'
		SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
			o.object_id, o.principal_id, o.schema_id, o.parent_object_id,
			o.type, o.type_desc, o.create_date, o.modify_date,
			o.is_ms_shipped, o.is_published, o.is_schema_published
		FROM sys.tables o
		WHERE o.is_ms_shipped = 0
		ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
			o.name COLLATE Latin1_General_100_BIN2';

-- Assert
EXEC test.assert_resultset_equals
	@message = N'sys.objects tables must match sys.tables',
	@expected_query = @expected_query,
	@actual_query = @actual_query;

-- Arrange
SET @expected_query = N'SELECT 1 AS value';
SET @actual_query = N'SELECT 2 AS value';
SET @caught = 0;

-- Act
BEGIN TRY
	EXEC test.assert_resultset_equals N'Different values', @expected_query, @actual_query;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() <> 70001 OR ERROR_MESSAGE() NOT LIKE N'%Unit-test fail: Different values%'
		THROW;
	SET @caught = 1;
END CATCH;
IF @caught = 0 THROW 51091, 'Resultset assertion accepted different values.', 1;

-- Arrange
SET @expected_query = N'SELECT 1 AS id, CAST(NULL AS int) AS value';
SET @actual_query = N'SELECT 1 AS id';
SET @caught = 0;

-- Act
BEGIN TRY
	EXEC test.assert_resultset_equals N'NULL is not an absent column', @expected_query, @actual_query;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() <> 70001 OR ERROR_MESSAGE() NOT LIKE N'%Unit-test fail: NULL is not an absent column%'
		THROW;
	SET @caught = 1;
END CATCH;
IF @caught = 0 THROW 51091, 'Resultset assertion omitted NULL columns.', 1;
GO

CREATE OR ALTER PROC [tests].[test.assert_error]
AS
PRINT N'Check caught error number, LIKE message and state.';
PRINT N'Expect: NULL/DEFAULT skip filters, but require an error.';
SET NOCOUNT ON;

DECLARE @legacy_sentinel varbinary(max);

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.assert_error N'No active CATCH', DEFAULT, DEFAULT, DEFAULT;
	THROW 51091, 'An assertion outside CATCH must fail.', 1;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
		N'%Unit-test fail: No active CATCH%Expected a caught error; none was caught.%'
		THROW;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	THROW 51024, N'assert_error reference_[x]', 17;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N'Any caught error', NULL, NULL, NULL;
	EXEC test.assert_error N'Number only', 51024, NULL, NULL;
	EXEC test.assert_error N'Message only', NULL, N'%reference%', NULL;
	EXEC test.assert_error N'State only', NULL, NULL, 17;
	EXEC test.assert_error N'Number and message', 51024, N'assert%', NULL;
	EXEC test.assert_error N'Number and state', 51024, NULL, 17;
	EXEC test.assert_error N'Message and state', NULL, N'%[[]x]', 17;
	EXEC test.assert_error N'All fields', 51024, N'%reference[_][[]x]', 17;
	EXEC test.assert_error N'Prefix pattern', NULL, N'assert_error reference%', NULL;
	EXEC test.assert_error N'Single-character wildcard', NULL, N'%referenc_%', NULL;
	EXEC test.assert_error N'Character class', NULL, N'%referenc[e]%', NULL;
	EXEC test.assert_error N'Escaped literal wildcards', NULL, N'assert[_]error reference[_][[]x]', NULL;
	EXEC test.assert_error N'DEFAULT filters', DEFAULT, DEFAULT, DEFAULT;
	EXEC test.assert_error N'Message-only DEFAULT filters', DEFAULT, N'%reference%', DEFAULT;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Wrong number', 51025, NULL, NULL;
		THROW 51091, 'A wrong number was accepted.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong number%Got error number: 51024%'
			THROW;
	END CATCH;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Wrong message', NULL, N'different message', NULL;
		THROW 51091, 'A wrong message was accepted.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong message%Got error number: 51024%'
			THROW;
	END CATCH;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Wrong state', NULL, NULL, 18;
		THROW 51091, 'A wrong state was accepted.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong state%Got error number: 51024%'
			THROW;
	END CATCH;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Matching number, wrong message', 51024, N'different message', NULL;
		THROW 51091, 'A wrong message with a matching number was accepted.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Matching number, wrong message%Got error number: 51024%'
			THROW;
	END CATCH;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Wrong number, matching message', 51025, N'%reference%', NULL;
		THROW 51091, 'A wrong number with a matching message was accepted.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong number, matching message%Got error number: 51024%'
			THROW;
	END CATCH;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Wrong state, matching message', 51024, N'%reference%', 18;
		THROW 51091, 'A wrong state with matching number/message was accepted.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong state, matching message%Got error number: 51024%'
			THROW;
	END CATCH;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Nonmatching fragment', NULL, N'%missing%', NULL;
		THROW 51091, 'A nonmatching fragment was accepted.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Nonmatching fragment%Got error number: 51024%'
			THROW;
	END CATCH;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Empty message is not omitted', NULL, N'', NULL;
		THROW 51091, 'An empty message filter was ignored.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Empty message is not omitted%Got error number: 51024%'
			THROW;
	END CATCH;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Zero is not an omitted state', NULL, NULL, 0;
		THROW 51091, 'A zero state filter was ignored.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Zero is not an omitted state%Got error number: 51024%'
			THROW;
	END CATCH;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Zero is not an omitted number', 0, NULL, NULL;
		THROW 51091, 'A zero number filter was ignored.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Zero is not an omitted number%Got error number: 51024%'
			THROW;
	END CATCH;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.fail_no_error;
	THROW 51091, 'The no-error sentinel did not throw.', 1;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE N'Unit-test fail: <<No error>>%'
		THROW;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N'Sentinel is not a caught application error', 70001, DEFAULT, DEFAULT;
		THROW 51091, 'The no-error sentinel was accepted.', 1;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() IS DISTINCT FROM 70001 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Sentinel is not a caught application error%Expected a caught error; none was caught.%'
			THROW;
	END CATCH;
END CATCH;

-- Arrange
--N/A

-- Act
SET @legacy_sentinel = CONVERT(varbinary(max), OBJECT_ID(N'[test].[error]', N'FN'));

-- Assert
EXEC test.assert_null N'Upgrade must retire the legacy no-error sentinel', @legacy_sentinel;
GO

-- Migrate framework-owned sentinel tests before retiring legacy names.
IF OBJECT_ID(N'[tests].[test.throw_error@fc_error_helpers]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.throw_error@fc_error_helpers]
AS
PRINT N''Check error helpers and numeric/empty messages.'';
PRINT N''Expect: NULL stays NULL; 11 invalid calls are caught.'';

DECLARE @result nvarchar(max), @caught bit, @i int, @message nvarchar(max),
	@numeric_messages nvarchar(max), @number_message nvarchar(max);

-- Arrange
SET @i = 0;
SET @numeric_messages = N''["123",""," ","-2","+3","0004","2147483647","-2147483648"]'';

-- Act
SET @result = test.throw_error(NULL);

-- Assert
IF @result IS NOT NULL THROW 51091, ''throw_error(NULL) must return NULL.'', 1;

WHILE @i < 3
BEGIN
	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		IF @i = 0 SET @result = test.throw_error(N''fc raw error'');
		ELSE IF @i = 1 SET @result = test.fail(N''fc explicit fail'');
		ELSE EXEC test.fail_no_error;
	END TRY
	BEGIN CATCH
		-- Assert
		SET @message = ERROR_MESSAGE();
		IF (ERROR_NUMBER() = 245 AND (
			(@i = 0 AND CHARINDEX(N''fc raw error'', @message) > 0) OR
			(@i = 1 AND CHARINDEX(N''Unit-test fail: fc explicit fail'', @message) > 0)))
			OR (@i = 2 AND ERROR_NUMBER() = 70001
				AND @message LIKE N''Unit-test fail: <<No error>>%'') SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''An error/fail helper did not throw the expected marker.'', 1;
	SET @i += 1;
END;

SET @i = 0;
WHILE @i < 8
BEGIN
	-- Arrange
	SELECT @number_message = value FROM OPENJSON(@numeric_messages) WHERE [key] = CONVERT(nvarchar(10), @i);
	SET @caught = 0;

	-- Act
	BEGIN TRY
		SET @result = test.throw_error(@number_message);
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Error: '', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''A numeric or empty raw error message did not throw.'', 1;
	SET @i += 1;
END;');
GO

IF OBJECT_ID(N'[tests].[test.error@fc_no_error]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.fail_no_error@fc_no_error]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.fail_no_error@fc_no_error]
AS
PRINT N''Call fail_no_error after an expected error is missing.'';
PRINT N''Expect: its no-error marker is raised and caught.'';

DECLARE @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 70001 AND ERROR_MESSAGE() LIKE N''Unit-test fail: <<No error>>%'' SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''fail_no_error did not raise its no-error marker.'', 1;');
GO

IF OBJECT_ID(N'[tests].[test.assert_error_like@fc_patterns]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.assert_error@fc_patterns]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.assert_error@fc_patterns]
AS
PRINT N''Check error LIKE patterns and the no-error marker.'';
PRINT N''Expect: matching passes; the invalid match is caught.'';

DECLARE @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	THROW 51011, ''fc wildcard_value'', 1;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N''literal underscore and wildcard'', DEFAULT, N''fc wildcard[_]%'', DEFAULT;
END CATCH;

-- Arrange
--N/A

-- Act
BEGIN TRY
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	BEGIN TRY
		EXEC test.assert_error N''fc no-error marker must be rejected'', DEFAULT, N''%<<No error>>%'', DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc no-error marker must be rejected'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;
END CATCH;

IF @caught = 0 THROW 51091, ''assert_error accepted the no-error marker.'', 1;');
GO

IF OBJECT_ID(N'[tests].[test.assert_error_number@fc_error_assertions]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.assert_error@fc_error_assertions]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.assert_error@fc_error_assertions]
AS
PRINT N''Check matching/mismatching error numbers and patterns.'';
PRINT N''Expect: matches pass; invalid checks throw and are caught.'';

DECLARE @caught bit, @value int, @i int;

-- Arrange
SET @caught = 0;

-- A real conversion error must still be accepted.
-- Act
BEGIN TRY
	SET @value = CONVERT(int, N''fc genuine conversion error'');
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() <> 245 THROW;
	EXEC test.assert_error N''genuine conversion error'', 245, DEFAULT, DEFAULT;
	SET @caught = 1;
END CATCH;

IF @caught = 0
	THROW 51091, ''A genuine conversion error was not accepted.'', 1;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	THROW 51011, ''fc expected exception'', 1;
END TRY
BEGIN CATCH
	-- Assert
	EXEC test.assert_error N''matching number'', 51011, DEFAULT, DEFAULT;
	EXEC test.assert_error N''matching pattern'', DEFAULT, N''%fc expected exception%'', DEFAULT;

	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.assert_error N''fc wrong number'', 51012, DEFAULT, DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc wrong number'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''Wrong error number was accepted.'', 1;

	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		EXEC test.assert_error N''fc wrong pattern'', DEFAULT, N''%not the actual message%'', DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc wrong pattern'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''Wrong error pattern was accepted.'', 1;
END CATCH;
-- The no-error sentinel must NOT satisfy even its matching native error number.
-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	EXEC test.fail_no_error;
END TRY
BEGIN CATCH
	BEGIN TRY
		EXEC test.assert_error N''fc sentinel is not a real conversion error'', 70001, DEFAULT, DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(
			N''Unit-test fail: fc sentinel is not a real conversion error'', ERROR_MESSAGE()) > 0
			SET @caught = 1;
	END CATCH;
END CATCH;

IF @caught = 0 THROW 51091, ''Error number assertion accepted the no-error sentinel.'', 1;
SET @i = 0;
WHILE @i < 2
BEGIN
	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		IF @i = 0 EXEC test.assert_error N''fc no active error'', 51011, DEFAULT, DEFAULT;
		ELSE EXEC test.assert_error N''fc no active error'', DEFAULT, N''%anything%'', DEFAULT;
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc no active error'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''An error assertion passed outside CATCH.'', 1;
	SET @i += 1;
END;');
GO

IF OBJECT_ID(N'[tests].[test.fail_no_error@fc_no_error]', N'P') IS NOT NULL
	DROP PROCEDURE IF EXISTS [tests].[test.error@fc_no_error];
IF OBJECT_ID(N'[test].[fail_no_error]', N'P') IS NOT NULL
	AND OBJECT_ID(N'[test].[error]', N'FN') IS NOT NULL
	DROP FUNCTION [test].[error];
GO

-- Retire renamed framework APIs after their replacements and owned callers exist.
IF OBJECT_ID(N'[tests].[test.assert_resultset_equals]', N'P') IS NOT NULL
	AND OBJECT_ID(N'[test].[assert_resultset_equals]', N'P') IS NOT NULL
BEGIN
	DROP PROCEDURE IF EXISTS [tests].[test.assert_query_equals];
	DROP PROCEDURE IF EXISTS [test].[assert_query_equals];
END;
IF OBJECT_ID(N'[test].[is_json_equal]', N'FN') IS NOT NULL
	AND OBJECT_ID(N'[test].[is_equal_openjson]', N'FN') IS NOT NULL
	DROP FUNCTION [test].[is_equal_openjson];
GO

IF OBJECT_ID(N'[tests].[test.assert_error@fc_patterns]', N'P') IS NOT NULL
	DROP PROCEDURE IF EXISTS [tests].[test.assert_error_like@fc_patterns];
IF OBJECT_ID(N'[tests].[test.assert_error@fc_error_assertions]', N'P') IS NOT NULL
	DROP PROCEDURE IF EXISTS [tests].[test.assert_error_number@fc_error_assertions];
IF OBJECT_ID(N'[test].[assert_error]', N'P') IS NOT NULL
BEGIN
	IF OBJECT_ID(N'[test].[assert_error_like]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[assert_error_like];
	IF OBJECT_ID(N'[test].[assert_error_number]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[assert_error_number];
END;
GO

CREATE OR ALTER PROCEDURE [tests].[power@vectors]
	@base int,
	@exponent int,
	@expected int
AS
BEGIN
	PRINT N'Check POWER using registered argument vectors.';
	PRINT N'Expect: results match the third vector argument.';
	SET NOCOUNT ON;
	DECLARE @actual int;

	-- Arrange
	--N/A

	-- Act
	SET @actual = POWER(@base, @exponent);

	-- Assert
	EXEC test.assert_equals N'POWER(base,exponent)', @expected, @actual;
END;
GO

CREATE OR ALTER PROCEDURE [tests].[replicate@dimensions]
	@number int = 1,
	@text nvarchar(max) = N'a'
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected bigint, @actual bigint;

	-- Arrange
	SET @expected = @number * DATALENGTH(@text);

	-- Act
	SET @actual = DATALENGTH(REPLICATE(@text, @number));

	-- Assert
	EXEC test.assert_equals N'REPLICATE byte length', @expected, @actual;
END;
GO

INSERT [test].[test_vectors] (procedure_name, parameters)
SELECT N'[tests].[power@vectors]', v.parameters
FROM (VALUES (N'2,3,8'), (N'3,2,9'), (N'5,0,1'), (N'-2,3,-8')) v(parameters)
WHERE NOT EXISTS (
	SELECT 1
	FROM [test].[test_vectors] AS existing
	WHERE existing.procedure_name COLLATE Latin1_General_100_BIN2_UTF8 = N'[tests].[power@vectors]'
		AND existing.parameters COLLATE Latin1_General_100_BIN2_UTF8 = v.parameters
);
GO

-- Refresh already-installed shipped assertion callers; do not rewrite custom tests.
IF OBJECT_ID(N'[tests].[test.assert_equals@fc_assertions]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.assert_equals@fc_assertions]
AS
PRINT N''Check equality/NULL assertions and 3 failure cases.'';
PRINT N''Expect: valid checks pass; all 3 failures are caught.'';

DECLARE @caught bit, @i int, @message nvarchar(max);

-- Arrange
SET @i = 0;

-- Act
EXEC test.assert_equals N''equal'', N''1.0'', N''1'';
EXEC test.assert_null N''null'', NULL;
EXEC test.assert_not_null N''not null'', 0x;

-- Assert
-- Successful return of the valid assertions is checked by the positive-suite summary.

WHILE @i < 3
BEGIN
	-- Arrange
	SET @caught = 0;

	-- Act
	BEGIN TRY
		IF @i = 0 EXEC test.assert_equals N''fc assertion marker'', N''a'', N''b'';
		ELSE IF @i = 1 EXEC test.assert_null N''fc assertion marker'', 0x01;
		ELSE EXEC test.assert_not_null N''fc assertion marker'', NULL;
	END TRY
	BEGIN CATCH
		-- Assert
		SET @message = ERROR_MESSAGE();
		IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''Unit-test fail:'', @message) > 0
			AND CHARINDEX(N''fc assertion marker'', @message) > 0 SET @caught = 1;
	END CATCH;

	IF @caught = 0 THROW 51091, ''A failing assertion did not raise its failure marker.'', 1;
	SET @i += 1;
END;');
GO

IF OBJECT_ID(N'[tests].[test.assert_not_null@fc_not_null]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.assert_not_null@fc_not_null]
AS
PRINT N''Check that assert_not_null rejects only NULL.'';
PRINT N''Expect: zero bytes pass; the NULL failure is caught.'';

DECLARE @caught bit;

-- Arrange
SET @caught = 0;

-- Act
EXEC test.assert_not_null N''zero bytes are not NULL'', 0x0000;

BEGIN TRY
	EXEC test.assert_not_null N''fc NULL must fail'', NULL;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc NULL must fail'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''assert_not_null accepted NULL.'', 1;');
GO

IF OBJECT_ID(N'[tests].[test.assert_null@fc_null]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.assert_null@fc_null]
AS
PRINT N''Check that assert_null accepts only NULL.'';
PRINT N''Expect: NULL passes; the non-NULL failure is caught.'';

DECLARE @caught bit;

-- Arrange
SET @caught = 0;

-- Act
EXEC test.assert_null N''NULL is NULL'', NULL;

BEGIN TRY
	EXEC test.assert_null N''fc empty binary is not NULL'', 0x;
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 70001 AND CHARINDEX(N''fc empty binary is not NULL'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''assert_null accepted an empty non-NULL value.'', 1;');
GO

IF OBJECT_ID(N'[tests].[test.fail@fc_failure]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.fail@fc_failure]
AS
PRINT N''Call fail() with a numeric message and with NULL.'';
PRINT N''Expect: both calls throw; both exceptions are caught.'';

DECLARE @result int, @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	SET @result = test.fail(N''123'');
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Unit-test fail: 123'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''fail did not reject a numeric-only message.'', 1;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	SET @result = test.fail(NULL);
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Unit-test fail:'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

IF @caught = 0 THROW 51091, ''fail(NULL) did not raise a failure.'', 1;');
GO

IF OBJECT_ID(N'[tests].[test.log@fc_logging]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.log@fc_logging]
AS
PRINT N''Check logger levels, parameters and chunked output.'';
PRINT N''Expect: sample WARNING/DEBUG logs; all 4100 chars printed.'';

DECLARE @id int, @data nvarchar(max), @multiline nvarchar(max), @hex nvarchar(4000),
	@boundary nvarchar(max);

-- Arrange
SET @id = OBJECT_ID(N''[tests].[test.log@fc_logging]'');
SET @data = REPLICATE(CAST(N''x'' AS nvarchar(max)), 4100);
SET @multiline = N''first'' + NCHAR(13) + NCHAR(10) + N''second'';
SET @hex = CONVERT(nvarchar(4000), 0x0102, 1);
SET @boundary = REPLICATE(CAST(N''x'' AS nvarchar(max)), 2040) + N''%'';
-- SQL cannot capture PRINT/InfoMessage text: these are explicit output-path smoke checks.

-- Act
EXEC test.log @message = NULL, @data = NULL;
EXEC test.log @message = N''fc logger %1 %2 %3 %4 100%'', @p1 = 42, @p2 = NULL,
	@p3 = @hex, @p4_str = N''wide text'', @rowcount = 0, @proc_id = @id, @severity = N''warning'';
EXEC test.log @message = N''fc inline data'', @data = N''short 100% data'', @severity = N''info'';
EXEC test.log @message = N''fc multiline data'', @data = @multiline;
EXEC test.log @message = N''fc chunked data (4100 characters)'', @data = @data;

-- A literal percent at a truncation boundary must not become a format token.
EXEC test.log @message = @boundary;
EXEC test.log @message = N''fc boundary data'', @data = @boundary;

-- Assert
-- Successful return is verified by the positive-suite runner summary below.
');
GO

IF OBJECT_ID(N'[tests].[test.set_registration_scope@fc_context]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.set_scope@fc_context]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.set_registration_scope@fc_context]
AS
PRINT N''Check mutable session/global scope in SESSION_CONTEXT.'';
PRINT N''Expect: exact values; invalid input preserves the last scope.'';
SET NOCOUNT ON;
DECLARE @session_rejected bit = 0;
DECLARE @previous sql_variant,
	@actual sql_variant, @actual_type nvarchar(128), @scope nvarchar(max), @i int = 0, @caught bit,
	@scopes nvarchar(max) = N''["session","global","session","global"]'',
	@invalid nvarchar(max) = N''[null,"","GLOBAL","SESSION","global ","session "]'';
IF CAST(SERVERPROPERTY(''EngineEdition'') AS int) = 11
BEGIN
	-- Arrange
	--N/A

	-- Act
	BEGIN TRY
		EXEC test.set_registration_scope N''session'';
	END TRY
	BEGIN CATCH
		-- Assert
		IF ERROR_NUMBER() <> 70000 THROW;
		SET @session_rejected = 1;
	END CATCH;

	IF @session_rejected = 0 THROW 51091, ''Fabric Warehouse accepted session scope.'', 1;
	EXEC test.set_registration_scope N''global'';
	PRINT N''SKIP: mutable session scope is not available on Fabric Warehouse.'';
	RETURN;
END;
SELECT @previous = SESSION_CONTEXT(N''ttest:vectors:scope'');
BEGIN TRY
	WHILE @i < 4
	BEGIN
		-- Arrange
		SELECT @scope = value FROM OPENJSON(@scopes) WHERE CONVERT(int, [key]) = @i;

		-- Act
		EXEC test.set_registration_scope @scope;
		SELECT @actual = SESSION_CONTEXT(N''ttest:vectors:scope'');
		EXEC sys.sp_executesql
			N''SELECT @actual_type = CONVERT(nvarchar(128), SQL_VARIANT_PROPERTY(@actual, N''''BaseType''''));'',
			N''@actual sql_variant, @actual_type nvarchar(128) OUTPUT'',
			@actual = @actual, @actual_type = @actual_type OUTPUT;

		-- Assert
		IF CONVERT(nvarchar(4000), @actual) COLLATE Latin1_General_100_BIN2
				IS DISTINCT FROM @scope COLLATE Latin1_General_100_BIN2
			OR DATALENGTH(CONVERT(nvarchar(4000), @actual)) IS DISTINCT FROM DATALENGTH(@scope)
			OR @actual_type IS DISTINCT FROM N''nvarchar''
			THROW 51091, ''set_registration_scope did not store the exact mutable Unicode scope.'', 1;
		SET @i += 1;
	END;
	SET @i = 0;
	WHILE @i < (SELECT COUNT(*) FROM OPENJSON(@invalid))
	BEGIN
		-- Arrange
		SELECT @scope = value FROM OPENJSON(@invalid) WHERE CONVERT(int, [key]) = @i;
		SET @caught = 0;

		-- Act
		BEGIN TRY
			EXEC test.set_registration_scope @scope;
		END TRY
		BEGIN CATCH
			-- Assert
			IF ERROR_NUMBER() <> 70000 THROW;
			SET @caught = 1;
		END CATCH;

		SELECT @actual = SESSION_CONTEXT(N''ttest:vectors:scope'');
		IF @caught = 0 OR CONVERT(nvarchar(4000), @actual)
			COLLATE Latin1_General_100_BIN2 IS DISTINCT FROM N''global''
			THROW 51091, ''Invalid scope was accepted or changed SESSION_CONTEXT.'', 1;
		SET @i += 1;
	END;
END TRY
BEGIN CATCH
	EXEC sys.sp_set_session_context @key = N''ttest:vectors:scope'', @value = @previous;
	THROW;
END CATCH;
EXEC sys.sp_set_session_context @key = N''ttest:vectors:scope'', @value = @previous;');
GO

IF @@TRANCOUNT = 0
BEGIN
	IF OBJECT_ID(N'[tests].[test.assert_query_schemas_equal]', N'P') IS NOT NULL
	BEGIN
		IF OBJECT_ID(N'test.test_vectors', N'U') IS NOT NULL
			EXEC(N'UPDATE test.test_vectors
				SET procedure_name = ''[tests].[test.assert_query_schemas_equal]''
				WHERE procedure_name = ''[tests].[test.assert_schema_equals]'';');
		IF OBJECT_ID(N'test.test_dimension_values', N'U') IS NOT NULL
			EXEC(N'UPDATE test.test_dimension_values
				SET procedure_name = ''[tests].[test.assert_query_schemas_equal]''
				WHERE procedure_name = ''[tests].[test.assert_schema_equals]'';');
		DROP PROCEDURE IF EXISTS [tests].[test.assert_schema_equals];
	END;
	IF OBJECT_ID(N'[tests].[test.set_registration_scope@fc_context]', N'P') IS NOT NULL
	BEGIN
		IF OBJECT_ID(N'test.test_vectors', N'U') IS NOT NULL
			EXEC(N'UPDATE test.test_vectors
				SET procedure_name = ''[tests].[test.set_registration_scope@fc_context]''
				WHERE procedure_name = ''[tests].[test.set_scope@fc_context]'';');
		IF OBJECT_ID(N'test.test_dimension_values', N'U') IS NOT NULL
			EXEC(N'UPDATE test.test_dimension_values
				SET procedure_name = ''[tests].[test.set_registration_scope@fc_context]''
				WHERE procedure_name = ''[tests].[test.set_scope@fc_context]'';');
		DROP PROCEDURE IF EXISTS [tests].[test.set_scope@fc_context];
	END;
	DROP PROCEDURE IF EXISTS [test].[set_scope];
	DROP PROCEDURE IF EXISTS [test].[reset];
	DROP PROCEDURE IF EXISTS [test].[assert_schema];
	DROP PROCEDURE IF EXISTS [test].[assert_schema_equals];
	IF OBJECT_ID(N'[test].[is_float_equals]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[is_float_equals];
END;
GO

IF OBJECT_ID(N'[tests].[test.test@fc_catalog]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.test@fc_catalog]
AS
PRINT N''Check discovery, name parsing and invalid test names.'';
PRINT N''Expect: valid names parse; malformed names are rejected.'';
SET NOCOUNT ON;
IF @@TRANCOUNT > 0 THROW 51091, ''Catalog self-test requires no active transaction.'', 1;

DECLARE @invalid_one bit, @invalid_two bit, @invalid_three bit, @naming_error nvarchar(max),
	@schema nvarchar(128), @object nvarchar(128), @action nvarchar(128), @main nvarchar(128),
	@conceptual_count int;

-- Arrange
SET @invalid_one = 0;
SET @invalid_two = 0;
SET @invalid_three = 0;
IF OBJECT_ID(N''[tests].[fc_catalog_invalid]'') IS NOT NULL
	OR OBJECT_ID(N''[tests].[fc_catalog_invalid@]'') IS NOT NULL
	OR OBJECT_ID(N''[tests].[@fc_catalog_invalid]'') IS NOT NULL
	THROW 51091, ''Catalog fixture name already exists.'', 1;
BEGIN TRY
BEGIN TRAN;
EXEC(N''CREATE PROC [tests].[test.run@fc_catalog_probe] AS RETURN 0;'');
EXEC(N''CREATE PROC [tests].[fc_catalog_concept@fc_catalog_probe] AS RETURN 0;'');
EXEC(N''CREATE PROC [tests].[fc_catalog_concept@fc_catalog_probe.with.dot] AS RETURN 0;'');

-- Discovery must preserve both conceptual actions.
-- Act
SET @conceptual_count = (SELECT COUNT(*) FROM test.test
	WHERE test_proc_name IN (N''fc_catalog_concept@fc_catalog_probe'', N''fc_catalog_concept@fc_catalog_probe.with.dot'')
		AND tested_object_schema_name IS NULL AND tested_object_full_name IS NULL
		AND tested_object_main_schema_name IS NULL AND tested_object_name = N''fc_catalog_concept''
		AND tested_action = STUFF(test_proc_name, 1, CHARINDEX(''@'', test_proc_name), N''''));

-- Assert
IF @conceptual_count <> 2
	THROW 51091, ''Conceptual discovery must preserve the object/action without assigning a schema.'', 1;
EXEC [tests].[test.test@name_convention];

-- Arrange
EXEC(N''CREATE PROC [tests].[private.test.run@fc_catalog_probe] AS RETURN 0;'');
EXEC(N''CREATE PROC [tests].[test.log@fc_catalog_probe]]edge@extra] AS RETURN 0;'');

-- Act
SELECT @schema = tested_object_schema_name, @object = tested_object_name,
	@action = tested_action, @main = tested_object_main_schema_name
FROM test.test WHERE test_proc_full_name = N''[tests].[test.run@fc_catalog_probe]'';

-- Assert
IF @schema IS DISTINCT FROM N''test'' OR @object IS DISTINCT FROM N''run''
	OR @action IS DISTINCT FROM N''fc_catalog_probe'' OR @main IS DISTINCT FROM N''test''
	THROW 51091, ''Regular discovery/name parsing failed.'', 1;

-- Arrange
--N/A

-- Act
SELECT @schema = tested_object_schema_name, @object = tested_object_name, @main = tested_object_main_schema_name
FROM test.test WHERE test_proc_full_name = N''[tests].[private.test.run@fc_catalog_probe]'';

-- Assert
IF @schema IS DISTINCT FROM N''private'' OR @object IS DISTINCT FROM N''test.run'' OR @main IS DISTINCT FROM N''test''
	THROW 51091, ''Private-schema main-schema parsing failed.'', 1;

-- Arrange
SET @action = NULL;

-- Act
SELECT @action = tested_action FROM test.test
WHERE test_proc_full_name = N''[tests].[test.log@fc_catalog_probe]]edge@extra]'';

-- Assert
IF @action IS DISTINCT FROM N''fc_catalog_probe]edge@extra''
	THROW 51091, ''Bracket escaping or multiple action separators failed.'', 1;
ROLLBACK;

-- UDF assertion errors can doom an explicit transaction, so run invalid-name probes outside it.
-- Arrange
EXEC(N''CREATE PROC [tests].[fc_catalog_invalid] AS RETURN 0;'');
SET @invalid_one = 1;
EXEC(N''CREATE PROC [tests].[fc_catalog_invalid@] AS RETURN 0;'');
SET @invalid_two = 1;
EXEC(N''CREATE PROC [tests].[@fc_catalog_invalid] AS RETURN 0;'');
SET @invalid_three = 1;

-- Act
BEGIN TRY
	EXEC [tests].[test.test@name_convention];
END TRY
BEGIN CATCH
	-- Assert
	IF ERROR_NUMBER() <> 245 THROW;
	SET @naming_error = ERROR_MESSAGE();
END CATCH;

IF @naming_error IS NULL
	OR CHARINDEX(N''[tests].[fc_catalog_invalid]'', @naming_error) = 0
	OR CHARINDEX(N''[tests].[fc_catalog_invalid@]'', @naming_error) = 0
	OR CHARINDEX(N''[tests].[@fc_catalog_invalid]'', @naming_error) = 0
	THROW 51091, ''Naming validation must reject malformed conceptual names.'', 1;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;
	IF @invalid_one = 1 DROP PROC [tests].[fc_catalog_invalid];
	IF @invalid_two = 1 DROP PROC [tests].[fc_catalog_invalid@];
	IF @invalid_three = 1 DROP PROC [tests].[@fc_catalog_invalid];
	THROW;
END CATCH;

-- Cleanup is required on success and on unexpected validator errors.
DROP PROC [tests].[fc_catalog_invalid];
DROP PROC [tests].[fc_catalog_invalid@];
DROP PROC [tests].[@fc_catalog_invalid];');
GO

IF OBJECT_ID(N'[tests].[test.vector@fc_literals]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER   PROC [tests].[test.vector@fc_literals]
	@case_id int = 0,
	@number bigint = 7,
	@amount decimal(18,4) = 1.5000,
	@approx float = 1.25e0,
	@flag bit = 1,
	@text nvarchar(max) = N''default'',
	@day date = ''20260304'',
	@stamp datetime2(6) = ''2026-03-04T05:06:07.123456'',
	@bytes varbinary(8) = 0x01
AS
PRINT N''Check typed vector arguments, Unicode, NULL and DEFAULT.'';
PRINT N''Expect: SQL preserves values across positional/named literal arguments.'';
SET NOCOUNT ON;

DECLARE @matches bit;

-- Arrange
--N/A

-- Act
SET @matches = CASE WHEN EXISTS (
	SELECT 1
	FROM (VALUES
		(0, CAST(7 AS bigint), CAST(1.5000 AS decimal(18,4)), CAST(1.25 AS float),
			CAST(1 AS bit), CAST(N''default'' AS nvarchar(max)), CAST(''20260304'' AS date),
			CAST(''2026-03-04T05:06:07.123456'' AS datetime2(6)), CAST(0x01 AS varbinary(8))),
		(1, CAST(-9223372036854775808 AS bigint), -1234.5678, -0.000125,
			1, N''O''''Brien, Jr.'', CAST(''20240229'' AS date),
			CAST(''2024-02-29T01:02:03.123456'' AS datetime2(6)), 0x00FF),
		(2, CAST(9223372036854775807 AS bigint), 0.0001, 1250.0,
			0, NCHAR(381) + NCHAR(0x4E2D) + N'', O''''Brien\path'', CAST(''20261231'' AS date),
			CAST(''2026-12-31T23:59:59.999999'' AS datetime2(6)), 0x),
		(3, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL),
		(4, 0, 0.0000, 0.0, 0, N'''', NULL, NULL, 0x)
	) expected(case_id, number, amount, approx, flag, text_value, day_value, stamp, bytes)
	WHERE @case_id = expected.case_id
		AND @number IS NOT DISTINCT FROM expected.number
		AND @amount IS NOT DISTINCT FROM expected.amount
		AND @approx IS NOT DISTINCT FROM expected.approx
		AND @flag IS NOT DISTINCT FROM expected.flag
		AND CONVERT(varbinary(max), @text) IS NOT DISTINCT FROM CONVERT(varbinary(max), expected.text_value)
		AND @day IS NOT DISTINCT FROM expected.day_value
		AND @stamp IS NOT DISTINCT FROM expected.stamp
		AND @bytes IS NOT DISTINCT FROM expected.bytes
) THEN 1 ELSE 0 END;

-- Assert
IF @matches IS DISTINCT FROM 1
	THROW 51091, ''Typed vector arguments differed from the independent expected values.'', 1;');
GO

-- Refresh only already-installed shipped catalog comparison tests.
DECLARE @cases nvarchar(max) = N'[
  {
    "case_id": 1,
    "action_name": "views",
    "objects_filter": "o.type = N''V'' AND o.is_ms_shipped = 0",
    "objects_projection": "SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published",
    "counterpart_query": "SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published FROM sys.[views] o WHERE o.type = N''V'' AND o.is_ms_shipped = 0"
  },
  {
    "case_id": 2,
    "action_name": "procedures",
    "objects_filter": "o.type = N''P'' AND o.is_ms_shipped = 0",
    "objects_projection": "SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published",
    "counterpart_query": "SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published FROM sys.[procedures] o WHERE o.type = N''P'' AND o.is_ms_shipped = 0"
  },
  {
    "case_id": 3,
    "action_name": "key_constraints",
    "objects_filter": "o.type IN (N''PK'', N''UQ'') AND o.is_ms_shipped = 0",
    "objects_projection": "SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published",
    "counterpart_query": "SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published FROM sys.[key_constraints] o WHERE o.type IN (N''PK'', N''UQ'') AND o.is_ms_shipped = 0"
  },
  {
    "case_id": 4,
    "action_name": "foreign_keys",
    "objects_filter": "o.type = N''F'' AND o.is_ms_shipped = 0",
    "objects_projection": "SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published",
    "counterpart_query": "SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published FROM sys.[foreign_keys] o WHERE o.type = N''F'' AND o.is_ms_shipped = 0"
  },
  {
    "case_id": 5,
    "action_name": "check_constraints",
    "objects_filter": "o.type = N''C'' AND o.is_ms_shipped = 0",
    "objects_projection": "SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published",
    "counterpart_query": "SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published FROM sys.[check_constraints] o WHERE o.type = N''C'' AND o.is_ms_shipped = 0"
  },
  {
    "case_id": 6,
    "action_name": "default_constraints",
    "objects_filter": "o.type = N''D'' AND o.parent_object_id <> 0 AND o.is_ms_shipped = 0",
    "objects_projection": "SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published",
    "counterpart_query": "SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\to.object_id, o.principal_id, o.schema_id, o.parent_object_id,\n\t\to.type, o.type_desc, o.create_date, o.modify_date,\n\t\to.is_ms_shipped, o.is_published, o.is_schema_published FROM sys.[default_constraints] o WHERE o.type = N''D'' AND o.parent_object_id <> 0 AND o.is_ms_shipped = 0"
  },
  {
    "case_id": 7,
    "action_name": "information_schema.tables",
    "objects_filter": "o.type IN (N''U'', N''V'')",
    "objects_projection": "DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name,\n\t\t\to.name AS object_name, CASE o.type WHEN N''U'' THEN N''BASE TABLE'' ELSE N''VIEW'' END AS table_type",
    "counterpart_query": "SELECT TABLE_CATALOG AS catalog_name, TABLE_SCHEMA AS schema_name,\n\t\t\tTABLE_NAME AS object_name, TABLE_TYPE AS table_type\n\t\t\tFROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE IN (N''BASE TABLE'', N''VIEW'')"
  },
  {
    "case_id": 8,
    "action_name": "information_schema.views",
    "objects_filter": "o.type = N''V''",
    "objects_projection": "DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name",
    "counterpart_query": "SELECT TABLE_CATALOG AS catalog_name, TABLE_SCHEMA AS schema_name,\n\t\t\tTABLE_NAME AS object_name FROM INFORMATION_SCHEMA.VIEWS"
  },
  {
    "case_id": 9,
    "action_name": "information_schema.routines",
    "objects_filter": "o.type IN (N''P'', N''FN'', N''IF'', N''TF'')",
    "objects_projection": "DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\t\tCASE o.type WHEN N''P'' THEN N''PROCEDURE'' ELSE N''FUNCTION'' END AS routine_type,\n\t\t\to.create_date, o.modify_date",
    "counterpart_query": "SELECT ROUTINE_CATALOG AS catalog_name, ROUTINE_SCHEMA AS schema_name,\n\t\t\tROUTINE_NAME AS object_name, ROUTINE_TYPE AS routine_type,\n\t\t\tCREATED AS create_date, LAST_ALTERED AS modify_date\n\t\t\tFROM INFORMATION_SCHEMA.ROUTINES\n\t\t\tWHERE ROUTINE_BODY = N''SQL'' AND ROUTINE_TYPE IN (N''PROCEDURE'', N''FUNCTION'')"
  },
  {
    "case_id": 10,
    "action_name": "information_schema.table_constraints",
    "objects_filter": "o.type IN (N''C'', N''F'', N''PK'', N''UQ'')",
    "objects_projection": "DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,\n\t\t\tDB_NAME() AS table_catalog_name, OBJECT_SCHEMA_NAME(o.parent_object_id) AS table_schema_name,\n\t\t\tOBJECT_NAME(o.parent_object_id) AS table_name,\n\t\t\tCASE o.type WHEN N''C'' THEN N''CHECK'' WHEN N''F'' THEN N''FOREIGN KEY''\n\t\t\t\tWHEN N''PK'' THEN N''PRIMARY KEY'' ELSE N''UNIQUE'' END AS constraint_type",
    "counterpart_query": "SELECT CONSTRAINT_CATALOG AS catalog_name, CONSTRAINT_SCHEMA AS schema_name,\n\t\t\tCONSTRAINT_NAME AS object_name, TABLE_CATALOG AS table_catalog_name,\n\t\t\tTABLE_SCHEMA AS table_schema_name, TABLE_NAME AS table_name, CONSTRAINT_TYPE AS constraint_type\n\t\t\tFROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS\n\t\t\tWHERE CONSTRAINT_TYPE IN (N''CHECK'', N''FOREIGN KEY'', N''PRIMARY KEY'', N''UNIQUE'')"
  },
  {
    "case_id": 11,
    "action_name": "information_schema.check_constraints",
    "objects_filter": "o.type = N''C''",
    "objects_projection": "DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name",
    "counterpart_query": "SELECT CONSTRAINT_CATALOG AS catalog_name, CONSTRAINT_SCHEMA AS schema_name, CONSTRAINT_NAME AS object_name\n\t\t\tFROM INFORMATION_SCHEMA.CHECK_CONSTRAINTS"
  },
  {
    "case_id": 12,
    "action_name": "information_schema.referential_constraints",
    "objects_filter": "o.type = N''F''",
    "objects_projection": "DB_NAME() AS catalog_name, SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name",
    "counterpart_query": "SELECT CONSTRAINT_CATALOG AS catalog_name, CONSTRAINT_SCHEMA AS schema_name, CONSTRAINT_NAME AS object_name\n\t\t\tFROM INFORMATION_SCHEMA.REFERENTIAL_CONSTRAINTS"
  }
]';

DECLARE @template nvarchar(max) = N'CREATE OR ALTER PROC [tests].{{procedure}}
AS
BEGIN
	SET NOCOUNT ON;
	PRINT N''Compare filtered sys.objects and catalog-view rows.'';
	PRINT N''Expect: equivalent columns match, including NULLs.'';

	DECLARE @expected nvarchar(max), @actual nvarchar(max);

	-- Arrange
	SET @expected = (
		SELECT {{projection}}
		FROM sys.objects o
		WHERE {{filter}}
		ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
			o.name COLLATE Latin1_General_100_BIN2
		FOR JSON PATH, INCLUDE_NULL_VALUES
	);

	-- Act
	SET @actual = (
		SELECT r.*
		FROM ({{counterpart}}) r
		ORDER BY r.schema_name COLLATE Latin1_General_100_BIN2,
			r.object_name COLLATE Latin1_General_100_BIN2
		FOR JSON PATH, INCLUDE_NULL_VALUES
	);

	-- Assert
	EXEC test.assert_equals
		N''sys.objects subset must match all equivalent {{label}} columns'',
		@expected, @actual;
END;';

DECLARE @case_id int = 1, @case_count int = (SELECT COUNT(*) FROM OPENJSON(@cases)),
    @action_name nvarchar(128), @procedure_name nvarchar(128),
    @filter nvarchar(max), @projection nvarchar(max), @counterpart nvarchar(max), @sql nvarchar(max);
	WHILE @case_id <= @case_count
	BEGIN
		SELECT @action_name = action_name, @filter = objects_filter, @projection = objects_projection,
			@counterpart = counterpart_query
		FROM OPENJSON(@cases)
        WITH (case_id int, action_name nvarchar(128), objects_filter nvarchar(max),
            objects_projection nvarchar(max), counterpart_query nvarchar(max))
        WHERE case_id = @case_id;
		SET @procedure_name = N'sys.objects@' + @action_name;
		SET @sql = REPLACE(@template, N'{{procedure}}', QUOTENAME(@procedure_name));
		SET @sql = REPLACE(@sql, N'{{filter}}', @filter);
		SET @sql = REPLACE(@sql, N'{{projection}}', @projection);
		SET @sql = REPLACE(@sql, N'{{counterpart}}', @counterpart);
		SET @sql = REPLACE(@sql, N'{{label}}',
			IIF(@action_name LIKE N'information_schema.%', @action_name, N'sys.' + @action_name));
		IF OBJECT_ID(N'[tests].' + QUOTENAME(@procedure_name), N'P') IS NOT NULL
            EXEC sys.sp_executesql @sql;
		SET @case_id += 1;
	END;
GO

-- Refresh only already-installed shipped STDEV tests.
DECLARE @references nvarchar(max) = N'[
  {
    "series_size": 0,
    "log_stdev": null,
    "sin_stdev": null
  },
  {
    "series_size": 1,
    "log_stdev": null,
    "sin_stdev": null
  },
  {
    "series_size": 2,
    "log_stdev": "0.49012907173427356E0",
    "sin_stdev": "0.047960537094532095E0"
  },
  {
    "series_size": 3,
    "log_stdev": "0.55554836702486265E0",
    "sin_stdev": "0.42528195815059372E0"
  },
  {
    "series_size": 10,
    "log_stdev": "0.73302386571524281E0",
    "sin_stdev": "0.73047057675776728E0"
  },
  {
    "series_size": 100,
    "log_stdev": "0.92805318513601598E0",
    "sin_stdev": "0.71257270260367911E0"
  },
  {
    "series_size": 1000,
    "log_stdev": "0.9854629932739295E0",
    "sin_stdev": "0.70759635532427667E0"
  },
  {
    "series_size": 10000,
    "log_stdev": "0.99753151513917659E0",
    "sin_stdev": "0.7071388163856821E0"
  },
  {
    "series_size": 100000,
    "log_stdev": "0.9996244804083867E0",
    "sin_stdev": "0.70711040212720566E0"
  }
]';

DECLARE @template nvarchar(max) = N'CREATE OR ALTER PROC [tests].{{procedure}}
AS
BEGIN
	SET NOCOUNT ON;
	PRINT N''Check STDEV for {{label}}, n={{size}}.'';
	PRINT N''Expect: NULL for n < 2; else reference within tolerance.'';

	DECLARE @actual float, @actual_count int, @actual_count_text nvarchar(12),
		@actual_bytes varbinary(max), @expected float, @tolerance float, @message nvarchar(2048);

	-- Arrange
	SET @expected = {{expected}};
	SET @tolerance = {{absolute}} + {{relative}} * COALESCE(ABS(@expected), 0);

	-- Act
	SELECT @actual_count = COUNT(*), @actual = STDEV({{expression}})
	FROM GENERATE_SERIES(1, {{size}}, 1) s;
	SET @actual_count_text = CONVERT(nvarchar(12), @actual_count);
	SET @actual_bytes = CONVERT(varbinary(max), @actual);

	-- Assert
	EXEC test.assert_equals
		N''GENERATE_SERIES must return {{size}} rows'', N''{{size}}'',
		@actual_count_text;
	SET @message = N''STDEV {{label}}, n={{size}} must match the reference'';
	IF @expected IS NULL
		EXEC test.assert_null @message, @actual_bytes;
	ELSE
		EXEC test.assert_float_equals
			@message, @expected, @actual, @tolerance;
END;';

DECLARE @absolute_tolerance float = 1.0E-12, @relative_tolerance float = 1.0E-10,
    @case_id int = 1, @case_count int = (SELECT COUNT(*) * 3 FROM OPENJSON(@references)),
    @series_size int, @transformation varchar(8), @procedure_name nvarchar(128),
    @expected float, @expression nvarchar(100), @sql nvarchar(max);
	WHILE @case_id <= @case_count
	BEGIN
		SELECT @series_size = series_size, @transformation = transformation,
			@procedure_name = procedure_name, @expected = expected_stdev
		FROM (
SELECT ROW_NUMBER() OVER (ORDER BY r.series_size, t.transformation) AS case_id,
	r.series_size, t.transformation,
	CONCAT('stdev@', t.transformation, '_', r.series_size) AS procedure_name,
	CASE t.transformation
		WHEN 'value' THEN
			CASE WHEN r.series_size < 2 THEN NULL
				ELSE SQRT(CONVERT(float, r.series_size) * (r.series_size + 1) / 12.0)
			END
		WHEN 'log' THEN r.log_stdev
		WHEN 'sin' THEN r.sin_stdev
	END AS expected_stdev
FROM OPENJSON(@references)
WITH (series_size int, log_stdev float, sin_stdev float) r
CROSS JOIN (VALUES ('value'), ('log'), ('sin')) t(transformation)
        ) cases WHERE case_id = @case_id;
		SET @expression = CASE @transformation
			WHEN 'value' THEN N'CONVERT(float, s.value)'
			WHEN 'log' THEN N'LOG(CONVERT(float, s.value))'
			WHEN 'sin' THEN N'SIN(CONVERT(float, s.value))'
		END;
		SET @sql = REPLACE(@template, N'{{procedure}}', QUOTENAME(@procedure_name));
		SET @sql = REPLACE(@sql, N'{{size}}', CONVERT(nvarchar(12), @series_size));
		SET @sql = REPLACE(@sql, N'{{expression}}', @expression);
		SET @sql = REPLACE(@sql, N'{{expected}}', COALESCE(CONVERT(nvarchar(32), @expected, 3), N'NULL'));
		SET @sql = REPLACE(@sql, N'{{absolute}}', CONVERT(nvarchar(32), @absolute_tolerance, 3));
		SET @sql = REPLACE(@sql, N'{{relative}}', CONVERT(nvarchar(32), @relative_tolerance, 3));
		SET @sql = REPLACE(@sql, N'{{label}}', @transformation);
		IF OBJECT_ID(N'[tests].' + QUOTENAME(@procedure_name), N'P') IS NOT NULL
            EXEC sys.sp_executesql @sql;
		SET @case_id += 1;
	END;
GO
GO

DECLARE @missing nvarchar(max);
SELECT @missing = STRING_AGG(CONVERT(nvarchar(max), name), N', ')
FROM (VALUES
	  (N'[test].[test]','V')
	, (N'[test].[test_vectors]','U')
	, (N'[test].[throw_error]','FN')
	, (N'[test].[assert_error]','P')
	, (N'[test].[fail_no_error]','P')
	, (N'[test].[fail]','FN')
	, (N'[test].[is_json_equal]','FN')
	, (N'[test].[format_message]','FN')
	, (N'[test].[assert_not_null]','P')
	, (N'[test].[assert_null]','P')
	, (N'[test].[is_equal]','FN')
	, (N'[test].[is_equals]','FN')
	, (N'[test].[is_float_equal]','FN')
	, (N'[test].[is_null]','FN')
	, (N'[test].[is_not_null]','FN')
	, (N'[test].[assert_equals]','P')
	, (N'[test].[assert_float_equals]','P')
	, (N'[test].[log]','P')
	, (N'[test].[throw]','P')
	, (N'[test].[run]','P')
	, (N'[test].[set_registration_scope]','P')
	, (N'[test].[vector]','P')
	, (N'[test].[dimension]','P')
	, (N'[test].[clear_registrations]','P')
	, (N'[test].[assert_resultset_equals]','P')
	, (N'[test].[get_query_schema]','P')
	, (N'[test].[assert_schema_signature]','P')
	, (N'[test].[assert_query_schemas_equal]','P')
	, (N'[tests].[test.format_message]','P')
	, (N'[tests].[test.test]','P')
	, (N'[tests].[test.test@name_convention]','P')
	, (N'[tests].[test.throw]','P')
	, (N'[tests].[test.assert_equals]','P')
	, (N'[tests].[test.assert_float_equals]','P')
	, (N'[tests].[test.assert_resultset_equals]','P')
	, (N'[tests].[test.assert_query_schemas_equal]','P')
	, (N'[tests].[test.assert_error]','P')
	, (N'[tests].[test.assert_not_null]','P')
	, (N'[tests].[test.assert_null]','P')
	, (N'[tests].[test.is_equal]','P')
	, (N'[tests].[sys.objects@tables]','P')
	, (N'[tests].[stdev@basic]','P')
	, (N'[tests].[data_types@basic]','P')
	, (N'[tests].[power@vectors]','P')
	, (N'[tests].[replicate@dimensions]','P')
) AS required(name, type)
WHERE OBJECT_ID(name, type) IS NULL;

IF @missing IS NOT NULL
BEGIN
	DECLARE @message nvarchar(2048) = N'Installation incomplete. Missing objects: ' + @missing;
	THROW 70000, @message, 1;
END;
GO

-- Clients may continue later GO batches after a preflight error.
IF @@TRANCOUNT > 0
BEGIN
	IF CAST(SERVERPROPERTY('EngineEdition') AS int) = 11
		RAISERROR(N'Run install.sql outside a transaction.', 16, 1);
	ELSE
		EXEC sys.sp_executesql N'SET XACT_ABORT OFF; RAISERROR(N''Run install.sql outside a transaction.'', 16, 1);';
	RETURN;
END;

DECLARE @basic_test_names nvarchar(max) =
	N'[tests].[test.test]|[tests].[test.test@name_convention]|'
	+ N'[tests].[test.format_message]|[tests].[test.throw]|'
	+ N'[tests].[test.assert_equals]|[tests].[test.assert_not_null]|[tests].[test.assert_null]|'
	+ N'[tests].[test.is_equal]|[tests].[sys.objects@tables]|[tests].[stdev@basic]|'
	+ N'[tests].[data_types@basic]|[tests].[test.assert_float_equals]|'
	+ N'[tests].[test.assert_resultset_equals]|[tests].[test.assert_query_schemas_equal]|[tests].[test.assert_error]|[tests].[power@vectors]|'
	+ N'[tests].[replicate@dimensions]';

PRINT N'Run basic tests (17 procedures, 25 cases with default global vectors)';
DECLARE @engine_edition int = CAST(SERVERPROPERTY('EngineEdition') AS int),
	@previous_vector_scope sql_variant, @saved_dimensions nvarchar(max),
	@created_dimension_store bit = 0, @dimension_fixture_ready bit = 0;
IF @engine_edition <> 11
	EXEC sys.sp_executesql N'SELECT @scope = SESSION_CONTEXT(N''ttest:vectors:scope'');',
		N'@scope sql_variant OUTPUT', @scope = @previous_vector_scope OUTPUT;
BEGIN TRY
	EXEC test.set_registration_scope N'global';
	IF OBJECT_ID(N'[test].[test_dimension_values]', N'U') IS NULL
	BEGIN
		CREATE TABLE [test].[test_dimension_values] (
			procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
			parameter_name varchar(512) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
			value varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
		);
		SET @created_dimension_store = 1;
	END;
	SELECT @saved_dimensions = CONCAT(N'[', STRING_AGG(CONVERT(nvarchar(max),
		JSON_OBJECT('parameter_name': CONVERT(nvarchar(max), parameter_name),
			'value': CONVERT(nvarchar(max), value))), N','), N']')
	FROM [test].[test_dimension_values]
	WHERE procedure_name = '[tests].[replicate@dimensions]';
	SET @dimension_fixture_ready = 1;
	DELETE FROM [test].[test_dimension_values] WHERE procedure_name = '[tests].[replicate@dimensions]';
	EXEC test.dimension N'[tests].[replicate@dimensions]', N'@number', N'[1,2]';
	EXEC test.dimension N'[tests].[replicate@dimensions]', N'@text', N'["a","bb","ccc"]';
	IF @engine_edition = 11
		EXEC test.run @test_names = @basic_test_names;
	ELSE
		EXEC sys.sp_executesql
			N'SET XACT_ABORT OFF; EXEC test.run @test_names = @names;',
			N'@names nvarchar(max)', @names = @basic_test_names;
	DELETE FROM [test].[test_dimension_values] WHERE procedure_name = '[tests].[replicate@dimensions]';
	INSERT [test].[test_dimension_values] (procedure_name, parameter_name, value)
	SELECT '[tests].[replicate@dimensions]', parameter_name, value
	FROM OPENJSON(@saved_dimensions) WITH (parameter_name nvarchar(512), value nvarchar(max));
	SET @dimension_fixture_ready = 0;
	IF @created_dimension_store = 1
	BEGIN
		DROP TABLE [test].[test_dimension_values];
		SET @created_dimension_store = 0;
	END;
	IF @engine_edition <> 11
		EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_vector_scope;
END TRY
BEGIN CATCH
	IF @@TRANCOUNT > 0 ROLLBACK;
	IF @dimension_fixture_ready = 1
	BEGIN
		DELETE FROM [test].[test_dimension_values] WHERE procedure_name = '[tests].[replicate@dimensions]';
		INSERT [test].[test_dimension_values] (procedure_name, parameter_name, value)
		SELECT '[tests].[replicate@dimensions]', parameter_name, value
		FROM OPENJSON(@saved_dimensions) WITH (parameter_name nvarchar(512), value nvarchar(max));
	END;
	IF @created_dimension_store = 1 DROP TABLE [test].[test_dimension_values];
	IF @engine_edition <> 11
		EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_vector_scope;
	THROW;
END CATCH;
PRINT N'Installation and tests complete.';
GO
