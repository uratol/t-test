CREATE PROC [tests].[test.assert_resultset_equals]
AS
PRINT N'Compare sys.objects user tables with sys.tables.';
PRINT N'Expect: all common columns match, including NULLs.';
SET NOCOUNT ON;

-- Assert
EXEC test.assert_resultset_equals
	@message = N'sys.objects tables must match sys.tables',
	@expected_query = N'
		SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
			o.object_id, o.principal_id, o.schema_id, o.parent_object_id,
			o.type, o.type_desc, o.create_date, o.modify_date,
			o.is_ms_shipped, o.is_published, o.is_schema_published
		FROM sys.objects o
		WHERE o.type = N''U'' AND o.is_ms_shipped = 0
		ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
			o.name COLLATE Latin1_General_100_BIN2',
	@actual_query = N'
		SELECT SCHEMA_NAME(o.schema_id) AS schema_name, o.name AS object_name,
			o.object_id, o.principal_id, o.schema_id, o.parent_object_id,
			o.type, o.type_desc, o.create_date, o.modify_date,
			o.is_ms_shipped, o.is_published, o.is_schema_published
		FROM sys.tables o
		WHERE o.is_ms_shipped = 0
		ORDER BY SCHEMA_NAME(o.schema_id) COLLATE Latin1_General_100_BIN2,
			o.name COLLATE Latin1_General_100_BIN2';
