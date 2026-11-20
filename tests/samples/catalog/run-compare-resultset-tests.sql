-- Run every installed catalog test targeting the sys schema, including basic tables.
-- Install install.sql; install-compare-resultset-tests.sql adds 12 catalog tests.
-- Procedure containers and tested-object schemas are separate filters.
-- Run outside a transaction with metadata visibility and no concurrent catalog DDL.
IF OBJECT_ID(N'test.run', N'P') IS NULL
    THROW 51090, 'Install T-TEST before running catalog tests.', 1;

EXEC test.run @test_schemas = N'tests', @test_object_schemas = N'sys';
