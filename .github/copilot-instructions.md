# T-TEST repository guidance

For creating or refactoring SQL tests, load the repository `t-test` skill in
[SKILL.md](skills/t-test/SKILL.md). Read the relevant recipe and public API before editing.

- Framework APIs live in `test`; `tests` and sample schemas contain test procedures.
  Use existing names, including `test.vector` and `test.dimension`.
- Declare sample vectors with `EXEC test.vector`, never direct registry-table writes.
  Direct registry access belongs only to framework internals and deliberate regression
  fixtures that inspect or exercise storage behavior.
- Sample installers define procedures; their paired runners perform targeted reset,
  registration and execution. Preserve the root installer's basic verification and
  existing framework-package behavior; do not rewrite them to match a sample.
- Preserve independent expectations, Arrange / Act / Assert and existing scenarios.
  Generalize repeated inputs without removing the behavior a case tests.
- Distinguish SQL Server checks from Fabric Warehouse execution. Never claim a Fabric
  run or measured coverage from native/static checks alone.

Keep [the API reference](../docs/api.md) and human-readable recipes authoritative.
The skill guides their use; it does not replace them.
