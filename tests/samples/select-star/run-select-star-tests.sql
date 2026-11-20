-- Run every test procedure installed in the select_star schema.
-- Install install.sql and install-select-star-tests.sql first.
-- Fabric SELECT-star syntax is required; four REPLACE cases also compare one stable row.
IF OBJECT_ID(N'test.run', N'P') IS NULL
    THROW 51090, 'Install updated T-TEST before running SELECT-star tests.', 1;

EXEC test.run @test_schemas = N'select_star';
