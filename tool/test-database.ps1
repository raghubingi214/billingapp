[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9_-]+[.]sql$')]
    [string]$Fixture = 'customer_ledger.sql',
    [switch]$PrepareOnly,
    [switch]$KeepDatabase
)

$ErrorActionPreference = 'Stop'
$cliVersion = '3.0.0'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$fixturePath = Join-Path $repositoryRoot "supabase/tests/$Fixture"
if (-not (Test-Path -LiteralPath $fixturePath -PathType Leaf)) {
    throw "Fixture does not exist: $Fixture"
}
$npxCommand = Get-Command npx -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $npxCommand) {
    throw 'Node.js/npm is required to run the pinned Supabase CLI.'
}
$npxExecutable = $npxCommand.Source
$runId = [guid]::NewGuid().ToString('N')
$projectId = 'billingapp-validation-' + $runId.Substring(0, 12)
$runDirectory = Join-Path $repositoryRoot ".local-db-validation/$runId"
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

function Invoke-ValidationCli {
    param([string[]]$CliArguments)
    & $npxExecutable --yes "supabase@$cliVersion" @CliArguments
    if ($LASTEXITCODE -ne 0) {
        throw "Local Supabase command failed: $($CliArguments[0]) $($CliArguments[1])"
    }
}

Invoke-ValidationCli -CliArguments @('init', '--workdir', $runDirectory, '--yes')
$configPath = Join-Path $runDirectory 'supabase/config.toml'
$configText = Get-Content -LiteralPath $configPath -Raw
if ([regex]::Matches($configText, '(?m)^project_id\s*=').Count -ne 1) {
    throw 'Unexpected generated Supabase configuration: project_id is not unique.'
}
$configText = $configText -replace '(?m)^project_id\s*=.*$', "project_id = `"$projectId`""
Set-Content -LiteralPath $configPath -Value $configText -Encoding utf8
$migrationDirectory = Join-Path $runDirectory 'supabase/migrations'
New-Item -ItemType Directory -Path $migrationDirectory -Force | Out-Null

# Match the tracked deployment baseline. Entitlement activation 042 is explicitly
# held back; do not silently activate it while validating an unrelated export.
$heldMigration = '202611050042_subscription_commands.sql'
if (-not (Test-Path -LiteralPath (Join-Path $repositoryRoot "supabase/migrations/$heldMigration"))) {
    throw 'The held entitlement migration changed. Review the baseline before running SQL validation.'
}
$migrationFiles = Get-ChildItem -LiteralPath (Join-Path $repositoryRoot 'supabase/migrations') -File -Filter '*.sql' |
    Where-Object { $_.Name -ne $heldMigration } | Sort-Object Name
foreach ($migrationFile in $migrationFiles) {
    Copy-Item -LiteralPath $migrationFile.FullName -Destination $migrationDirectory
}
Write-Host "Prepared isolated project $projectId with $($migrationFiles.Count) migrations."
Write-Host 'Migration 042 is excluded; this run cannot prove entitlement activation.'
Write-Host "Configuration: $configPath"
if ($PrepareOnly) { return }

# No link command, --remote argument, hosted URL, or app .env is used here.
# Cleanup targets only this invocation's unique project, never --all.
$databaseAttempted = $false
try {
    $databaseAttempted = $true
    Invoke-ValidationCli -CliArguments @('db', 'start', '--workdir', $runDirectory)
    Invoke-ValidationCli -CliArguments @('db', 'reset', '--workdir', $runDirectory, '--no-seed', '--yes')
    # The CLI query command prepares one statement. Fixtures contain transactions
    # and DO blocks, so execute the script with psql in this exact local container.
    $databaseContainer = "supabase_db_$projectId"
    & docker cp $fixturePath "${databaseContainer}:/tmp/billingapp-fixture.sql"
    if ($LASTEXITCODE -ne 0) { throw 'Unable to copy fixture into the isolated database container.' }
    & docker exec --user postgres $databaseContainer psql --username postgres --dbname postgres --set ON_ERROR_STOP=1 --file /tmp/billingapp-fixture.sql
    if ($LASTEXITCODE -ne 0) { throw "SQL fixture failed: $Fixture" }
    Write-Host "SQL fixture passed: $Fixture"
}
finally {
    if ($databaseAttempted -and -not $KeepDatabase) {
        Invoke-ValidationCli -CliArguments @('stop', '--project-id', $projectId, '--workdir', $runDirectory, '--no-backup')
    }
    elseif ($KeepDatabase) {
        Write-Host "Retained local project: $projectId"
        Write-Host "Stop it using the pinned CLI with stop --project-id $projectId --workdir $runDirectory --no-backup"
    }
}
