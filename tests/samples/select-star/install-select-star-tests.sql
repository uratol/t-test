-- Install 50 independent Fabric Warehouse SELECT-star query-contract tests.
-- Install updated T-TEST first; execute run-select-star-tests.sql separately.
-- Arrange: an independent explicit projection over existing system views.
-- Act: the equivalent SELECT-star expression, including composed/nested operators.
-- Assert: ordered names and types must match; selected REPLACE tests also compare rows.
-- Basic tests use direct SELECT ... FROM sys.objects queries.
-- Derived inputs and WITH appear only in the explicitly marked edge-case section.
-- No input-table fixtures, generated reference projections, or hardcoded type signatures.
-- Schema assertions create and clean metadata views in schema test.
-- Procedures live in select_star; use test.run @test_schemas = N'select_star'.
-- EXCLUDE modifies the star projection; it is not the EXCEPT set operator.
SET NOCOUNT ON;

IF OBJECT_ID(N'test.assert_query_schemas_equal', N'P') IS NULL
	OR OBJECT_ID(N'test.assert_resultset_equals', N'P') IS NULL
	OR OBJECT_ID(N'test.run', N'P') IS NULL
	THROW 51090, 'Install updated T-TEST before installing these tests.', 1;
IF SCHEMA_ID(N'select_star') IS NULL
	EXEC(N'CREATE SCHEMA select_star AUTHORIZATION dbo;');
DROP PROCEDURE IF EXISTS select_star.assert_schema;
-- Remove the retired CTAS tests when upgrading an existing package.
DROP PROCEDURE IF EXISTS select_star.test_ctas_like;
DROP PROCEDURE IF EXISTS select_star.test_ctas_combined;
DROP PROCEDURE IF EXISTS select_star.test_ctas_cte;
DROP PROCEDURE IF EXISTS select_star.test_ctas_empty;
GO

-- Basic operators: explicit columns versus a star expression over the same system view.
CREATE OR ALTER PROCEDURE select_star.test_plain
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id, schema_id, parent_object_id,
		type, type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Plain star preserves every catalog column in order',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_like_suffix
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query =
		N'SELECT object_id, principal_id, schema_id, parent_object_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''%id'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'LIKE suffix keeps all four ID columns in catalog order',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_like_not_like
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT modify_date FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''%date'' NOT LIKE ''create%'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'LIKE and NOT LIKE intersect their selections',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_not_like_chain
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, type, type_desc, create_date, modify_date
		FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * NOT LIKE ''%[_]id'' NOT LIKE ''is[_]%'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Chained exclusions remove IDs and flags without reordering',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_like_bracket_pattern
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, principal_id, parent_object_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''[op]%'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Bracket class selects o and p prefixes in source order',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_exclude_single
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id, schema_id, parent_object_id,
		type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * EXCLUDE (type) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'EXCLUDE removes only its named column',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_exclude_many
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id, schema_id, parent_object_id,
		create_date, modify_date, is_ms_shipped, is_published, is_schema_published
		FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * EXCLUDE (type, type_desc) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'EXCLUDE removes every listed column',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_exclude_first
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, principal_id, schema_id, parent_object_id,
		type, type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * EXCLUDE (name) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'EXCLUDE first column leaves no ordinal gap',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_exclude_last
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id, schema_id, parent_object_id,
		type, type_desc, create_date, modify_date, is_ms_shipped, is_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * EXCLUDE (is_schema_published) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'EXCLUDE last column preserves all preceding columns',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_rename_single
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id, schema_id, parent_object_id,
		type, type_desc AS description, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * RENAME (type_desc AS description) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'RENAME changes a name without changing its type or ordinal',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_rename_many
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name AS object_name, object_id, principal_id, schema_id,
		parent_object_id, type, type_desc AS description, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query =
		N'SELECT * RENAME (name AS object_name, type_desc AS description) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'RENAME applies every listed alias',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_rename_preserves_order
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name AS z, object_id, principal_id, schema_id,
		parent_object_id, type, type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published AS first_column FROM sys.objects;';

	-- Act
	SET @actual_query =
		N'SELECT * RENAME (is_schema_published AS first_column, name AS z) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Alias spelling and RENAME list order do not reorder columns',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_replace_arithmetic
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id,
		CAST(schema_id * 2 AS bigint) AS schema_id, parent_object_id,
		type, type_desc, create_date, modify_date, is_ms_shipped, is_published,
		is_schema_published FROM sys.objects WHERE object_id = OBJECT_ID(N''test.run'');';

	-- Act
	SET @actual_query = N'SELECT * REPLACE (CAST(schema_id * 2 AS bigint) AS schema_id)
		FROM sys.objects WHERE object_id = OBJECT_ID(N''test.run'');';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Arithmetic REPLACE changes type at the original ordinal',
		@expected_query, @actual_query;
	EXEC test.assert_resultset_equals N'Arithmetic REPLACE evaluates the expected expression',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_replace_cast_date
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id, schema_id, parent_object_id,
		type, type_desc, create_date, CAST(modify_date AS date) AS modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * REPLACE (CAST(modify_date AS date) AS modify_date)
		FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Date REPLACE changes only the selected column type',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_replace_null
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id, schema_id, parent_object_id,
		type, CAST(NULL AS varchar(10)) AS type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published
		FROM sys.objects WHERE object_id = OBJECT_ID(N''test.run'');';

	-- Act
	SET @actual_query = N'SELECT * REPLACE (CAST(NULL AS varchar(10)) AS type_desc)
		FROM sys.objects WHERE object_id = OBJECT_ID(N''test.run'');';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Typed NULL REPLACE preserves the column name and ordinal',
		@expected_query, @actual_query;
	EXEC test.assert_resultset_equals N'Typed NULL REPLACE returns NULL, not the catalog value',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_replace_chain
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT CAST(UPPER(name) AS varchar(40)) AS name,
		object_id, principal_id, schema_id, parent_object_id, type, type_desc,
		create_date, CAST(modify_date AS date) AS modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * REPLACE (CAST(UPPER(name) AS varchar(40)) AS name)
		REPLACE (CAST(modify_date AS date) AS modify_date) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Chained REPLACE clauses update both original positions',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_replace_precision
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id,
		CAST(schema_id AS decimal(10,3)) AS schema_id, parent_object_id,
		type, type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * REPLACE (CAST(schema_id AS decimal(10,3)) AS schema_id)
		FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Decimal REPLACE retains the requested precision and scale',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_combined
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, type_desc AS description,
		CAST(modify_date AS date) AS create_date, CAST(modify_date AS date) AS modify_date
		FROM sys.objects WHERE object_id = OBJECT_ID(N''test.run'');';

	-- Act
	SET @actual_query = N'SELECT * NOT LIKE ''%[_]id'' NOT LIKE ''is[_]%'' EXCLUDE (type)
		RENAME (type_desc AS description)
		REPLACE (CAST(modify_date AS date) AS create_date)
		REPLACE (CAST(modify_date AS date) AS modify_date)
		FROM sys.objects WHERE object_id = OBJECT_ID(N''test.run'');';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Combined filters, EXCLUDE, RENAME and REPLACE match projection',
		@expected_query, @actual_query;
	EXEC test.assert_resultset_equals N'Combined REPLACE expressions use the expected source values',
		@expected_query, @actual_query;
END;
GO

-- Basic combinations: keep both queries direct; do not hide the projection in a CTE.
CREATE OR ALTER PROCEDURE select_star.test_like_exclude
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, schema_id, parent_object_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''%id'' EXCLUDE (principal_id) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'EXCLUDE subtracts from the LIKE-selected columns',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_like_rename
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query =
		N'SELECT object_id AS entity_id, principal_id, schema_id, parent_object_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''%id'' RENAME (object_id AS entity_id) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'RENAME changes a LIKE-selected column without moving it',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_like_replace
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT object_id, principal_id,
		CAST(schema_id AS bigint) AS schema_id, parent_object_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''%id'' REPLACE (CAST(schema_id AS bigint) AS schema_id)
		FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'REPLACE changes the type of a LIKE-selected column',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_not_like_rename_replace
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, type, type_desc AS description,
		create_date, CAST(modify_date AS date) AS modify_date FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * NOT LIKE ''%[_]id'' NOT LIKE ''is[_]%''
		RENAME (type_desc AS description)
		REPLACE (CAST(modify_date AS date) AS modify_date) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Negative filters compose with RENAME and REPLACE',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_exclude_rename_replace
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name AS object_name, object_id,
		CAST(schema_id AS bigint) AS schema_id, type, type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * EXCLUDE (principal_id, parent_object_id)
		RENAME (name AS object_name) REPLACE (CAST(schema_id AS bigint) AS schema_id)
		FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'EXCLUDE, RENAME and REPLACE preserve unaffected columns',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_rename_replace
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name AS object_name, object_id, principal_id,
		CAST(schema_id AS bigint) AS schema_id, parent_object_id,
		type, type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * RENAME (name AS object_name)
		REPLACE (CAST(schema_id AS bigint) AS schema_id) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'RENAME and REPLACE each preserve their source ordinal',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_rename_quoted
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name AS [Object Name], object_id AS [Object.ID],
		principal_id, schema_id, parent_object_id, type, type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query =
		N'SELECT * RENAME (name AS [Object Name], object_id AS [Object.ID]) FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Quoted aliases preserve literal spaces, dots and case',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_replace_same_type
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, -object_id AS object_id, principal_id, schema_id,
		parent_object_id, type, type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published
		FROM sys.objects WHERE object_id = OBJECT_ID(N''test.run'');';

	-- Act
	SET @actual_query = N'SELECT * REPLACE (-object_id AS object_id)
		FROM sys.objects WHERE object_id = OBJECT_ID(N''test.run'');';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Same-type REPLACE retains the original column schema',
		@expected_query, @actual_query;
	EXEC test.assert_resultset_equals N'Same-type REPLACE must change the value, not just bind',
		@expected_query, @actual_query;
END;
GO

-- Basic LIKE patterns: only the SELECT lists differ; both sources are sys.objects.
CREATE OR ALTER PROCEDURE select_star.test_like_literal_underscore
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query =
		N'SELECT object_id, principal_id, schema_id, parent_object_id FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''%[_]id'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'LIKE with a literal underscore selects the four ID columns',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_like_prefix
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query =
		N'SELECT is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''is_%'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'LIKE prefix selects the three catalog flags',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_like_prefix_escaped
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query =
		N'SELECT is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * LIKE ''is[_]%'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'LIKE with a literal is_ prefix selects the three catalog flags',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_not_like_suffix
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, type, type_desc, create_date, modify_date,
		is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * NOT LIKE ''%_id'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'NOT LIKE suffix excludes the four ID columns',
		@expected_query, @actual_query;
END;
GO

CREATE OR ALTER PROCEDURE select_star.test_not_like_escaped_prefix
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT name, object_id, principal_id, schema_id, parent_object_id,
		type, type_desc, create_date, modify_date FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT * NOT LIKE ''is[_]%'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'NOT LIKE literal is_ prefix excludes the three catalog flags',
		@expected_query, @actual_query;
END;
GO

-- Edge cases: qualified/joined stars and query contexts, including nested SELECT and WITH.
CREATE OR ALTER PROCEDURE select_star.test_qualified_star
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT s.object_id, CAST(s.schema_id * 2 AS bigint) AS schema_id,
		s.parent_object_id FROM sys.objects s;';

	-- Act
	SET @actual_query = N'SELECT s.* LIKE ''%[_]id'' EXCLUDE (principal_id)
		REPLACE (CAST(s.schema_id * 2 AS bigint) AS schema_id) FROM sys.objects s;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Qualified star modifiers stay scoped to their input',
		@expected_query, @actual_query;
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

CREATE OR ALTER PROCEDURE select_star.test_distinct
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query =
		N'SELECT DISTINCT is_ms_shipped, is_published, is_schema_published FROM sys.objects;';

	-- Act
	SET @actual_query = N'SELECT DISTINCT * LIKE ''is[_]%'' FROM sys.objects;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'DISTINCT consumes the filtered star projection',
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

CREATE OR ALTER PROCEDURE select_star.test_correlated
AS
BEGIN
	SET NOCOUNT ON;
	DECLARE @expected_query nvarchar(max), @actual_query nvarchar(max);

	-- Arrange
	SET @expected_query = N'SELECT o.name, o.object_id, o.principal_id, o.schema_id,
		o.parent_object_id, o.type, o.create_date, o.modify_date,
		o.is_ms_shipped, o.is_published, o.is_schema_published,
		(SELECT COUNT(1) FROM sys.objects c WHERE c.parent_object_id = o.object_id) AS children
		FROM sys.objects o;';

	-- Act
	SET @actual_query = N'SELECT o.* EXCLUDE (type_desc),
		(SELECT COUNT(*) FROM sys.objects c WHERE c.parent_object_id = o.object_id) AS children
		FROM sys.objects o;';

	-- Assert
	EXEC test.assert_query_schemas_equal N'Explicit correlated expressions follow the star expansion',
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
