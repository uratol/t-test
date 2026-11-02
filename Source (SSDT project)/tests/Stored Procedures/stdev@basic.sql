CREATE PROC [tests].[stdev@basic]
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
