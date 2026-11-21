-- Run 30 schema vectors, four schema/data vectors and 16 static query contexts.
-- Install install.sql and install-select-star-tests.sql first.
-- Fabric SELECT-star syntax is required; four REPLACE cases also compare one stable row.
IF OBJECT_ID(N'test.run', N'P') IS NULL
    OR OBJECT_ID(N'test.set_registration_scope', N'P') IS NULL
    OR OBJECT_ID(N'test.vector', N'P') IS NULL
    OR OBJECT_ID(N'select_star.test', N'P') IS NULL
    OR OBJECT_ID(N'select_star.test_data', N'P') IS NULL
    THROW 51090, 'Install T-TEST and SELECT-star test definitions before running.', 1;

GO

-- Reset only the two shared tests, then declare their 34 global vectors.
EXEC test.set_registration_scope @scope = N'global';
EXEC test.clear_registrations @test_name = N'[select_star].[test]';
EXEC test.clear_registrations @test_name = N'[select_star].[test_data]';
GO

-- Declare each vector through the framework API.
-- Double quotes delimit the argument list; quotes inside SQL values are doubled.
SET QUOTED_IDENTIFIER OFF;
-- test_plain
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_plain: Plain star preserves every catalog column in order',
        'name, object_id, principal_id, schema_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '*'";

-- test_like_suffix
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_like_suffix: LIKE suffix keeps all four ID columns in catalog order',
        'object_id, principal_id, schema_id, parent_object_id',
        '* LIKE ''%id'''";

-- test_like_not_like
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_like_not_like: LIKE and NOT LIKE intersect their selections',
        'modify_date',
        '* LIKE ''%date'' NOT LIKE ''create%'''";

-- test_not_like_chain
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_not_like_chain: Chained exclusions remove IDs and flags without reordering',
        'name, type, type_desc, create_date, modify_date',
        '* NOT LIKE ''%[_]id'' NOT LIKE ''is[_]%'''";

-- test_like_bracket_pattern
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_like_bracket_pattern: Bracket class selects o and p prefixes in source order',
        'object_id, principal_id, parent_object_id',
        '* LIKE ''[op]%'''";

-- test_exclude_single
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_exclude_single: EXCLUDE removes only its named column',
        'name, object_id, principal_id, schema_id, parent_object_id, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* EXCLUDE (type)'";

-- test_exclude_many
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_exclude_many: EXCLUDE removes every listed column',
        'name, object_id, principal_id, schema_id, parent_object_id, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* EXCLUDE (type, type_desc)'";

-- test_exclude_first
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_exclude_first: EXCLUDE first column leaves no ordinal gap',
        'object_id, principal_id, schema_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* EXCLUDE (name)'";

-- test_exclude_last
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_exclude_last: EXCLUDE last column preserves all preceding columns',
        'name, object_id, principal_id, schema_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published',
        '* EXCLUDE (is_schema_published)'";

-- test_rename_single
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_rename_single: RENAME changes a name without changing its type or ordinal',
        'name, object_id, principal_id, schema_id, parent_object_id, type, type_desc AS description, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* RENAME (type_desc AS description)'";

-- test_rename_many
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_rename_many: RENAME applies every listed alias',
        'name AS object_name, object_id, principal_id, schema_id, parent_object_id, type, type_desc AS description, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* RENAME (name AS object_name, type_desc AS description)'";

-- test_rename_preserves_order
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_rename_preserves_order: Alias spelling and RENAME list order do not reorder columns',
        'name AS z, object_id, principal_id, schema_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published AS first_column',
        '* RENAME (is_schema_published AS first_column, name AS z)'";

-- test_replace_cast_date
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_replace_cast_date: Date REPLACE changes only the selected column type',
        'name, object_id, principal_id, schema_id, parent_object_id, type, type_desc, create_date, CAST(modify_date AS date) AS modify_date, is_ms_shipped, is_published, is_schema_published',
        '* REPLACE (CAST(modify_date AS date) AS modify_date)'";

-- test_replace_chain
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_replace_chain: Chained REPLACE clauses update both original positions',
        'CAST(UPPER(name) AS varchar(40)) AS name, object_id, principal_id, schema_id, parent_object_id, type, type_desc, create_date, CAST(modify_date AS date) AS modify_date, is_ms_shipped, is_published, is_schema_published',
        '* REPLACE (CAST(UPPER(name) AS varchar(40)) AS name)
         REPLACE (CAST(modify_date AS date) AS modify_date)'";

-- test_replace_precision
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_replace_precision: Decimal REPLACE retains the requested precision and scale',
        'name, object_id, principal_id, CAST(schema_id AS decimal(10,3)) AS schema_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* REPLACE (CAST(schema_id AS decimal(10,3)) AS schema_id)'";

-- test_like_exclude
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_like_exclude: EXCLUDE subtracts from the LIKE-selected columns',
        'object_id, schema_id, parent_object_id',
        '* LIKE ''%id'' EXCLUDE (principal_id)'";

-- test_like_rename
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_like_rename: RENAME changes a LIKE-selected column without moving it',
        'object_id AS entity_id, principal_id, schema_id, parent_object_id',
        '* LIKE ''%id'' RENAME (object_id AS entity_id)'";

-- test_like_replace
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_like_replace: REPLACE changes the type of a LIKE-selected column',
        'object_id, principal_id, CAST(schema_id AS bigint) AS schema_id, parent_object_id',
        '* LIKE ''%id'' REPLACE (CAST(schema_id AS bigint) AS schema_id)'";

-- test_not_like_rename_replace
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_not_like_rename_replace: Negative filters compose with RENAME and REPLACE',
        'name, type, type_desc AS description, create_date, CAST(modify_date AS date) AS modify_date',
        '* NOT LIKE ''%[_]id'' NOT LIKE ''is[_]%''
         RENAME (type_desc AS description)
         REPLACE (CAST(modify_date AS date) AS modify_date)'";

-- test_exclude_rename_replace
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_exclude_rename_replace: EXCLUDE, RENAME and REPLACE preserve unaffected columns',
        'name AS object_name, object_id, CAST(schema_id AS bigint) AS schema_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* EXCLUDE (principal_id, parent_object_id)
         RENAME (name AS object_name) REPLACE (CAST(schema_id AS bigint) AS schema_id)'";

-- test_rename_replace
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_rename_replace: RENAME and REPLACE each preserve their source ordinal',
        'name AS object_name, object_id, principal_id, CAST(schema_id AS bigint) AS schema_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* RENAME (name AS object_name)
         REPLACE (CAST(schema_id AS bigint) AS schema_id)'";

-- test_rename_quoted
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_rename_quoted: Quoted aliases preserve literal spaces, dots and case',
        'name AS [Object Name], object_id AS [Object.ID], principal_id, schema_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* RENAME (name AS [Object Name], object_id AS [Object.ID])'";

-- test_like_literal_underscore
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_like_literal_underscore: LIKE with a literal underscore selects the four ID columns',
        'object_id, principal_id, schema_id, parent_object_id',
        '* LIKE ''%[_]id'''";

-- test_like_prefix
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_like_prefix: LIKE prefix selects the three catalog flags',
        'is_ms_shipped, is_published, is_schema_published',
        '* LIKE ''is_%'''";

-- test_like_prefix_escaped
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_like_prefix_escaped: LIKE with a literal is_ prefix selects the three catalog flags',
        'is_ms_shipped, is_published, is_schema_published',
        '* LIKE ''is[_]%'''";

-- test_not_like_suffix
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_not_like_suffix: NOT LIKE suffix excludes the four ID columns',
        'name, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* NOT LIKE ''%_id'''";

-- test_not_like_escaped_prefix
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_not_like_escaped_prefix: NOT LIKE literal is_ prefix excludes the three catalog flags',
        'name, object_id, principal_id, schema_id, parent_object_id, type, type_desc, create_date, modify_date',
        '* NOT LIKE ''is[_]%'''";

-- test_distinct
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_distinct: DISTINCT consumes the filtered star projection',
        'DISTINCT is_ms_shipped, is_published, is_schema_published',
        'DISTINCT * LIKE ''is[_]%'''";

-- test_qualified_star
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_qualified_star: Qualified star modifiers stay scoped to their input',
        's.object_id, CAST(s.schema_id * 2 AS bigint) AS schema_id, s.parent_object_id',
        's.* LIKE ''%[_]id'' EXCLUDE (principal_id) REPLACE (CAST(s.schema_id * 2 AS bigint) AS schema_id)'";

-- test_correlated
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'test_correlated: Explicit correlated expressions follow the star expansion',
        's.name, s.object_id, s.principal_id, s.schema_id, s.parent_object_id, s.type, s.create_date, s.modify_date, s.is_ms_shipped, s.is_published, s.is_schema_published, (SELECT COUNT(1) FROM sys.objects c WHERE c.parent_object_id = s.object_id) AS children',
        's.* EXCLUDE (type_desc), (SELECT COUNT(*) FROM sys.objects c WHERE c.parent_object_id = s.object_id) AS children'";

-- test_replace_arithmetic
EXEC test.vector @test_name = '[select_star].[test_data]',
    @arguments_sql = "
        'test_replace_arithmetic: Arithmetic REPLACE changes type at the original ordinal',
        'name, object_id, principal_id, CAST(schema_id * 2 AS bigint) AS schema_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* REPLACE (CAST(schema_id * 2 AS bigint) AS schema_id)'";

-- test_replace_null
EXEC test.vector @test_name = '[select_star].[test_data]',
    @arguments_sql = "
        'test_replace_null: Typed NULL REPLACE preserves the column name and ordinal',
        'name, object_id, principal_id, schema_id, parent_object_id, type, CAST(NULL AS varchar(10)) AS type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* REPLACE (CAST(NULL AS varchar(10)) AS type_desc)'";

-- test_combined
EXEC test.vector @test_name = '[select_star].[test_data]',
    @arguments_sql = "
        'test_combined: Combined filters, EXCLUDE, RENAME and REPLACE match projection',
        'name, type_desc AS description, CAST(modify_date AS date) AS create_date, CAST(modify_date AS date) AS modify_date',
        '* NOT LIKE ''%[_]id'' NOT LIKE ''is[_]%'' EXCLUDE (type) RENAME (type_desc AS description) REPLACE (CAST(modify_date AS date) AS create_date) REPLACE (CAST(modify_date AS date) AS modify_date)'";

-- test_replace_same_type
EXEC test.vector @test_name = '[select_star].[test_data]',
    @arguments_sql = "
        'test_replace_same_type: Same-type REPLACE retains the original column schema',
        'name, -object_id AS object_id, principal_id, schema_id, parent_object_id, type, type_desc, create_date, modify_date, is_ms_shipped, is_published, is_schema_published',
        '* REPLACE (-object_id AS object_id)'";

SET QUOTED_IDENTIFIER ON;
GO
EXEC test.run @test_schemas = N'select_star';
