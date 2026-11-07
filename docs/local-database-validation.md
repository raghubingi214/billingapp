# Local SQL validation

Run from PowerShell with Node.js/npm and a working Docker Desktop engine:

```powershell
./tool/test-database.ps1 -Fixture customer_ledger.sql
```

The same script runs in PowerShell on the Linux GitHub runner's `database` job.
That job is intended to validate the migration/fixture independently of the
Windows Docker engine; its result must be checked before claiming a SQL pass.

The script pins Supabase CLI 3.0.0 and generates a unique project under the ignored
`.local-db-validation` directory. It starts local Postgres, resets that isolated
database to the copied migrations without seed scripts, runs the selected SQL
fixture through `psql` with `ON_ERROR_STOP=1` inside that container, then stops and
removes only that invocation's local database volumes.
It never links a project, loads the app `.env`, or passes `--remote`/`--all`.
The CLI can download its local container images on the first database start.

Migration `202611050042_subscription_commands.sql` is deliberately excluded to
match the held entitlement activation in the implementation tracker. All other
current migrations, including the prepared statement export migration 062, are
copied. This validation does not prove entitlement activation or production
compatibility; the hosted project remains separate.

To inspect the configuration and copied migration set without starting Docker:

```powershell
./tool/test-database.ps1 -PrepareOnly
```

To retain the disposable database for investigation, add `-KeepDatabase`. The
script prints its unique project ID and the scoped cleanup command. The generated
configuration files remain under the ignored directory for inspection.

Current evidence: CI started and reset an isolated database, applied all 61
selected migrations (including 062, excluding 042), and cleaned it up. Initial
fixture execution failed because the CLI query command cannot prepare multiple
statements; the runner now uses `psql`, with the fixture now passing in CI run 42264835839.
Windows Docker remains unavailable. No hosted migration was applied.
