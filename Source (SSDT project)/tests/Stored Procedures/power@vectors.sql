CREATE PROCEDURE [tests].[power@vectors]
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
