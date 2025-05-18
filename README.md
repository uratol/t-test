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

The script will:

1. **Create two schemas** that hold the framework internals and your tests (see table below).
2. \*\*Immediately execute \*\***`EXEC test.run`** at the end, running the built‑in sanity checks bundled with T‑TEST.
   You’ll see a short summary like `INFO: 4 self‑tests executed. Succeeded: 4, failed: 0`—proof the installation is good.
   Feel free to comment out that line inside *install.sql* if you want to postpone the first run.

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

#### Why wrap tests in a `BEGIN TRAN / ROLLBACK`

> **Most T‑TEST samples open a transaction at the very top and roll it back at the end.**
>
> • **Self‑contained execution** – you (or CI) can simply `EXEC [tests].[…]` and the procedure cleans up after itself, leaving no side‑effects.
>
> • **Transaction‑aware flows** – Service Broker dialogs, SQL Agent jobs started with `sp_start_job`, and any trigger‑spawned work all participate in the same transaction, so you can assert on their behaviour *before* the rollback.
>
> • **Zero data pollution** – production tables remain untouched even if the test inserts millions of rows.

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

### Run tests

T‑TEST provides two convenient ways to execute your tests:

1. Via the runner **\[test].\[run]**
2. **By calling the test procedure directly**

#### 1. Using `test.run`

```sql
-- run absolutely everything
EXEC test.run;

-- run only tests that target objects in the sales schema
EXEC test.run @schemas = N'sales';

-- run a specific test and stop on first failure
EXEC test.run
      @test_names        = N'[tests].[sales.usp_create_order@happy_path]|[tests].[inventory.adjust_stock@edge_case]',
      @exclude_test_names = N'[tests].[obsolete.some_legacy_test]',
      @schemas            = N'sales,inventory',
      @exclude_schemas    = N'legacy',
      @limit_failed       = 5,              -- stop after 5 failures
      @before_callback    = N'SET NOCOUNT ON',
      @log_proc_name      = N'test.log';

```

`test.run` prints a concise summary and **throws** if any test fails, giving `sqlcmd` or your CI pipeline a non‑zero exit code:

```
################################################################################################
Running [tests].[sales.usp_create_order@happy_path]
INFO: 5 tests executed. Succeeded: 5, failed: 0, errors: 0
```

#### 2. Executing a test procedure directly

Because most tests are wrapped in `BEGIN TRAN / ROLLBACK`, you can execute a single test in SSMS without leaving data behind:

```sql
EXEC [tests].[sales.usp_create_order@happy_path];
```

Perfect for quick debugging and exploratory runs.

---

## 🔒 Transactions: when to wrap and when to skip

Most T‑TEST samples begin with `BEGIN TRAN … ROLLBACK`. **Why?**

1. **Run individual tests ad‑hoc** – You can execute a single test procedure in SSMS and be sure nothing sticks in the database after the rollback.
2. **Keep CI databases clean** – The test runner doesn’t need to issue explicit rollbacks; each test is self‑contained.
3. **Isolation = repeatability** – Data written by one test never pollutes the next run.

### When *not* to start a manual transaction

Some behaviours depend on a real commit:

* **Service Broker conversations** – activation procedures, queue processing, and message delivery only fire after the outer transaction commits.
* **SQL Agent jobs / sp\_start\_job** – the job executes in a separate session; wrapping the call in a transaction may postpone it indefinitely.
* **Trigger / CDC / replication side‑effects** – if your assertion needs to observe them *after* commit.

For such scenarios simply omit `BEGIN TRAN` / `ROLLBACK` and let your test clean up explicitly or run against disposable test data.

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

### 2. Recordset comparison (no temp tables needed)

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
        'Users must match',
        (
            SELECT *
            FROM (VALUES (1, N'Ann'), (2, N'Bob')) v(id, name)
            FOR JSON PATH
        ),
        (SELECT * FROM dbo.get_users() FOR JSON PATH)
    );
ROLLBACK;
```

### 3. Exception handling (real object)

```sql
CREATE OR ALTER PROCEDURE [tests].[sales.usp_create_order@invalid_customer]
AS
BEGIN TRAN
    BEGIN TRY
        -- Call the object under test which is *expected* to raise
        EXEC sales.usp_create_order @customer_id = -1;  -- invalid id triggers validation error
    END TRY
    BEGIN CATCH
        -- Assert that the error message contains the expected text
                SELECT test.assert_error_like(
            'Should report invalid customer id',
            '%invalid customer%'
        );

        SELECT test.assert_error_number(
            'Should raise validation error number',
            50001
        );
    END CATCH;
ROLLBACK;
```

### 4. Inline `test.fail` inside a `WHERE` clause Inline `test.fail` inside a `WHERE` clause

```sql
CREATE OR ALTER PROCEDURE [tests].[security.is_admin@assert_role]
AS
BEGIN TRAN
    /*
       Fail the test *only* when the condition is true.
       Here we assert that the current login must belong to the db_owner role.
    */
    SELECT test.fail('Current login must be a member of db_owner')
    WHERE IS_MEMBER('db_owner') = 0;
ROLLBACK;
```

````

---

## 🛠 Assertion toolbox

| Helper                                      | Purpose                                                        | Example                                                               |
| ------------------------------------------- | -------------------------------------------------------------- | --------------------------------------------------------------------- |
| `test.assert_equals(msg, expected, actual)` | smart equality check (numbers, JSON, etc.)                     | `test.assert_equals('Should be 42', '42', @val)`                      |
| `test.assert_error_like(msg, pattern)`      | assert previously raised error message                         | `test.assert_error_like('Should complain about PK', '%PRIMARY KEY%')` |
| `test.assert_error_number(msg, expected_number)` | assert error **number** inside CATCH block                     | `test.assert_error_number('Should raise 50001', 50001)` |
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
````

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

##
