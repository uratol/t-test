# T-TEST

A **lightweight, pure‑T‑SQL unit‑testing framework** for SQL Server. Drop‑in installation, zero external dependencies, CI‑friendly output.

---

## ✨ Features

* **100 % T‑SQL** – no CLR, PowerShell or external test runner required.
* **Self‑discovering tests**: every procedure in the `tests` schema is a test.
* **Rich assertions**:

  * smart equality (`NULL`, numbers, dates, JSON – order‑insensitive)
  * error pattern matching
  * null / not‑null shortcuts
* **Transactional isolation** – write tests as `BEGIN TRAN / ROLLBACK` so production data is never touched.
* **Minimal footprint** – just helper functions in `test` schema and a view + runner.
* **CI‑ready** – `test.run` prints a concise summary and raises on failure, giving your pipeline a non‑zero exit code.

---

## 🚀 Quick start

### 1. Install

Simply execute the included **install.sql** script in the database you want to test:

```sql
:r install.sql
```

The script creates two schemas:

| Schema  | Purpose                                                |
| ------- | ------------------------------------------------------ |
| `test`  | framework internal objects: runner, assertions, logger |
| `tests` | **your** test procedures live here                     |

### 2. Write a test

Create a stored procedure inside `tests`. The procedure name encodes the object you test:

```
[tests].[<schema>.<object>][@<action>]
```

* `<schema>` – schema of the object under test (e.g. `sales`)
* `<object>` – object name (`usp_create_order`)
* `@<action>` – *optional* scenario / edge‑case tag

Example:

```sql
CREATE OR ALTER PROCEDURE [tests].[sales.usp_create_order@happy_path]
AS
BEGIN TRAN
    ------------------------------------------------------------------
    -- arrange
    DECLARE @customer_id int = 1;
    DECLARE @order_id   int;

    -- act
    EXEC @order_id = sales.usp_create_order @customer_id;

    -- assert
    SELECT test.assert_not_null('Order id must be generated',
                                @order_id);
ROLLBACK;
```

Any uncaught exception fails the test automatically.

### 3. Run all tests

```sql
EXEC test.run;      -- run everything
```

You will see something like:

```
################################################################################################
Running [tests].[sales.usp_create_order@happy_path]
INFO: 1 tests of 3 executed. Succeeded: 1, failed: 0, errors: 0
```

If any test fails `test.run` will `THROW`, making `sqlcmd`/CI step fail.

---

## 📚 Test examples

### 1. Basic equality assertion

```sql
CREATE OR ALTER PROCEDURE [tests].[math.add@positive]
AS
BEGIN TRAN
    DECLARE @result int;

    EXEC @result = math.add @a = 20, @b = 22;

    -- Should return 42
    SELECT test.assert_equals('20 + 22 must be 42', '42', CAST(@result AS nvarchar(max)));
ROLLBACK;
```

### 2. JSON order‑independent comparison (no temp variables needed)

```sql
CREATE OR ALTER PROCEDURE [tests].[api.get_users@ordering]
AS
BEGIN TRAN
    /*
       Compare the JSON produced by the procedure directly with the expected
       literal – no @expected/@actual temp vars necessary because helpers are
       **functions**.
    */
    SELECT test.assert_equals(
        'Users JSON must match ignoring order',
        (
            SELECT *
            FROM (VALUES (1, N'Ann'), (2, N'Bob')) v(id, name)
            FOR JSON PATH
        ),
        (SELECT * FROM dbo.get_users() FOR JSON PATH)
    );
ROLLBACK;
```

### 3. Exception handling

```sql
CREATE OR ALTER PROCEDURE [tests].[test.throw@message_and_proc]
AS
BEGIN TRAN
    BEGIN TRY
        EXEC test.throw @message = 'Test exception!' , @proc_id = @@procid;

        -- Sentinel helper – forces failure if exception was **not** thrown
        EXEC test.error;
    END TRY
    BEGIN CATCH
        -- Validate message text
        SELECT test.assert_error_like('Thrown exception should contain the message', 'Test exception!%');

        -- Validate procedure tag
        SELECT test.assert_error_like(
            'Thrown exception should contain the called procedure name separated by <Procedure:> tag',
            CONCAT('%', '<Procedure:>', '%', QUOTENAME(OBJECT_SCHEMA_NAME(@@procid)), '.', QUOTENAME(OBJECT_NAME(@@procid)), '%')
        );
    END CATCH;
ROLLBACK;
```

---

## 🛠 Assertion toolbox

| Helper                                      | Purpose                                                        | Example                                                               |
| ------------------------------------------- | -------------------------------------------------------------- | --------------------------------------------------------------------- |
| `test.assert_equals(msg, expected, actual)` | smart equality check (numbers, JSON, etc.)                     | `test.assert_equals('Should be 42', '42', @val)`                      |
| `test.assert_error_like(msg, pattern)`      | assert previously raised error message                         | `test.assert_error_like('Should complain about PK', '%PRIMARY KEY%')` |
| `test.assert_not_null(msg, value)`          | value **must** be NOT NULL                                     |                                                                       |
| `test.assert_null(msg, value)`              | value **must** be NULL                                         |                                                                       |
| `test.fail(msg)`                            | fail immediately, you can add your conditions in WHERE section | SELECT `test.fail('Not implemented')` WHERE IsAdmin(@my\_profile) = 0 |
|                                             |                                                                |                                                                       |

---

## ⚙️ Runner options

```sql
EXEC test.run
      @test_names        = N'[tests].[sales.usp_create_order@happy_path]|[tests].[sales.*]',
      @exclude_test_names = N'[tests].[obsolete.*]',
      @schemas            = N'sales,inventory',
      @exclude_schemas    = N'legacy',
      @limit_failed       = 5,              -- stop after 5 failures
      @before_callback    = N'SET NOCOUNT ON',
      @log_proc_name      = N'test.log';
```

| Parameter                       | Default      | Description                                                         |
| ------------------------------- | ------------ | ------------------------------------------------------------------- |
| `@test_names`                   | `NULL`       | Pipe‑separated list of fully‑qualified test procedures to *include* |
| `@exclude_test_names`           | `NULL`       | Pipe‑separated list to *exclude*                                    |
| `@schemas` / `@exclude_schemas` | `NULL`       | Filter by *tested object* schema (not test schema)                  |
| `@limit_failed`                 | `1 000 000`  | Fail‑fast after N failures                                          |
| `@before_callback`              | `NULL`       | T‑SQL executed before each test (e.g. `DBCC DROPCLEANBUFFERS`)      |
| `@log_proc_name`                | `'test.log'` | Plug‑in alternative logger                                          |

---

## 📝 Logging

`test.log` standardises messages (`DEBUG`, `INFO`, `WARNING`, `ERROR`). Pass contextual data via `%1..%4` placeholders:

```sql
EXEC test.log @message = 'Imported %1 rows', @p1 = @@ROWCOUNT, @severity = 'info';
```

Feel free to swap it with your own implementation and point `test.run` to it.

---

## 🤖 CI integration

Add a job after your migration step:

```yaml
- task: SqlAzureDacpacDeployment@1
  inputs:
    sqlFile: migrations.sql
    # …
- script: sqlcmd -b -S $(DbServer) -d $(Db) -i sql/run_tests.sql
  displayName: "Run T‑SQL unit tests"
```

* `-b` makes `sqlcmd` exit with non‑zero code on `THROW`, so the pipeline fails if tests fail.

---

## 🔄 T-TEST vs. tSQLt

| Area                                       | T-TEST                                                                                                                                                                                                                            | tSQLt                                                                                                                                                               | Take‑away                                                                                     |
| ------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| **Installation size**                      | single script, < 10 KB of objects in `test` & `tests` schemas                                                                                                                                                                     | \~700 KB, dozens of objects spread across multiple helper schemas (`tSQLt`, `tSQLtPrivate`, etc.)                                                                   | T-TEST is tiny & vendor‑free; tSQLt is feature‑rich but heavy                                 |
| **How recordsets are compared**            | `test.assert_equals` does *smart* binary/JSON/decimal equality – often one line                                                                                                                                                   | `tSQLt.AssertEqualsTable` requires creating an *expected* table variable and `tSQLt.ExpectResultSets` with XML                                                      | T-TEST is terser; tSQLt is explicit but verbose                                               |
| **Service Broker & SQL Agent job testing** | Works seamlessly: each test opens its own `BEGIN TRAN` so dialogs, job runs, messages happen inside the same transaction and are rolled back                                                                                      | Standard pattern uses `EXEC tSQLt.NewTestClass` which wraps an *outer* transaction; Service Broker & job threads run **outside** it, often making assertions tricky | T-TEST 🟢; tSQLt requires extra harness or disabling transactions                             |
| **Test classification**                    | Test procedure name encodes target: `[tests].[schema.object@scenario]` ⇒ quick filtering by schema/object                                                                                                                         | Uses *test classes* (schemas) + procedure name – extra level, but cleaner separation                                                                                | Depends on taste; T-TEST needs no helper commands to create classes                           |
| **Execution flexibility**                  | `test.run` accepts *include / exclude* lists, schema filters, fail‑fast limit, callback hook                                                                                                                                      | `EXEC tSQLt.Run` runs all or a single class; finer filtering requires PowerShell or wrapper scripts                                                                 | T-TEST offers more granular selection out‑of‑the‑box                                          |
| **Helpers & exception handling**           | Helpers are **functions** – they can be called inline (`SELECT test.assert_equals(...)`) and accept expressions / sub‑queries as parameters. Dedicated `test.error` & pattern‑based `test.assert_error_like` for error validation | Helpers are *procedures*. Need temp tables / variables for passing data; exception tests rely on `tSQLt.ExpectException` with hard‑coded numbers                    | Functions inline ⇒ less boilerplate. tSQLt procedures support output capture but add ceremony |
| **Mocking / Isolation**                    | Uses your own `BEGIN TRAN / ROLLBACK`; no automatic fake tables                                                                                                                                                                   | Rich mocking: fake tables, spy procedures, `tSQLt.FakeTable`, `tSQLt.SpyProcedure`                                                                                  | tSQLt wins for complex mocks                                                                  |
| **Dependencies**                           | None (pure T‑SQL)                                                                                                                                                                                                                 | CLR enabled (for NUnit‑style output) on older versions, external installer                                                                                          | T-TEST easier on locked‑down servers                                                          |

**When to prefer T-TEST**

* You want a *minimal* framework that piggybacks on plain T‑SQL and works in any environment (Azure SQL DB, managed instances, on‑prem).
* Your primary pain‑point is **assertion verbosity** rather than advanced mocking.
* You need to test **Service Broker conversations or SQL Agent jobs** inside the same transaction.

**When to stick to tSQLt**

* You rely on its **fake tables / spy procedures** for heavy isolation or mocking.
* You need its **code‑coverage hooks** or integration with existing tSQLt‑based test suites.

---

## 📄 License

[MIT](LICENSE)

---

## 🤝 Contributing

1. Fork / create a feature branch.
2. Add or update tests inside `tests` schema.
3. Ensure `EXEC test.run` passes.
4. Submit a PR.

Feel free to open issues for bugs or feature requests.

---
