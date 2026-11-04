-- SQL Server 2022+ / Fabric Warehouse.
-- Removes the 70 shipped test procedures, framework objects and legacy API names.
-- Preserves schemas, unrelated user objects, tables and data.
-- Custom tests that depend on the framework will need it reinstalled.
-- Run the entire file outside a transaction. Cleanup is not atomic.
SET NOCOUNT ON;
IF @@TRANCOUNT > 0
	THROW 51090, 'Run uninstall.sql outside a transaction.', 1;

BEGIN TRY
	-- Basic verification (15).
	DROP PROCEDURE IF EXISTS [tests].[test.test];
	DROP PROCEDURE IF EXISTS [tests].[test.test@name_convention];
	DROP PROCEDURE IF EXISTS [tests].[test.format_message];
	DROP PROCEDURE IF EXISTS [tests].[test.throw];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_equals];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_float_equals];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_resultset_equals];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_query_equals];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_error];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_not_null];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_null];
	DROP PROCEDURE IF EXISTS [tests].[test.is_equal];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@tables];
	DROP PROCEDURE IF EXISTS [tests].[stdev@basic];
	DROP PROCEDURE IF EXISTS [tests].[data_types@basic];
	DROP PROCEDURE IF EXISTS [tests].[power@vectors];

	-- Additional framework coverage (16).
	DROP PROCEDURE IF EXISTS [tests].[test.is_equal@fc_values];
	DROP PROCEDURE IF EXISTS [tests].[test.is_json_equal@fc_json];
	DROP PROCEDURE IF EXISTS [tests].[test.is_equal_openjson@fc_json];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_equals@fc_assertions];
	DROP PROCEDURE IF EXISTS [tests].[test.throw_error@fc_error_helpers];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_null@fc_null];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_not_null@fc_not_null];
	DROP PROCEDURE IF EXISTS [tests].[test.fail@fc_failure];
	DROP PROCEDURE IF EXISTS [tests].[test.fail_no_error@fc_no_error];
	DROP PROCEDURE IF EXISTS [tests].[test.error@fc_no_error];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_error_like@fc_patterns];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_error_number@fc_error_assertions];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_error@fc_patterns];
	DROP PROCEDURE IF EXISTS [tests].[test.assert_error@fc_error_assertions];
	DROP PROCEDURE IF EXISTS [tests].[test.format_message@fc_parameters];
	DROP PROCEDURE IF EXISTS [tests].[test.log@fc_logging];
	DROP PROCEDURE IF EXISTS [tests].[test.throw@fc_throwing];
	DROP PROCEDURE IF EXISTS [tests].[test.test@fc_catalog];
	DROP PROCEDURE IF EXISTS [tests].[test.set_scope@fc_context];
	DROP PROCEDURE IF EXISTS [tests].[test.vector@fc_literals];

	-- Additional catalog comparisons (12).
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@views];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@procedures];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@key_constraints];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@foreign_keys];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@check_constraints];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@default_constraints];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@information_schema.tables];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@information_schema.views];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@information_schema.routines];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@information_schema.table_constraints];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@information_schema.check_constraints];
	DROP PROCEDURE IF EXISTS [tests].[sys.objects@information_schema.referential_constraints];

	-- Additional STDEV cases (27).
	DROP PROCEDURE IF EXISTS [tests].[stdev@log_0];
	DROP PROCEDURE IF EXISTS [tests].[stdev@sin_0];
	DROP PROCEDURE IF EXISTS [tests].[stdev@value_0];
	DROP PROCEDURE IF EXISTS [tests].[stdev@log_1];
	DROP PROCEDURE IF EXISTS [tests].[stdev@sin_1];
	DROP PROCEDURE IF EXISTS [tests].[stdev@value_1];
	DROP PROCEDURE IF EXISTS [tests].[stdev@log_2];
	DROP PROCEDURE IF EXISTS [tests].[stdev@sin_2];
	DROP PROCEDURE IF EXISTS [tests].[stdev@value_2];
	DROP PROCEDURE IF EXISTS [tests].[stdev@log_3];
	DROP PROCEDURE IF EXISTS [tests].[stdev@sin_3];
	DROP PROCEDURE IF EXISTS [tests].[stdev@value_3];
	DROP PROCEDURE IF EXISTS [tests].[stdev@log_10];
	DROP PROCEDURE IF EXISTS [tests].[stdev@sin_10];
	DROP PROCEDURE IF EXISTS [tests].[stdev@value_10];
	DROP PROCEDURE IF EXISTS [tests].[stdev@log_100];
	DROP PROCEDURE IF EXISTS [tests].[stdev@sin_100];
	DROP PROCEDURE IF EXISTS [tests].[stdev@value_100];
	DROP PROCEDURE IF EXISTS [tests].[stdev@log_1000];
	DROP PROCEDURE IF EXISTS [tests].[stdev@sin_1000];
	DROP PROCEDURE IF EXISTS [tests].[stdev@value_1000];
	DROP PROCEDURE IF EXISTS [tests].[stdev@log_10000];
	DROP PROCEDURE IF EXISTS [tests].[stdev@sin_10000];
	DROP PROCEDURE IF EXISTS [tests].[stdev@value_10000];
	DROP PROCEDURE IF EXISTS [tests].[stdev@log_100000];
	DROP PROCEDURE IF EXISTS [tests].[stdev@sin_100000];
	DROP PROCEDURE IF EXISTS [tests].[stdev@value_100000];

	DROP PROCEDURE IF EXISTS [test].[run];
	DROP PROCEDURE IF EXISTS [test].[reset];
	DROP PROCEDURE IF EXISTS [test].[vector];
	DROP PROCEDURE IF EXISTS [test].[set_scope];
	DROP PROCEDURE IF EXISTS [test].[assert_resultset_equals];
	DROP PROCEDURE IF EXISTS [test].[assert_query_equals];
	DROP PROCEDURE IF EXISTS [test].[throw];
	DROP PROCEDURE IF EXISTS [test].[log];
	IF OBJECT_ID(N'[test].[test]', N'V') IS NOT NULL
		DROP VIEW [test].[test];

	IF OBJECT_ID(N'[test].[assert_equals]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[assert_equals];
	IF OBJECT_ID(N'[test].[assert_float_equals]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[assert_float_equals];
	IF OBJECT_ID(N'[test].[assert_null]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[assert_null];
	IF OBJECT_ID(N'[test].[assert_not_null]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[assert_not_null];
	IF OBJECT_ID(N'[test].[assert_error_like]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[assert_error_like];
	IF OBJECT_ID(N'[test].[assert_error]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[assert_error];
	IF OBJECT_ID(N'[test].[assert_error_number]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[assert_error_number];
	IF OBJECT_ID(N'[test].[error]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[error];
	IF OBJECT_ID(N'[test].[fail_no_error]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[fail_no_error];
	IF OBJECT_ID(N'[test].[fail]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[fail];
	IF OBJECT_ID(N'[test].[is_equal]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[is_equal];
	IF OBJECT_ID(N'[test].[is_json_equal]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[is_json_equal];
	IF OBJECT_ID(N'[test].[is_equal_openjson]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[is_equal_openjson];
	IF OBJECT_ID(N'[test].[format_message]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[format_message];
	IF OBJECT_ID(N'[test].[throw_error]', N'FN') IS NOT NULL
		DROP FUNCTION [test].[throw_error];

	PRINT N'T-TEST uninstalled. User objects and schemas retained.';
END TRY
BEGIN CATCH
	THROW;
END CATCH;
