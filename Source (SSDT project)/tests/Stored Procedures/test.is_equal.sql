CREATE PROC [tests].[test.is_equal]
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
