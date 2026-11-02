CREATE PROC [tests].[test.assert_float_equals]
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
