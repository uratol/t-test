CREATE PROC [tests].[test.format_message]
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
