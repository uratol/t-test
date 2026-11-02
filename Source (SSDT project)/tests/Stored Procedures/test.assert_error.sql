CREATE PROC [tests].[test.assert_error]
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
