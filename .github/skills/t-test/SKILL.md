---
name: t-test
description: Author and refactor T-TEST T-SQL tests for SQL Server and Microsoft Fabric Warehouse. Use when creating SQL unit tests, choosing static tests versus data vectors or dimensions, registering cases with test.vector, selecting assertions, or separating sample installation from execution.
compatibility: SQL Server 2022+ or Fabric Warehouse. Local release checks require PowerShell, sqlcmd, Windows authentication and an explicitly supplied SQL Server endpoint; Fabric execution requires its own endpoint.
---

# T-TEST test authoring

Use this repository's public API and recipes, not APIs borrowed from tSQLt.
All paths below are Markdown links relative to this skill; commands run from the
repository root using the current platform's filesystem path conventions.

## 1. Read the contract and choose a test shape

Read the changed code, existing neighboring tests and the relevant
[API section](../../../docs/api.md). Load only the needed recipe:

| Situation | Shape | Recipe |
|---|---|---|
| Fixed invariant, boundary or a distinct query context | Static procedure | [Static tests](../../../docs/static-test-recipes.md) |
| Multiple paired inputs and independent expected outputs | Parameterized procedure plus `test.vector` calls | [Data-driven tests](../../../docs/data-test-recipes.md) |
| Independent parameter domains where every combination is meaningful | Parameterized procedure plus `test.dimension` calls | [Dimension tests](../../../docs/dimension-test-recipes.md) |

Vectors and dimensions describe case generation, not which assertion to use.
A vector can check schemas, values or both. Do not turn paired input/expected values
into dimensions: their Cartesian product would create incorrect expectations.
Explicit vectors add cases to dimension products; they do not multiply the product.

Generalize cases that differ only in inputs. Keep JOIN, CTE, derived-table, PIVOT,
empty-input and ordering contexts when the context itself is the contract.
Do not remove WHERE clauses or rewrite contexts merely to fit a simpler template.

## 2. Select the assertion that proves the requirement

| Requirement | API |
|---|---|
| Scalar value or ordered JSON comparison | `test.assert_equals` |
| FLOAT comparison with an explicit absolute tolerance | `test.assert_float_equals` |
| SQL NULL or non-NULL | `test.assert_null` / `test.assert_not_null` |
| Two queries have matching column names, order and types | `test.assert_query_schemas_equal` |
| A query matches an independently specified schema signature | `test.assert_schema_signature` |
| Two SELECTs return matching data | `test.assert_resultset_equals` |
| Expected exception | `test.assert_error` inside CATCH; use the recipe's missing-error sentinel |

Assertions are procedures: call them with `EXEC`. `is_*` functions return bit and do
not fail a test themselves. Use canonical `test.is_equal`, not its `is_equals` alias.
Compute function expressions into variables before passing values to procedure calls.
For NULL assertions, use the explicit binary conversion shown in the recipe.
`assert_equals` follows SQL collation/padding rules and has a limited numeric shortcut;
it is not byte-exact equality. Read its limits before testing text or decimal precision.

Schema equality does not verify values, row counts, nullability or collation.
Use both schema and result assertions when a transformation must preserve or change
metadata and produce correct values; a same-type REPLACE needs the value check.

## 3. Write independent, readable Arrange / Act / Assert

Put declarations and boilerplate before the three blank-separated sections:
`-- Arrange`, `-- Act`, `-- Assert`. An empty Arrange contains `--N/A`.
Arrange prepares independent expectations; Act exercises the behavior; Assert verifies it.
Never calculate an expected value by repeating the implementation under test.
Never generate expected SELECT columns from the actual query or catalog metadata.

For recipe documentation, put exactly two explanatory helper bullets immediately
before each SQL example. Explain what the custom APIs do before presenting code.

## 4. Register through the public API, not storage tables

Framework procedures live in `test`. Test procedures may live in `tests` or a sample
schema. Do not invent `tests.add_vector`, `text.vector` or tSQLt APIs.

- `test.vector(@test_name, @arguments_sql)` appends one complete trusted SQL argument
  list. It does not execute the test, create the store or reset previous vectors.
  Repeated registrations append duplicate cases unless the runner resets its own test.
- `test.dimension(@test_name, @parameter_name, @values_json)` defines one independent
  domain. Repeating that domain is an error, not an append. Read its limits and required
  caller-owned table setup in the dimension recipe.
- `test.set_registration_scope` selects storage but creates and clears nothing.
  Fabric uses global storage only; do not add session-context branches to Fabric-only
  samples. SQL Server session stores must be created in the outer calling batch.
- `test.clear_registrations @test_name = ...` clears only that test's vectors and domains.
  Do not use a bare/global-wide reset in samples: it deletes other users' cases.
- `test.run` executes saved cases. A required-parameter procedure needs registrations;
  merely installing its definition does not supply inputs.

Select test-procedure containers with `@test_schemas` and individual names/patterns
with `@test_names`. `@test_object_schemas` filters parsed tested-object schemas,
not test containers. Read the runner API before changing selectors.

Do not INSERT, UPDATE or DELETE registry tables from sample authoring code.
Internal storage regression fixtures may seed or inspect rows deliberately; this is
not a pattern to copy into samples. Missing stores can warn and skip registration:
verify setup and the planned/executed cases instead of treating a clean command exit
as proof that every case ran.

`@arguments_sql` is SQL code, not JSON or untrusted input. Serialize actual literal
values, not references to caller-local variables. Keep expected columns on one line
even when long; align case label, expected columns and tested expression.
Use `N` prefixes when Unicode requires them, not automatically for ASCII-only arguments.

This declaration illustrates the installed SELECT-star schema test, not a complete
setup script. Follow the paired runner for scope, reset and complete case registration:

```sql
SET QUOTED_IDENTIFIER OFF;
EXEC test.vector @test_name = '[select_star].[test]',
    @arguments_sql = "
        'ID projection',
        'object_id, principal_id, schema_id, parent_object_id',
        '* LIKE ''%[_]id'''";
SET QUOTED_IDENTIFIER ON;
```

Double quotes delimit the argument-list string only with `QUOTED_IDENTIFIER OFF`.
Single quotes inside its SQL values still need doubling. Define modules with
`QUOTED_IDENTIFIER ON` and restore ON after readable vector declarations.

## 5. Keep sample installation and execution separate

For sample packages, installers define procedures and retire only replaced definitions.
Paired run scripts select scope, reset only their own tests, declare vectors with
`EXEC test.vector`, then call `test.run`. Repeating setup must not duplicate cases or
erase unrelated registrations. Never register vectors inside the test being executed.
Do not change the root installer's basic verification or existing framework installer
contracts while authoring samples.

Use [SELECT-star definitions](../../../tests/samples/select-star/install-select-star-tests.sql)
and [its runner](../../../tests/samples/select-star/run-select-star-tests.sql) as the
readable paired-input example. `select_star.test` checks schemas over `sys.objects s`.
`select_star.test_data` checks schemas and values on the stable `test.run` catalog row.
Both accept case label, expected columns and star expression. Keep the correlated
subquery's own filter and the data test's single-row filter.

## 6. Validate on the correct engine and report only observed results

Schema assertions create temporary metadata-probe views, require view permissions
and do not execute SELECT rows. Read their view-compatible query restrictions.
Result comparisons execute queries separately and compare ordered JSON: use stable
input and explicit ordering when comparing multiple rows.

`assert_resultset_equals` uses scalar FOR JSON capture. Its native behavior is tested,
but Warehouse documentation restricts FOR JSON in subqueries; a native pass does not
prove that data path works on Fabric. Do not silently replace a required value assertion
with a schema-only assertion. Do not add transactions or unsupported SET statements
on the assumption that T-TEST provides tSQLt-style automatic isolation.

Use the smallest existing check covering the change. For a full local release check,
run the existing harness with an explicitly supplied endpoint:

```powershell
.\tests\regression\run-regression-tests.ps1 -Server '<server>' -MutationChecks
```

It creates and drops only its own fresh database. Do not substitute a shared database,
reuse an existing database, or run destructive setup there. Fabric-only operators
require a Fabric endpoint; without one, distinguish definition/input checks from
actual execution. Documentation-only changes need documentation/skill validation,
not a database run.

Before completion, confirm the intended scenarios remain, both positive and meaningful
negative expectations are covered, the runner's case counts match its registrations,
and documentation uses the actual API. Never invent a line/branch coverage percentage.
