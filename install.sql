-- Existing framework objects are updated; existing user tests are retained.
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

CREATE OR ALTER view [test].[test]
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
where s.name = 'tests'
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
GO
GO

CREATE OR ALTER function [test].[fail_no_error]()
returns nvarchar(max)
as
begin
	return test.throw_error('<<No error>>')
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
GO

CREATE OR ALTER function test.assert_not_null
(@message nvarchar(max)
,@value varbinary(max)
)
returns nvarchar(max)
as
begin
	declare @return_value nvarchar(max)

	if @value is null
		set @return_value = test.fail(@message)
	else
		set @return_value = N''

	return @return_value
end
GO

CREATE OR ALTER function [test].[assert_null]
(@message nvarchar(max)
,@value varbinary(max)
)
returns nvarchar(max)
as
begin
	declare @return_value nvarchar(max)

	if @value is not null
		set @return_value = test.fail(@message)
	else
		set @return_value = N''

	return @return_value
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

CREATE OR ALTER FUNCTION [test].[assert_float_equals]
( @message nvarchar(max)
, @expected float
, @actual float
, @tolerance float
)
RETURNS nvarchar(max)
AS
BEGIN
	DECLARE @return_value nvarchar(max) = N'', @equal bit = 0;

	IF @tolerance IS NULL OR @tolerance < 0
		SET @return_value = test.fail(CONCAT(@message, CHAR(13), CHAR(10),
			N'Absolute tolerance must be non-negative and not NULL.'));
	ELSE
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

		IF @equal = 0
			SET @return_value = test.fail(CONCAT(@message, CHAR(13), CHAR(10),
				N'expected: ', COALESCE(N'<' + CONVERT(nvarchar(32), @expected, 3) + N'>', N'null'),
				CHAR(13), CHAR(10),
				N'but was : ', COALESCE(N'<' + CONVERT(nvarchar(32), @actual, 3) + N'>', N'null'),
				CHAR(13), CHAR(10),
				N'absolute tolerance: <', CONVERT(nvarchar(32), @tolerance, 3), N'>'));
	END;

	RETURN @return_value;
END;
GO

CREATE OR ALTER function [test].[assert_equals]
( @message nvarchar(max)
, @expected nvarchar(max)
, @actual nvarchar(max)
)
returns nvarchar(max)
as
begin
	declare @return_value nvarchar(max)

	if [test].[is_equal](@expected, @actual) = 1
		set @return_value = N''
	else
		set @return_value = test.fail(@message + char(13)+char(10)+
						'expected: ' + isnull('<'+@expected+'>', 'null') +
						char(13)+char(10)+
						'but was : ' + isnull('<'+@actual+'>', 'null'))

	return @return_value
end
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

CREATE OR ALTER FUNCTION [test].[assert_error]
( @message nvarchar(max)
, @expected_number int = NULL
, @expected_message_pattern nvarchar(max) = NULL
, @expected_state int = NULL
)
RETURNS int
AS
BEGIN
	DECLARE @actual_number int = ERROR_NUMBER(), @actual_message nvarchar(max) = ERROR_MESSAGE(),
		@actual_state int = ERROR_STATE(), @return_value int;

	IF @actual_number IS NULL OR @actual_message LIKE N'%<<No error>>%'
		SET @return_value = test.fail(CONCAT(@message, N'. Expected a caught error; none was caught.'));
	ELSE IF (@expected_number IS NOT NULL AND @actual_number IS DISTINCT FROM @expected_number)
		OR (@expected_message_pattern IS NOT NULL
			AND (@actual_message IS NULL OR @actual_message NOT LIKE @expected_message_pattern))
		OR (@expected_state IS NOT NULL AND @actual_state IS DISTINCT FROM @expected_state)
		SET @return_value = test.fail(CONCAT(@message,
			N'. Expected error number: ', COALESCE(CONVERT(nvarchar(12), @expected_number), N'<any>'),
			N'; message pattern: ', COALESCE(N'<' + @expected_message_pattern + N'>', N'<any>'),
			N'; state: ', COALESCE(CONVERT(nvarchar(12), @expected_state), N'<any>'),
			N'. Got error number: ', @actual_number,
			N'; message: <', @actual_message, N'>; state: ', @actual_state, N'.'));

	RETURN @return_value;
END;
GO

CREATE OR ALTER PROC [tests].[test.format_message]
AS
PRINT N'Check placeholders and explicit date/hex formatting.';
PRINT N'Expect: exact substitutions; ordinary text is unchanged.';
SET NOCOUNT ON;

-- Assert
IF test.format_message(NULL, 1, 2, 3, 4) IS NOT NULL
	THROW 51091, 'NULL format message changed.', 1;
IF CONVERT(varbinary(max), test.format_message(N'Hello %1', N'world', NULL, NULL, NULL))
	IS DISTINCT FROM CONVERT(varbinary(max), N'Hello world')
	THROW 51091, 'Text substitution failed.', 1;
IF CONVERT(varbinary(max), test.format_message(N'Hello at %2', NULL,
	CONVERT(nvarchar(33), CAST('2026-03-04T05:06:07.123456' AS datetime2(6)), 126), NULL, NULL))
	IS DISTINCT FROM CONVERT(varbinary(max), N'Hello at 2026-03-04T05:06:07.123456')
	THROW 51091, 'Explicit ISO date substitution failed.', 1;
IF CONVERT(varbinary(max), test.format_message(N'Hello binary: %1',
	CONVERT(nvarchar(4000), 0x010203, 1), NULL, NULL, NULL))
	IS DISTINCT FROM CONVERT(varbinary(max), N'Hello binary: 0x010203')
	THROW 51091, 'Explicit hexadecimal substitution failed.', 1;
IF CONVERT(varbinary(max), test.format_message(N'%1|%2', N'10/31/26', N'0xabcdef', DEFAULT, DEFAULT))
	IS DISTINCT FROM CONVERT(varbinary(max), N'10/31/26|0xabcdef')
	THROW 51091, 'Date-like or hexadecimal text changed.', 1;

EXEC test.log @message = N'Basic logger smoke: %1', @p1 = N'ok', @severity = 'debug';
GO

-- Refresh the existing coverage test for the explicit date/hex formatting contract.
IF OBJECT_ID(N'[tests].[test.format_message@fc_parameters]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER PROC [tests].[test.format_message@fc_parameters]
AS
PRINT N''Check placeholders, Unicode and explicit ISO/hex text.'';
PRINT N''Expect: exact text, NULLs and repeated placeholders.'';

DECLARE @actual nvarchar(max), @date datetime2(6), @date_text nvarchar(33), @hex nvarchar(4000),
	@raw_date sql_variant, @raw_binary sql_variant, @plain nvarchar(max);

-- Arrange
SET @date = CAST(''2026-03-04T05:06:07.123456'' AS datetime2(6));
SET @hex = CONVERT(nvarchar(4000), 0xAB, 1);
SET @date_text = CONVERT(nvarchar(33), @date, 126);

-- Act / Assert: each parameter arrangement has its own exact reference.
SET @actual = test.format_message(N''%1|%2|%3|%4'', @date_text, CONVERT(nvarchar(4000), 0x010203, 1), 42, NULL);
IF @actual IS DISTINCT FROM N''2026-03-04T05:06:07.123456|0x010203|42|<null>''
	THROW 51091, ''Explicit ISO/hex/numeric/NULL substitution failed.'', 1;
SET @actual = test.format_message(N''%1|%2|%3|%4'', NULL, 42, @hex, @date_text);
IF @actual IS DISTINCT FROM N''<null>|42|0xAB|2026-03-04T05:06:07.123456''
	THROW 51091, ''Formatting in alternate parameter positions failed.'', 1;
SET @actual = test.format_message(N''%1|%2|%3|%4'', 42, @date_text, NULL, @hex);
IF @actual IS DISTINCT FROM N''42|2026-03-04T05:06:07.123456|<null>|0xAB''
	THROW 51091, ''Second date/fourth binary parameter formatting failed.'', 1;
SET @actual = test.format_message(N''%1|%2|%3|%4'', @hex, NULL, @date_text, 42);
IF @actual IS DISTINCT FROM N''0xAB|<null>|2026-03-04T05:06:07.123456|42''
	THROW 51091, ''Third date/first binary parameter formatting failed.'', 1;
SET @actual = test.format_message(N''%1|%2|%3|%4'', DEFAULT, DEFAULT, DEFAULT, DEFAULT);
IF @actual IS DISTINCT FROM N''%1|%2|%3|%4'' THROW 51091, ''Unassigned placeholders changed.'', 1;
SET @actual = test.format_message(N''%1|%2'', N''10/31/26'', N''0xabcdef'', DEFAULT, DEFAULT);
IF @actual IS DISTINCT FROM N''10/31/26|0xabcdef'' THROW 51091, ''Text was reclassified as date/binary.'', 1;
SET @date = CAST(''2026-03-04T00:00:00'' AS datetime2(6));
SET @actual = test.format_message(N''%1'', CONVERT(nvarchar(33), @date, 126), DEFAULT, DEFAULT, DEFAULT);
IF @actual IS DISTINCT FROM N''2026-03-04T00:00:00'' THROW 51091, ''ISO midnight text changed.'', 1;
SET @actual = test.format_message(N''%1|%2'', CONVERT(nvarchar(4000), 0x, 1),
	CONVERT(nvarchar(33), CAST(NULL AS datetime2(6)), 126), DEFAULT, DEFAULT);
IF @actual IS DISTINCT FROM N''0x|<null>'' THROW 51091, ''Empty hex or NULL ISO substitution failed.'', 1;
-- Arrange
SET @raw_date = @date;
SET @raw_binary = 0x41004200;
SET @plain = CONCAT(CAST(@raw_date AS nvarchar(4000)), N''|'', CAST(@raw_binary AS nvarchar(4000)));
SET @actual = test.format_message(N''%1|%2'', @raw_date, @raw_binary, DEFAULT, DEFAULT);
IF CONVERT(varbinary(max), @actual) IS DISTINCT FROM CONVERT(varbinary(max), @plain)
	THROW 51091, ''Formatter still applies implicit date/binary formatting.'', 1;
SET @actual = test.format_message(NULL, 1, 2, 3, 4);
IF @actual IS NOT NULL THROW 51091, ''NULL message changed.'', 1;
SET @actual = test.format_message(N''%1:%1:100%'', NCHAR(381), DEFAULT, DEFAULT, DEFAULT);
IF @actual IS DISTINCT FROM NCHAR(381) + N'':'' + NCHAR(381) + N'':100%''
	THROW 51091, ''Unicode/repeated placeholder/percent formatting failed.'', 1;');
GO

-- Refresh only installed framework-owned equality coverage.
IF OBJECT_ID(N'[tests].[test.is_equal@fc_values]', N'P') IS NOT NULL
    EXEC(N'CREATE OR ALTER PROC [tests].[test.is_equal@fc_values]
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

-- Act / Assert: shortcuts must not evaluate JSON parsing.
SET @actual = test.is_equal(NULL, N'''');
IF @actual IS DISTINCT FROM 0 THROW 51091, ''Literal NULL/string comparison evaluated JSON parsing.'', 1;
SET @actual = test.is_equal(N''{bad JSON'', N''{bad JSON'');
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
    EXEC(N'CREATE OR ALTER PROC [tests].[test.is_json_equal@fc_json]
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
SET @right = JSON_OBJECT(''id'': 1, ''text'': @text + N''y'');
SET @equal = test.is_json_equal(@left, @right);
IF @equal IS DISTINCT FROM 0 THROW 51091, ''Long JSON values were truncated.'', 1;

-- Arrange
SET @unicode = NCHAR(0x0416) + NCHAR(0x4E2D)
	+ CONVERT(nvarchar(2), 0x3DD800DE);
SET @left = JSON_ARRAY(@unicode);
SET @right = N''["\u0416\u4e2d\ud83d\ude00"]'';
SET @equal = test.is_json_equal(@left, @right);
IF @equal IS DISTINCT FROM 1 THROW 51091, ''Raw and escaped Unicode differ.'', 1;
SET @left = JSON_ARRAY(NCHAR(8) + NCHAR(12) + NCHAR(10)
	+ NCHAR(13) + NCHAR(9) + N''/\"'');
SET @right = N''["\b\f\n\r\t\/\\\""]'';
SET @equal = test.is_json_equal(@left, @right);
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

declare @expected nvarchar(max), @actual nvarchar(max), @assertion_result nvarchar(max)

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
	set @assertion_result = test.assert_equals('Discovery must return both temporary procedures and their metadata'
		, @expected
		, @actual
		)

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

CREATE OR ALTER proc [test].[throw]
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

	set @message = replace(@message, '%', '%%');

	throw @err_num, @message, 1;
GO

CREATE OR ALTER proc [test].[set_scope]
  @scope nvarchar(max)
as

set nocount on

if @scope is null or not (
	(@scope collate Latin1_General_100_BIN2 = N'session' and datalength(@scope) = 14)
	or (@scope collate Latin1_General_100_BIN2 = N'global' and datalength(@scope) = 12))
	exec test.throw @message = N'Vector scope must be exactly session or global.';

declare @value nvarchar(7) = @scope
exec sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @value, @read_only = 0
GO

CREATE OR ALTER proc [test].[vector]
  @test_name nvarchar(max)
, @parameters nvarchar(max)
as

set nocount on

declare @scope nvarchar(4000) = convert(nvarchar(4000), session_context(N'ttest:vectors:scope'))
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
	from test.test
	where object_id(test_proc_full_name) = object_id(@test_name)

if @canonical_name is null
	exec test.throw @message = N'Vector test must be a schema-qualified discovered test in this database.';
if @parameters is null or trim(replace(replace(replace(@parameters,
	nchar(9), N' '), nchar(10), N' '), nchar(13), N' ')) = N''
	exec test.throw @message = N'Vector parameters cannot be NULL or blank.';

set @sql = N'INSERT ' + @table_name + N' (procedure_name, parameters) VALUES (@name, @parameters);'
exec sys.sp_executesql @sql, N'@name nvarchar(max), @parameters nvarchar(max)',
	@name = @canonical_name, @parameters = @parameters
GO

CREATE OR ALTER proc [test].[reset]
as

set nocount on

declare @scope nvarchar(4000) = convert(nvarchar(4000), session_context(N'ttest:vectors:scope'))
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

if @table_id is null return
set @sql = N'DELETE FROM ' + @table_name + N';'
exec sys.sp_executesql @sql
GO

CREATE OR ALTER proc [test].[run]
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
GO

CREATE OR ALTER PROC [tests].[test.throw]
AS
PRINT N'Check THROW, fail and missing-error sentinel helpers.';
PRINT N'Expect: 4 exceptions caught; NULL message stays NULL.';
SET NOCOUNT ON;

DECLARE @result nvarchar(max), @error_result int,
	@proc_id int = OBJECT_ID(N'[tests].[test.throw]');

-- Assert
SET @result = test.throw_error(NULL);
SET @result = test.assert_null(N'NULL error message stays NULL', CONVERT(varbinary(max), @result));

BEGIN TRY
	EXEC test.throw @message = N'Test exception!', @proc_id = @proc_id;
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Thrown exception metadata', 70000,
		N'Test exception!%<Procedure:> [[]tests].[[]test.throw]%', 1);
	IF @error_result IS NOT NULL THROW 51091, 'Matching error metadata must return NULL.', 1;

END CATCH;

BEGIN TRY
	SET @result = test.throw_error(N'basic raw error');
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Raw error must be raised', 245,
		N'%basic raw error%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.fail(N'basic explicit failure');
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Explicit failure must be raised', 245,
		N'%Unit-test fail: basic explicit failure%', DEFAULT);
END CATCH;

-- assert_error deliberately rejects the no-error sentinel.
BEGIN TRY
	SET @result = test.fail_no_error();
	THROW 51091, 'The no-error sentinel did not throw.', 1;
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE N'%<<No error>>%'
		THROW;
END CATCH;
GO

IF OBJECT_ID(N'[tests].[test.throw@fc_throwing]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER PROC [tests].[test.throw@fc_throwing]
AS
PRINT N''Throw 3 exceptions: no ID, valid ID, invalid ID.'';
PRINT N''Expect: all 3 caught; message and procedure ID verified.'';

DECLARE @id int, @caught bit, @i int, @message nvarchar(max), @scenario nvarchar(128);

-- Arrange
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
		SET @message = ERROR_MESSAGE();
		IF ERROR_NUMBER() = 70000 AND CHARINDEX(N''fc thrown exception'', @message) = 1
			AND ((@i = 0 AND @message = N''fc thrown exception'')
				OR (@i = 1 AND CHARINDEX(N''[tests].[test.throw@fc_throwing]'', @message) > 0)
				OR (@i = 2 AND CHARINDEX(N''<Procedure:> -1'', @message) > 0)) SET @caught = 1;
	END CATCH;

	-- Assert
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
	@assertion_result nvarchar(max);

-- Act
SELECT @four_samples = STDEV(CONVERT(float, n)) FROM (VALUES (1), (2), (3), (4)) v(n);
SELECT @one_sample = STDEV(CONVERT(float, n)) FROM (VALUES (1)) v(n);
SELECT @empty_set = STDEV(CONVERT(float, n)) FROM (VALUES (1)) v(n) WHERE n < 0;

-- Assert
SET @assertion_result = test.assert_float_equals(
	N'STDEV of 1,2,3,4 must match the reference within 1E-12',
	1.2909944487358056E0, @four_samples, 1E-12);
SET @assertion_result = test.assert_null(
	N'STDEV of one sample must be NULL', CONVERT(varbinary(max), @one_sample));
SET @assertion_result = test.assert_null(
	N'STDEV of an empty set must be NULL', CONVERT(varbinary(max), @empty_set));
GO

CREATE OR ALTER PROC [tests].[sys.objects@tables]
AS
PRINT N'Compare sys.objects user tables with sys.tables.';
PRINT N'Expect: all common columns match, including NULLs.';
SET NOCOUNT ON;

DECLARE @expected nvarchar(max), @actual nvarchar(max), @result nvarchar(max);

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
SET @result = test.assert_equals(N'sys.objects tables must match sys.tables', @expected, @actual);
GO

CREATE OR ALTER PROC [tests].[test.assert_equals]
AS
PRINT N'Check text, NULL, numeric, bit and date equality.';
PRINT N'Expect: equal values pass; text/float mismatches caught.';
SET NOCOUNT ON;

DECLARE @result nvarchar(max), @error_result int;

-- Assert
SET @result = test.assert_equals(N'Equal text', N'value', N'value');
SET @result = test.assert_equals(N'Equal NULLs', NULL, NULL);
SET @result = test.assert_equals(N'Equal integers', CAST(42 AS int), 6 * 7);
SET @result = test.assert_equals(N'Equal big integers',
	CAST(9007199254740993 AS bigint), CAST(9007199254740992 AS bigint) + 1);
SET @result = test.assert_equals(N'Equal decimals',
	CAST(123.125 AS decimal(18, 4)), CAST(123 + 0.125 AS decimal(18, 4)));
SET @result = test.assert_equals(N'Equal floats without tolerance',
	CONVERT(nvarchar(32), 1.25E0, 3), CONVERT(nvarchar(32), 0.5E0 + 0.75E0, 3));
SET @result = test.assert_equals(N'Equal bits', CAST(1 AS bit), CAST(1 AS bit));
SET @result = test.assert_equals(N'Equal dates',
	CAST('2026-03-04' AS date), DATEFROMPARTS(2026, 3, 4));
SET @result = test.assert_equals(N'Success returns empty text', N'', @result);

BEGIN TRY
	SET @result = test.assert_equals(N'basic equality mismatch', N'left', N'right');
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Mismatched values must fail', 245,
		N'%Unit-test fail: basic equality mismatch%expected: <left>%but was : <right>%',
		DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_equals(N'basic exact float mismatch',
		CONVERT(nvarchar(32), 1.25E0, 3), CONVERT(nvarchar(32), 1.2500000000000002E0, 3));
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Different floats must fail without tolerance', 245,
		N'%Unit-test fail: basic exact float mismatch%expected:%but was :%', DEFAULT);
END CATCH;
GO

CREATE OR ALTER PROC [tests].[test.assert_not_null]
AS
PRINT N'Check non-NULL bytes, empty bytes and NULL.';
PRINT N'Expect: both byte values pass; NULL failure is caught.';
SET NOCOUNT ON;

DECLARE @bytes_result nvarchar(max), @empty_result nvarchar(max),
	@assertion_result nvarchar(max), @error_result int;

-- Act
SET @bytes_result = test.assert_not_null(N'Non-NULL bytes', 0x01);
SET @empty_result = test.assert_not_null(N'Empty bytes are not NULL', 0x);

-- Assert
SET @assertion_result = test.assert_equals(N'Non-NULL bytes must pass', N'', @bytes_result);
SET @assertion_result = test.assert_equals(N'Empty bytes must pass', N'', @empty_result);

-- Act
BEGIN TRY
	SET @bytes_result = test.assert_not_null(N'basic NULL rejection', NULL);
	SET @bytes_result = test.fail_no_error();
END TRY
BEGIN CATCH
	-- Assert
	SET @error_result = test.assert_error(N'NULL must be rejected', 245,
		N'%Unit-test fail: basic NULL rejection%', DEFAULT);
	RAISERROR('[CAUGHT EXPECTED EXCEPTION] NULL rejected.', 0, 1) WITH NOWAIT;
END CATCH;
GO

CREATE OR ALTER PROC [tests].[test.assert_null]
AS
PRINT N'Check NULLs, empty scalar SELECTs and empty aggregates.';
PRINT N'Expect: NULLs pass; empty bytes and zero are rejected.';
SET NOCOUNT ON;

DECLARE @empty_value nvarchar(128), @empty_sum int, @empty_count int,
	@null_result nvarchar(max), @nullif_result nvarchar(max),
	@query_result nvarchar(max), @sum_result nvarchar(max),
	@assertion_result nvarchar(max), @error_result int;

-- Arrange
SET @empty_value = (SELECT name FROM sys.tables WHERE 1 = 0);
SELECT @empty_sum = SUM(v.value), @empty_count = COUNT(*)
FROM (VALUES (1)) v(value)
WHERE 1 = 0;

-- Act
SET @null_result = test.assert_null(N'Literal NULL', NULL);
SET @nullif_result = test.assert_null(N'NULLIF returns NULL', CONVERT(varbinary(max), NULLIF(1, 1)));
SET @query_result = test.assert_null(N'Empty scalar SELECT returns NULL', CONVERT(varbinary(max), @empty_value));
SET @sum_result = test.assert_null(N'SUM of an empty set is NULL', CONVERT(varbinary(max), @empty_sum));

-- Assert
SET @assertion_result = test.assert_equals(N'Literal NULL must pass', N'', @null_result);
SET @assertion_result = test.assert_equals(N'NULLIF result must pass', N'', @nullif_result);
SET @assertion_result = test.assert_equals(N'Empty scalar SELECT must pass', N'', @query_result);
SET @assertion_result = test.assert_equals(N'Empty SUM must pass', N'', @sum_result);

BEGIN TRY
	SET @assertion_result = test.assert_null(N'basic non-NULL rejection', 0x);
	SET @assertion_result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Empty bytes are not NULL', 245,
		N'%Unit-test fail: basic non-NULL rejection%', DEFAULT);
	RAISERROR('[CAUGHT EXPECTED EXCEPTION] non-NULL bytes rejected.', 0, 1) WITH NOWAIT;
END CATCH;

BEGIN TRY
	SET @assertion_result = test.assert_null(N'COUNT of an empty set is zero', CONVERT(varbinary(max), @empty_count));
	SET @assertion_result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Zero is not NULL', 245,
		N'%Unit-test fail: COUNT of an empty set is zero%', DEFAULT);
	RAISERROR('[CAUGHT EXPECTED EXCEPTION] zero rejected.', 0, 1) WITH NOWAIT;
END CATCH;
GO

CREATE OR ALTER PROC [tests].[test.is_equal]
AS
PRINT N'Check scalar equality and shallow ordered JSON.';
PRINT N'Expect: column order ignored; rows/types stay exact.';
SET NOCOUNT ON;

-- Assert
IF test.is_equal(NULL, NULL) IS DISTINCT FROM 1
	THROW 51091, 'NULL equality failed.', 1;
IF test.is_equal(NULL, N'') IS DISTINCT FROM 0
	THROW 51091, 'NULL versus text failed.', 1;
IF test.is_equal(N'value', N'value') IS DISTINCT FROM 1
	THROW 51091, 'Literal equality failed.', 1;
IF test.is_equal(N'left', N'right') IS DISTINCT FROM 0
	THROW 51091, 'Different text failed.', 1;
IF test.is_equal(N'001.50', N'1.5') IS DISTINCT FROM 1
	THROW 51091, 'Scalar numeric shortcut failed.', 1;
IF test.is_equal(N'[{"id":1,"v":"a"}]', N'[{"v":"a","id":1}]') IS DISTINCT FROM 1
	THROW 51091, 'Column order failed.', 1;
IF test.is_equal(N'[{"id":1},{"id":2}]', N'[{"id":2},{"id":1}]') IS DISTINCT FROM 0
	THROW 51091, 'Row order failed.', 1;
IF test.is_equal(N'[1]', N'[1.0]') IS DISTINCT FROM 0
	THROW 51091, 'Numeric spelling failed.', 1;
IF test.is_equal(N'[1]', N'["1"]') IS DISTINCT FROM 0
	THROW 51091, 'JSON types failed.', 1;
IF test.is_equal(N'[{"id":null}]', N'[{}]') IS DISTINCT FROM 0
	THROW 51091, 'NULL versus absent property failed.', 1;

IF test.is_json_equal(N'[{"id":1,"v":"a"}]', N'[{"v":"a","id":1}]') IS DISTINCT FROM 1
	THROW 51091, 'Direct JSON column order failed.', 1;
IF test.is_json_equal(N'[{"id":1},{"id":2}]', N'[{"id":2},{"id":1}]') IS DISTINCT FROM 0
	THROW 51091, 'Direct JSON row order failed.', 1;
IF test.is_json_equal(N'[1]', N'[1.0]') IS DISTINCT FROM 0
	THROW 51091, 'Direct JSON numeric spelling failed.', 1;
IF test.is_json_equal(N'[1]', N'["1"]') IS DISTINCT FROM 0
	THROW 51091, 'Direct JSON types failed.', 1;
IF test.is_json_equal(N'[{"id":null}]', N'[{}]') IS DISTINCT FROM 0
	THROW 51091, 'Direct JSON NULL versus absent failed.', 1;
GO

CREATE OR ALTER PROC [tests].[data_types@basic]
AS
PRINT N'Compare one row of numeric, text, date and spatial types.';
PRINT N'Expect: equal values; spatial WKT and SRID match.';
SET NOCOUNT ON;

DECLARE @expected nvarchar(max), @actual nvarchar(max), @result nvarchar(max),
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
SET @result = test.assert_equals(N'Inline rows must match across supported scalar types', @expected, @actual);
GO

CREATE OR ALTER PROC [tests].[test.assert_float_equals]
AS
PRINT N'Check FLOAT equality, tolerance, NULLs and extreme values.';
PRINT N'Expect: valid pairs pass; invalid comparisons are caught.';
SET NOCOUNT ON;

DECLARE @result nvarchar(max), @error_result int;

-- Assert
SET @result = test.assert_float_equals(N'Exact, zero tolerance', 1.25, 1.25, 0);
SET @result = test.assert_float_equals(N'Within tolerance', 1, 1.0625, 0.125);
SET @result = test.assert_float_equals(N'Inclusive boundary', 1, 1.125, 0.125);
SET @result = test.assert_float_equals(N'Negative values', -1, -1.125, 0.125);
SET @result = test.assert_float_equals(N'Both NULL', NULL, NULL, 0);
SET @result = test.assert_float_equals(N'Opposite signs at boundary', 1, -1, 2);
SET @result = test.assert_float_equals(N'Large opposite signs within tolerance', 1E308, -7E307, 1.79E308);
SET @result = test.assert_float_equals(N'Large equal values', 1.7E308, 1.7E308, 0);
SET @result = test.assert_float_equals(N'Large same-sign values within tolerance', 1.7E308, 1.6E308, 2E307);

BEGIN TRY
	SET @result = test.assert_float_equals(N'Outside tolerance', 1, 1.25, 0.125);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Outside tolerance must fail', 245,
		N'%Unit-test fail: Outside tolerance%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'Unequal, zero tolerance', 1, 1.125, 0);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Zero tolerance requires equality', 245,
		N'%Unit-test fail: Unequal, zero tolerance%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'NULL expected', NULL, 1, 0.125);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'NULL expected must fail', 245,
		N'%Unit-test fail: NULL expected%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'NULL actual', 1, NULL, 0.125);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'NULL actual must fail', 245,
		N'%Unit-test fail: NULL actual%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'Negative tolerance', 1, 1, -1);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Negative tolerance must fail', 245,
		N'%Unit-test fail: Negative tolerance%Absolute tolerance must be non-negative and not NULL.%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'NULL tolerance', 1, 1, NULL);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'NULL tolerance must fail', 245,
		N'%Unit-test fail: NULL tolerance%Absolute tolerance must be non-negative and not NULL.%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'NULL pair, invalid tolerance', NULL, NULL, -1);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'NULL pair must not hide an invalid tolerance', 245,
		N'%Unit-test fail: NULL pair, invalid tolerance%Absolute tolerance must be non-negative and not NULL.%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'Opposite signs outside tolerance', 1, -1, 1.5);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Opposite signs outside tolerance must fail', 245,
		N'%Unit-test fail: Opposite signs outside tolerance%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'Opposite signs near zero', 1, -1E-300, 1);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Opposite signs near zero must differ', 245,
		N'%Unit-test fail: Opposite signs near zero%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'Opposite signs near zero reversed', -1E-300, 1, 1);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Reversed opposite signs near zero must differ', 245,
		N'%Unit-test fail: Opposite signs near zero reversed%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'Difference would overflow', 1E308, -1E308, 1.79E308);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Overflowing difference must fail as an assertion', 245,
		N'%Unit-test fail: Difference would overflow%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'Large same-sign values outside tolerance', 1.7E308, 1E308, 1E307);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Large same-sign values outside tolerance must fail', 245,
		N'%Unit-test fail: Large same-sign values outside tolerance%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;

BEGIN TRY
	SET @result = test.assert_float_equals(N'Tiny unequal values', 1E-300, 2E-300, 0);
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	SET @error_result = test.assert_error(N'Tiny unequal values must fail with zero tolerance', 245,
		N'%Unit-test fail: Tiny unequal values%expected:%but was :%absolute tolerance:%', DEFAULT);
END CATCH;
GO

CREATE OR ALTER PROC [test].[assert_resultset_equals]
	@message nvarchar(max),
	@expected_query nvarchar(max),
	@actual_query nvarchar(max)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @expected nvarchar(max), @actual nvarchar(max), @sql nvarchar(max),
		@result nvarchar(max), @whitespace nvarchar(4) = N' ' + NCHAR(9) + NCHAR(10) + NCHAR(13);

	SET @expected_query = TRIM(@whitespace FROM @expected_query);
	SET @actual_query = TRIM(@whitespace FROM @actual_query);
	IF RIGHT(@expected_query, 1) = N';'
		SET @expected_query = TRIM(@whitespace FROM LEFT(@expected_query, LEN(@expected_query) - 1));
	IF RIGHT(@actual_query, 1) = N';'
		SET @actual_query = TRIM(@whitespace FROM LEFT(@actual_query, LEN(@actual_query) - 1));

	IF @expected_query IS NULL OR @expected_query = N''
	BEGIN
		SET @result = test.fail(CONCAT(@message, N': expected query must not be NULL or empty.'));
		RETURN;
	END;
	IF @actual_query IS NULL OR @actual_query = N''
	BEGIN
		SET @result = test.fail(CONCAT(@message, N': actual query must not be NULL or empty.'));
		RETURN;
	END;

	SET @sql = N'SET @json = (' + NCHAR(10) + @expected_query
		+ NCHAR(10) + N'FOR JSON PATH, INCLUDE_NULL_VALUES);';
	EXEC sys.sp_executesql @sql, N'@json nvarchar(max) OUTPUT', @json = @expected OUTPUT;

	SET @sql = N'SET @json = (' + NCHAR(10) + @actual_query
		+ NCHAR(10) + N'FOR JSON PATH, INCLUDE_NULL_VALUES);';
	EXEC sys.sp_executesql @sql, N'@json nvarchar(max) OUTPUT', @json = @actual OUTPUT;

	SET @result = test.assert_equals(@message, @expected, @actual);
END;
GO

CREATE OR ALTER PROC [tests].[test.assert_resultset_equals]
AS
PRINT N'Compare sys.objects user tables with sys.tables.';
PRINT N'Expect: all common columns match, including NULLs.';
SET NOCOUNT ON;

-- Assert
EXEC test.assert_resultset_equals
	@message = N'sys.objects tables must match sys.tables',
	@expected_query = N'
		SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
			o.object_id, o.principal_id, o.schema_id, o.parent_object_id,
			o.type, o.type_desc, o.create_date, o.modify_date,
			o.is_ms_shipped, o.is_published, o.is_schema_published
		FROM sys.objects o
		WHERE o.type = N''U'' AND o.is_ms_shipped = 0
		ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
			o.name COLLATE Latin1_General_100_BIN2',
	@actual_query = N'
		SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
			o.object_id, o.principal_id, o.schema_id, o.parent_object_id,
			o.type, o.type_desc, o.create_date, o.modify_date,
			o.is_ms_shipped, o.is_published, o.is_schema_published
		FROM sys.tables o
		WHERE o.is_ms_shipped = 0
		ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
			o.name COLLATE Latin1_General_100_BIN2';
GO

CREATE OR ALTER PROC [tests].[test.assert_error]
AS
PRINT N'Check caught error number, LIKE message and state.';
PRINT N'Expect: NULL/DEFAULT skip filters, but require an error.';
SET NOCOUNT ON;

DECLARE @result int, @sentinel nvarchar(max);

-- Assert
BEGIN TRY
	SET @result = test.assert_error(N'No active CATCH', DEFAULT, DEFAULT, DEFAULT);
	THROW 51091, 'An assertion outside CATCH must fail.', 1;
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
		N'%Unit-test fail: No active CATCH%Expected a caught error; none was caught.%'
		THROW;
END CATCH;

BEGIN TRY
	THROW 51024, N'assert_error reference_[x]', 17;
END TRY
BEGIN CATCH
	IF test.assert_error(N'Any caught error', NULL, NULL, NULL) IS NOT NULL
		THROW 51091, 'Any caught error must return NULL.', 1;
	IF test.assert_error(N'Number only', 51024, NULL, NULL) IS NOT NULL
		THROW 51091, 'Number-only filters must return NULL.', 1;
	IF test.assert_error(N'Message only', NULL, N'%reference%', NULL) IS NOT NULL
		THROW 51091, 'Message-only filters must return NULL.', 1;
	IF test.assert_error(N'State only', NULL, NULL, 17) IS NOT NULL
		THROW 51091, 'State-only filters must return NULL.', 1;
	IF test.assert_error(N'Number and message', 51024, N'assert%', NULL) IS NOT NULL
		THROW 51091, 'Number and message must return NULL.', 1;
	IF test.assert_error(N'Number and state', 51024, NULL, 17) IS NOT NULL
		THROW 51091, 'Number and state must return NULL.', 1;
	IF test.assert_error(N'Message and state', NULL, N'%[[]x]', 17) IS NOT NULL
		THROW 51091, 'Message and state must return NULL.', 1;
	IF test.assert_error(N'All fields', 51024, N'%reference[_][[]x]', 17) IS NOT NULL
		THROW 51091, 'All matching filters must return NULL.', 1;
	IF test.assert_error(N'Prefix pattern', NULL, N'assert_error reference%', NULL) IS NOT NULL
		THROW 51091, 'A matching prefix must return NULL.', 1;
	IF test.assert_error(N'Single-character wildcard', NULL, N'%referenc_%', NULL) IS NOT NULL
		THROW 51091, 'A matching wildcard must return NULL.', 1;
	IF test.assert_error(N'Character class', NULL, N'%referenc[e]%', NULL) IS NOT NULL
		THROW 51091, 'A matching character class must return NULL.', 1;
	IF test.assert_error(N'Escaped literal wildcards', NULL, N'assert[_]error reference[_][[]x]', NULL) IS NOT NULL
		THROW 51091, 'Escaped literal wildcards must return NULL.', 1;
	IF test.assert_error(N'DEFAULT filters', DEFAULT, DEFAULT, DEFAULT) IS NOT NULL
		THROW 51091, 'DEFAULT filters must return NULL.', 1;
	IF test.assert_error(N'Message-only DEFAULT filters', DEFAULT, N'%reference%', DEFAULT) IS NOT NULL
		THROW 51091, 'Message-only DEFAULT filters must return NULL.', 1;

	BEGIN TRY
		SET @result = test.assert_error(N'Wrong number', 51025, NULL, NULL);
		THROW 51091, 'A wrong number was accepted.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong number%Got error number: 51024%'
			THROW;
	END CATCH;

	BEGIN TRY
		SET @result = test.assert_error(N'Wrong message', NULL, N'different message', NULL);
		THROW 51091, 'A wrong message was accepted.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong message%Got error number: 51024%'
			THROW;
	END CATCH;

	BEGIN TRY
		SET @result = test.assert_error(N'Wrong state', NULL, NULL, 18);
		THROW 51091, 'A wrong state was accepted.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong state%Got error number: 51024%'
			THROW;
	END CATCH;

	BEGIN TRY
		SET @result = test.assert_error(N'Matching number, wrong message', 51024, N'different message', NULL);
		THROW 51091, 'A wrong message with a matching number was accepted.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Matching number, wrong message%Got error number: 51024%'
			THROW;
	END CATCH;

	BEGIN TRY
		SET @result = test.assert_error(N'Wrong number, matching message', 51025, N'%reference%', NULL);
		THROW 51091, 'A wrong number with a matching message was accepted.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong number, matching message%Got error number: 51024%'
			THROW;
	END CATCH;

	BEGIN TRY
		SET @result = test.assert_error(N'Wrong state, matching message', 51024, N'%reference%', 18);
		THROW 51091, 'A wrong state with matching number/message was accepted.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Wrong state, matching message%Got error number: 51024%'
			THROW;
	END CATCH;

	BEGIN TRY
		SET @result = test.assert_error(N'Nonmatching fragment', NULL, N'%missing%', NULL);
		THROW 51091, 'A nonmatching fragment was accepted.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Nonmatching fragment%Got error number: 51024%'
			THROW;
	END CATCH;

	BEGIN TRY
		SET @result = test.assert_error(N'Empty message is not omitted', NULL, N'', NULL);
		THROW 51091, 'An empty message filter was ignored.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Empty message is not omitted%Got error number: 51024%'
			THROW;
	END CATCH;

	BEGIN TRY
		SET @result = test.assert_error(N'Zero is not an omitted state', NULL, NULL, 0);
		THROW 51091, 'A zero state filter was ignored.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Zero is not an omitted state%Got error number: 51024%'
			THROW;
	END CATCH;

	BEGIN TRY
		SET @result = test.assert_error(N'Zero is not an omitted number', 0, NULL, NULL);
		THROW 51091, 'A zero number filter was ignored.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Zero is not an omitted number%Got error number: 51024%'
			THROW;
	END CATCH;
END CATCH;

BEGIN TRY
	SET @sentinel = test.fail_no_error();
	THROW 51091, 'The no-error sentinel did not throw.', 1;
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE N'%<<No error>>%'
		THROW;

	BEGIN TRY
		SET @result = test.assert_error(N'Sentinel is not a caught application error', 245, DEFAULT, DEFAULT);
		THROW 51091, 'The no-error sentinel was accepted.', 1;
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() IS DISTINCT FROM 245 OR ERROR_MESSAGE() NOT LIKE
			N'%Unit-test fail: Sentinel is not a caught application error%Expected a caught error; none was caught.%'
			THROW;
	END CATCH;
END CATCH;
GO

-- Migrate framework-owned sentinel tests before retiring legacy names.
IF OBJECT_ID(N'[tests].[test.throw_error@fc_error_helpers]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER PROC [tests].[test.throw_error@fc_error_helpers]
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
	SET @caught = 0;
	BEGIN TRY
		IF @i = 0 SET @result = test.throw_error(N''fc raw error'');
		ELSE IF @i = 1 SET @result = test.fail(N''fc explicit fail'');
		ELSE SET @result = test.fail_no_error();
	END TRY
	BEGIN CATCH
		SET @message = ERROR_MESSAGE();
		IF ERROR_NUMBER() = 245 AND (
			(@i = 0 AND CHARINDEX(N''fc raw error'', @message) > 0) OR
			(@i = 1 AND CHARINDEX(N''Unit-test fail: fc explicit fail'', @message) > 0) OR
			(@i = 2 AND CHARINDEX(N''<<No error>>'', @message) > 0)) SET @caught = 1;
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
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''Error: '', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;

	-- Assert
	IF @caught = 0 THROW 51091, ''A numeric or empty raw error message did not throw.'', 1;
	SET @i += 1;
END;');
GO

IF OBJECT_ID(N'[tests].[test.error@fc_no_error]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.fail_no_error@fc_no_error]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER PROC [tests].[test.fail_no_error@fc_no_error]
AS
PRINT N''Call fail_no_error() after an expected error is missing.'';
PRINT N''Expect: its no-error marker is raised and caught.'';

DECLARE @result nvarchar(max), @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	SET @result = test.fail_no_error();
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() = 245 AND CHARINDEX(N''<<No error>>'', ERROR_MESSAGE()) > 0 SET @caught = 1;
END CATCH;

-- Assert
IF @caught = 0 THROW 51091, ''fail_no_error() did not raise its no-error marker.'', 1;');
GO

IF OBJECT_ID(N'[tests].[test.assert_error_like@fc_patterns]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.assert_error@fc_patterns]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_error@fc_patterns]
AS
PRINT N''Check error LIKE patterns and the no-error marker.'';
PRINT N''Expect: matching passes; the invalid match is caught.'';

DECLARE @result int, @marker nvarchar(max), @caught bit;

-- Arrange
SET @caught = 0;

-- Act
BEGIN TRY
	THROW 51011, ''fc wildcard_value'', 1;
END TRY
BEGIN CATCH
	SET @result = test.assert_error(N''literal underscore and wildcard'', DEFAULT, N''fc wildcard[_]%'', DEFAULT);
	IF @result IS NOT NULL THROW 51091, ''A matching LIKE pattern returned a value.'', 1;
END CATCH;
BEGIN TRY
	SET @marker = test.fail_no_error();
END TRY
BEGIN CATCH
	BEGIN TRY
		SET @result = test.assert_error(N''fc no-error marker must be rejected'', DEFAULT, N''%<<No error>>%'', DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc no-error marker must be rejected'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;
END CATCH;

-- Assert
IF @caught = 0 THROW 51091, ''assert_error accepted the no-error marker.'', 1;');
GO

IF OBJECT_ID(N'[tests].[test.assert_error_number@fc_error_assertions]', N'P') IS NOT NULL
	OR OBJECT_ID(N'[tests].[test.assert_error@fc_error_assertions]', N'P') IS NOT NULL
	EXEC(N'CREATE OR ALTER PROC [tests].[test.assert_error@fc_error_assertions]
AS
PRINT N''Check matching/mismatching error numbers and patterns.'';
PRINT N''Expect: matches pass; invalid checks throw and are caught.'';

DECLARE @result int, @caught bit, @value int, @i int;

-- Arrange
SET @caught = 0;

-- Act: a real conversion error must still be accepted.
BEGIN TRY
	SET @value = CONVERT(int, N''fc genuine conversion error'');
END TRY
BEGIN CATCH
	IF ERROR_NUMBER() <> 245 THROW;
	SET @result = test.assert_error(N''genuine conversion error'', 245, DEFAULT, DEFAULT);
	SET @caught = 1;
END CATCH;

-- Assert.
IF @caught = 0 OR @result IS NOT NULL
	THROW 51091, ''A genuine conversion error was not accepted.'', 1;
SET @caught = 0;
BEGIN TRY
	THROW 51011, ''fc expected exception'', 1;
END TRY
BEGIN CATCH
	SET @result = test.assert_error(N''matching number'', 51011, DEFAULT, DEFAULT);
	IF @result IS NOT NULL THROW 51091, ''Matching error number returned a value.'', 1;
	SET @result = test.assert_error(N''matching pattern'', DEFAULT, N''%fc expected exception%'', DEFAULT);
	IF @result IS NOT NULL THROW 51091, ''Matching error pattern returned a value.'', 1;
	BEGIN TRY
		SET @result = test.assert_error(N''fc wrong number'', 51012, DEFAULT, DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc wrong number'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;
	IF @caught = 0 THROW 51091, ''Wrong error number was accepted.'', 1;
	SET @caught = 0;
	BEGIN TRY
		SET @result = test.assert_error(N''fc wrong pattern'', DEFAULT, N''%not the actual message%'', DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc wrong pattern'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;
	IF @caught = 0 THROW 51091, ''Wrong error pattern was accepted.'', 1;
END CATCH;
-- Act: the no-error sentinel must NOT satisfy expected error 245.
SET @caught = 0;
BEGIN TRY
	SET @value = test.fail_no_error();
END TRY
BEGIN CATCH
	BEGIN TRY
		SET @result = test.assert_error(N''fc sentinel is not a real conversion error'', 245, DEFAULT, DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(
			N''Unit-test fail: fc sentinel is not a real conversion error'', ERROR_MESSAGE()) > 0
			SET @caught = 1;
	END CATCH;
END CATCH;

-- Assert.
IF @caught = 0 THROW 51091, ''Error number assertion accepted the no-error sentinel.'', 1;
-- Arrange
SET @i = 0;
WHILE @i < 2
BEGIN
	SET @caught = 0;
	BEGIN TRY
		IF @i = 0 SET @result = test.assert_error(N''fc no active error'', 51011, DEFAULT, DEFAULT);
		ELSE SET @result = test.assert_error(N''fc no active error'', DEFAULT, N''%anything%'', DEFAULT);
	END TRY
	BEGIN CATCH
		IF ERROR_NUMBER() = 245 AND CHARINDEX(N''fc no active error'', ERROR_MESSAGE()) > 0 SET @caught = 1;
	END CATCH;
	IF @caught = 0 THROW 51091, ''An error assertion passed outside CATCH.'', 1;
	SET @i += 1;
END;');
GO

IF OBJECT_ID(N'[tests].[test.fail_no_error@fc_no_error]', N'P') IS NOT NULL
	DROP PROCEDURE IF EXISTS [tests].[test.error@fc_no_error];
IF OBJECT_ID(N'[test].[fail_no_error]', N'FN') IS NOT NULL
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
IF OBJECT_ID(N'[test].[assert_error]', N'FN') IS NOT NULL
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
	DECLARE @actual int = POWER(@base, @exponent);
	DECLARE @result nvarchar(max) = test.assert_equals(N'POWER(base,exponent)', @expected, @actual);
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

DECLARE @missing nvarchar(max);
SELECT @missing = STRING_AGG(CONVERT(nvarchar(max), name), N', ')
FROM (VALUES
	  (N'[test].[test]','V')
	, (N'[test].[test_vectors]','U')
	, (N'[test].[throw_error]','FN')
	, (N'[test].[assert_error]','FN')
	, (N'[test].[fail_no_error]','FN')
	, (N'[test].[fail]','FN')
	, (N'[test].[is_json_equal]','FN')
	, (N'[test].[format_message]','FN')
	, (N'[test].[assert_not_null]','FN')
	, (N'[test].[assert_null]','FN')
	, (N'[test].[is_equal]','FN')
	, (N'[test].[assert_equals]','FN')
	, (N'[test].[assert_float_equals]','FN')
	, (N'[test].[log]','P')
	, (N'[test].[throw]','P')
	, (N'[test].[run]','P')
	, (N'[test].[set_scope]','P')
	, (N'[test].[vector]','P')
	, (N'[test].[reset]','P')
	, (N'[test].[assert_resultset_equals]','P')
	, (N'[tests].[test.format_message]','P')
	, (N'[tests].[test.test]','P')
	, (N'[tests].[test.test@name_convention]','P')
	, (N'[tests].[test.throw]','P')
	, (N'[tests].[test.assert_equals]','P')
	, (N'[tests].[test.assert_float_equals]','P')
	, (N'[tests].[test.assert_resultset_equals]','P')
	, (N'[tests].[test.assert_error]','P')
	, (N'[tests].[test.assert_not_null]','P')
	, (N'[tests].[test.assert_null]','P')
	, (N'[tests].[test.is_equal]','P')
	, (N'[tests].[sys.objects@tables]','P')
	, (N'[tests].[stdev@basic]','P')
	, (N'[tests].[data_types@basic]','P')
	, (N'[tests].[power@vectors]','P')
) AS required(name, type)
WHERE OBJECT_ID(name, type) IS NULL;

IF @missing IS NOT NULL
BEGIN
	DECLARE @message nvarchar(2048) = N'Installation incomplete. Missing objects: ' + @missing;
	THROW 70000, @message, 1;
END;

DECLARE @basic_test_names nvarchar(max) =
	N'[tests].[test.test]|[tests].[test.test@name_convention]|'
	+ N'[tests].[test.format_message]|[tests].[test.throw]|'
	+ N'[tests].[test.assert_equals]|[tests].[test.assert_not_null]|[tests].[test.assert_null]|'
	+ N'[tests].[test.is_equal]|[tests].[sys.objects@tables]|[tests].[stdev@basic]|'
	+ N'[tests].[data_types@basic]|[tests].[test.assert_float_equals]|'
	+ N'[tests].[test.assert_resultset_equals]|[tests].[test.assert_error]|[tests].[power@vectors]';

PRINT N'Run basic tests (15 procedures, 18 cases)';
IF OBJECT_ID(N'tempdb..#test_vectors') IS NOT NULL
	THROW 70000, 'Installation verification requires a connection without #test_vectors.', 1;
DECLARE @previous_vector_scope sql_variant = SESSION_CONTEXT(N'ttest:vectors:scope');
BEGIN TRY
	CREATE TABLE #test_vectors (
		procedure_name varchar(2048) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL,
		parameters varchar(max) COLLATE Latin1_General_100_BIN2_UTF8 NOT NULL
	);
	EXEC test.set_scope N'session';
	EXEC test.vector N'[tests].[power@vectors]', N'2,3,8';
	EXEC test.vector N'[tests].[power@vectors]', N'3,2,9';
	EXEC test.vector N'[tests].[power@vectors]', N'5,0,1';
	EXEC test.vector N'[tests].[power@vectors]', N'-2,3,-8';
	IF CAST(SERVERPROPERTY('EngineEdition') AS int) = 11
		EXEC test.run @test_names = @basic_test_names;
	ELSE
		EXEC sys.sp_executesql
			N'SET XACT_ABORT OFF; EXEC test.run @test_names = @names;',
			N'@names nvarchar(max)', @names = @basic_test_names;
	DROP TABLE #test_vectors;
	EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_vector_scope;
	PRINT N'Installation and tests complete.';
END TRY
BEGIN CATCH
	DROP TABLE IF EXISTS #test_vectors;
	EXEC sys.sp_set_session_context @key = N'ttest:vectors:scope', @value = @previous_vector_scope;
	THROW;
END CATCH;
GO
