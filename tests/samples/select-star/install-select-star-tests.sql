-- Fabric Warehouse only: install two shared tests and 16 static query contexts.
-- The shared data test checks both schemas and values on one stable catalog row.
-- Definitions only. Run run-select-star-tests.sql to reset/register vectors and execute.
-- Query pairs are independently written, never generated from actual metadata.
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
IF SCHEMA_ID(N'select_star') IS NULL
    EXEC(N'CREATE SCHEMA select_star AUTHORIZATION dbo;');
GO

CREATE OR ALTER PROCEDURE select_star.test
    @case_name nvarchar(max),
    @expected_columns nvarchar(max),
    @star_expression nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

    -- Arrange
    SET @expected_query = CONCAT(N'SELECT ', @expected_columns, N' FROM sys.objects s;');

    -- Act
    SET @actual_query = CONCAT(N'SELECT ', @star_expression, N' FROM sys.objects s;');

    -- Assert
    EXEC test.assert_query_schemas_equal @case_name, @expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_data
    @case_name nvarchar(max),
    @expected_columns nvarchar(max),
    @star_expression nvarchar(max)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

    -- Arrange
    SET @expected_query = CONCAT(N'SELECT ', @expected_columns,
        N' FROM sys.objects WHERE object_id = OBJECT_ID(''test.run'');');

    -- Act
    SET @actual_query = CONCAT(N'SELECT ', @star_expression,
        N' FROM sys.objects WHERE object_id = OBJECT_ID(''test.run'');');

    -- Assert
    EXEC test.assert_query_schemas_equal @case_name, @expected_query, @actual_query;
    EXEC test.assert_resultset_equals @case_name, @expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_join
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT s.object_id, s.principal_id, s.schema_id, s.parent_object_id,
		p.name AS parent_name FROM sys.objects s
		LEFT JOIN sys.objects p ON p.object_id = s.parent_object_id;';

	-- Act
	SET @actual_query = N'SELECT s.* LIKE ''%[_]id'', p.name AS parent_name FROM sys.objects s
		LEFT JOIN sys.objects p ON p.object_id = s.parent_object_id;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Qualified star in a join does not absorb other inputs',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_two_stars
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT o.object_id, s.name AS schema_name, s.schema_id AS schema_key
		FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id;';

	-- Act
	SET @actual_query = N'SELECT o.* LIKE ''object[_]id'',
		s.* EXCLUDE (principal_id) RENAME (name AS schema_name, schema_id AS schema_key)
		FROM sys.objects o JOIN sys.schemas s ON s.schema_id = o.schema_id;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Each star has independent modifiers and expansion position',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_derived_inner
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id AS id, schema_id, parent_object_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT q.* FROM (
		SELECT * LIKE ''%[_]id'' EXCLUDE (principal_id) RENAME (object_id AS id)
		FROM sys.objects) q;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Inner derived modifiers determine the outer star schema',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_derived_outer
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, name AS object_name,
		CAST(schema_id * 2 AS bigint) AS schema_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * RENAME (name AS object_name)
		REPLACE (CAST(schema_id * 2 AS bigint) AS schema_id)
		FROM (SELECT object_id, name, schema_id FROM sys.objects) q;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Outer derived modifiers apply to the derived projection',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_nested_derived
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, name AS object_name,
		CAST(schema_id * 2 AS bigint) AS schema_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT q.* RENAME (name AS object_name) FROM (
		SELECT p.* REPLACE (CAST(schema_id * 2 AS bigint) AS schema_id)
		FROM (SELECT object_id, name, schema_id FROM sys.objects) p) q;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Nested derived stars propagate earlier replacement types',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_cte_inner
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id AS id, schema_id, parent_object_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'WITH p AS (
		SELECT * LIKE ''%[_]id'' EXCLUDE (principal_id) RENAME (object_id AS id)
		FROM sys.objects) SELECT p.* FROM p;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'CTE exposes the schema produced by its inner modifiers',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_cte_outer
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, type, type_desc, create_date, modify_date
		FROM sys.objects;';

	-- Act
	SET @actual_query = N'WITH p AS (SELECT * FROM sys.objects)
		SELECT * NOT LIKE ''%[_]id'' NOT LIKE ''is[_]%'' FROM p;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Outer filters can select from a CTE star expansion',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_cte_chain
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, name AS object_name,
		CAST(schema_id * 2 AS bigint) AS schema_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'WITH p AS (SELECT object_id, name, schema_id FROM sys.objects),
		q AS (SELECT * REPLACE (CAST(schema_id * 2 AS bigint) AS schema_id) FROM p),
		r AS (SELECT * RENAME (name AS object_name) FROM q)
		SELECT r.* FROM r;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'CTE stages preserve replacement types and renamed columns',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_union_all
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, principal_id, schema_id, parent_object_id
		FROM sys.objects WHERE object_id = 1
		UNION ALL SELECT object_id, principal_id, schema_id, parent_object_id
		FROM sys.objects WHERE object_id = 2;';

	-- Act
	SET @actual_query = N'SELECT u.* FROM (
		SELECT * LIKE ''%[_]id'' FROM sys.objects WHERE object_id = 1
		UNION ALL SELECT * LIKE ''%[_]id'' FROM sys.objects WHERE object_id = 2) u;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'UNION ALL binds compatible independently expanded stars',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_top_where
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT TOP (2) object_id, schema_id, parent_object_id
		FROM sys.objects WHERE object_id > 1 ORDER BY object_id DESC;';

	-- Act
	SET @actual_query = N'SELECT TOP (2) * LIKE ''%[_]id'' EXCLUDE (principal_id)
		FROM sys.objects WHERE object_id > 1 ORDER BY object_id DESC;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'TOP, WHERE and ORDER BY preserve the modified projection',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_empty
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name AS object_name, object_id FROM sys.objects WHERE 1 = 0;';

	-- Act
	SET @actual_query = N'SELECT * EXCLUDE (principal_id, schema_id, parent_object_id,
		type, type_desc, create_date, modify_date, is_ms_shipped, is_published,
		is_schema_published) RENAME (name AS object_name) FROM sys.objects WHERE 1 = 0;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Empty inputs still expose renamed columns and their order',
		@expected_query, @actual_query;
END;
GO


CREATE OR ALTER PROCEDURE select_star.test_aggregate
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT parent_object_id,
		SUM(CAST(schema_id * 2 AS bigint)) AS total FROM sys.objects GROUP BY parent_object_id;';

	-- Act
	SET @actual_query = N'SELECT parent_object_id, SUM(schema_id) AS total FROM (
		SELECT * LIKE ''%[_]id'' EXCLUDE (object_id, principal_id)
		REPLACE (CAST(schema_id * 2 AS bigint) AS schema_id)
		FROM sys.objects) q GROUP BY parent_object_id;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Aggregate return type follows the replaced input type',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_pivot_input
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT [U], [V] FROM (
		SELECT schema_id, type FROM sys.objects) s
		PIVOT (SUM(schema_id) FOR type IN ([U], [V])) p;';

	-- Act
	SET @actual_query = N'SELECT p.* FROM (
		SELECT * EXCLUDE (name, object_id, principal_id, parent_object_id, type_desc,
			create_date, modify_date, is_ms_shipped, is_published, is_schema_published)
		FROM sys.objects) s PIVOT (SUM(schema_id) FOR type IN ([U], [V])) p;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'PIVOT input excludes every unintended grouping column',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_pivot_output
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT [U] AS u_total,
		CAST(COALESCE([V], 0) AS decimal(18,2)) AS [V]
		FROM (SELECT parent_object_id, type, schema_id FROM sys.objects) s
		PIVOT (SUM(schema_id) FOR type IN ([U], [V])) p;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''[UV]'' RENAME ([U] AS u_total)
		REPLACE (CAST(COALESCE([V], 0) AS decimal(18,2)) AS [V])
		FROM (SELECT parent_object_id, type, schema_id FROM sys.objects) s
		PIVOT (SUM(schema_id) FOR type IN ([U], [V])) p;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'PIVOT output supports filtering, renaming and replacement',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_unpivot_input
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, value, metric FROM (
		SELECT object_id, principal_id, schema_id FROM sys.objects) s
		UNPIVOT (value FOR metric IN (principal_id, schema_id)) u;';

	-- Act
	SET @actual_query = N'SELECT object_id, value, metric FROM (
		SELECT * LIKE ''%[_]id'' EXCLUDE (parent_object_id) FROM sys.objects) s
		UNPIVOT (value FOR metric IN (principal_id, schema_id)) u;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'UNPIVOT input consumes only the selected ID columns',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_unpivot_output
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, value AS measure_value, metric AS measure_name
		FROM (SELECT object_id, principal_id, schema_id FROM sys.objects) s
		UNPIVOT (value FOR metric IN (principal_id, schema_id)) u;';

	-- Act
	SET @actual_query = N'SELECT * RENAME (value AS measure_value, metric AS measure_name)
		FROM (SELECT object_id, principal_id, schema_id FROM sys.objects) s
		UNPIVOT (value FOR metric IN (principal_id, schema_id)) u;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'UNPIVOT output retains value and metric types when renamed',
		@expected_query, @actual_query;
END;
GO

-- Retire the replaced package procedures, not unrelated objects or registration rows.
DROP PROCEDURE IF EXISTS select_star.assert_schema;
DROP PROCEDURE IF EXISTS select_star.test_ctas_like;
DROP PROCEDURE IF EXISTS select_star.test_ctas_combined;
DROP PROCEDURE IF EXISTS select_star.test_ctas_cte;
DROP PROCEDURE IF EXISTS select_star.test_ctas_empty;
DROP PROCEDURE IF EXISTS select_star.test_plain;
DROP PROCEDURE IF EXISTS select_star.test_like_suffix;
DROP PROCEDURE IF EXISTS select_star.test_like_not_like;
DROP PROCEDURE IF EXISTS select_star.test_not_like_chain;
DROP PROCEDURE IF EXISTS select_star.test_like_bracket_pattern;
DROP PROCEDURE IF EXISTS select_star.test_exclude_single;
DROP PROCEDURE IF EXISTS select_star.test_exclude_many;
DROP PROCEDURE IF EXISTS select_star.test_exclude_first;
DROP PROCEDURE IF EXISTS select_star.test_exclude_last;
DROP PROCEDURE IF EXISTS select_star.test_rename_single;
DROP PROCEDURE IF EXISTS select_star.test_rename_many;
DROP PROCEDURE IF EXISTS select_star.test_rename_preserves_order;
DROP PROCEDURE IF EXISTS select_star.test_replace_cast_date;
DROP PROCEDURE IF EXISTS select_star.test_replace_chain;
DROP PROCEDURE IF EXISTS select_star.test_replace_precision;
DROP PROCEDURE IF EXISTS select_star.test_like_exclude;
DROP PROCEDURE IF EXISTS select_star.test_like_rename;
DROP PROCEDURE IF EXISTS select_star.test_like_replace;
DROP PROCEDURE IF EXISTS select_star.test_not_like_rename_replace;
DROP PROCEDURE IF EXISTS select_star.test_exclude_rename_replace;
DROP PROCEDURE IF EXISTS select_star.test_rename_replace;
DROP PROCEDURE IF EXISTS select_star.test_rename_quoted;
DROP PROCEDURE IF EXISTS select_star.test_like_literal_underscore;
DROP PROCEDURE IF EXISTS select_star.test_like_prefix;
DROP PROCEDURE IF EXISTS select_star.test_like_prefix_escaped;
DROP PROCEDURE IF EXISTS select_star.test_not_like_suffix;
DROP PROCEDURE IF EXISTS select_star.test_not_like_escaped_prefix;
DROP PROCEDURE IF EXISTS select_star.test_distinct;
GO

DROP PROCEDURE IF EXISTS select_star.test_replace_arithmetic;
GO

DROP PROCEDURE IF EXISTS select_star.test_replace_null;
GO

DROP PROCEDURE IF EXISTS select_star.test_combined;
GO

DROP PROCEDURE IF EXISTS select_star.test_replace_same_type;
GO

DROP PROCEDURE IF EXISTS select_star.test_qualified_star;
GO

DROP PROCEDURE IF EXISTS select_star.test_correlated;
GO
