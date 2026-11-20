-- Run every installed STDEV test, including stdev@basic.
-- Install install.sql; install-stdev-tests.sql adds 27 reference-series tests.
-- STDEV is a concept without an object schema, so select its tests by name pattern.
-- Run outside a transaction. New stdev@... tests are included automatically.
IF OBJECT_ID(N'test.run', N'P') IS NULL
    THROW 51090, 'Install T-TEST before running STDEV tests.', 1;

EXEC test.run @test_names = N'[tests].stdev@%';
