#Requires -Version 5.1
<#
.SYNOPSIS
    Bounded-retry batch driver for the M2 staged acceptance verifier
    (round-8 R8-F2; rules v1.5 section 2 rule 7).

.DESCRIPTION
    Runs verify_m2_round4_closure as a per-stage MATLAB -batch process:

        init -> c1c2stale -> c2clean -> c3 -> c5 -> contract -> report

    Retry semantics (rules v1.5, matching the verifier's own gates):

    * A stage attempt whose process exits NONZERO and leaves no FRESH
      done marker is retried as a FULL re-execution from stage entry
      (the verifier bumps its persistent <stage>.attempts counter at
      entry; timestamped trial archives make partial-state reuse
      impossible).
    * "Fresh" means the done marker's LastWriteTime is later than the
      attempt's own start time: a marker left over from an earlier run
      can never mask a real crash.
    * A NONZERO exit WITH a fresh done marker is a crash AFTER the
      evidence was atomically complete -- harmless, the batch
      continues (rules v1.5 rule 7e).
    * Retries are bounded by -MaxAttempts (default 3). A deterministic
      failure exhausts the budget and ABORTS the batch with all
      attempt logs kept. The verifier independently refuses an
      over-budget stage entry (air:M2Verify:AttemptBudget), and the
      authoritative bound is manifest.maxAttempts written by init --
      keep this default in lockstep with it.

    Every attempt's full console output is archived to

        results/batch_runs/<yyyyMMdd_HHmmss>/<stage>.attempt<N>.log

    Driver-level behavior is covered by tools/test_m2_batch_driver.ps1
    (three retry classes + freshness + rc/done consistency), which
    dot-sources this file with -SourceOnly.

.EXAMPLE
    pwsh -File tools\run_m2_batch.ps1
    powershell -File tools\run_m2_batch.ps1 -MaxAttempts 3
#>
param(
    [int]$MaxAttempts = 3,
    [string]$Matlab = 'matlab',
    [string]$LogRoot = '',
    [string[]]$Stages = @('init', 'c1c2stale', 'c2clean', 'c3', 'c5', 'contract', 'report'),
    [switch]$SourceOnly
)

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:AdapterDir = Join-Path $RepoRoot 'models\px4_x8'
$script:StagedDir = Join-Path $RepoRoot 'results\round4_closure_staged'

function Invoke-StageWithRetry {
    # Core bounded-retry loop, kept free of MATLAB specifics so the
    # driver tests can exercise it with mock stage commands.
    #   $Invoke: scriptblock { param($logPath) ...; return <exit code> }
    #   $DoneFile: stage evidence marker; $null for rc-only stages
    #      (init's manifest / report's archive are judged by exit code).
    # Returns the successful attempt number (1-based).
    param(
        [string]$Name,
        [scriptblock]$Invoke,
        [string]$DoneFile,
        [int]$Max,
        [string]$LogDir
    )
    for ($i = 1; $i -le $Max; $i++) {
        $log = Join-Path $LogDir ($Name + '.attempt' + $i + '.log')
        $t0 = Get-Date
        $rc = & $Invoke $log
        if ($rc -eq 0) {
            if ($DoneFile -and -not (Test-Path $DoneFile)) {
                throw ("{0}: attempt {1} exited 0 but the done marker {2} is missing -- inconsistent stage, batch stopped" -f $Name, $i, $DoneFile)
            }
            Write-Host ("{0}: PASS (rc=0, attempt {1})" -f $Name, $i)
            return $i
        }
        if ($DoneFile -and (Test-Path $DoneFile) -and ((Get-Item $DoneFile).LastWriteTime -gt $t0)) {
            Write-Host ("{0}: PASS with post-stamp crash (rc={1}, fresh done marker; harmless per rules v1.5 rule 7e)" -f $Name, $rc)
            return $i
        }
        if ($DoneFile) {
            Write-Host ("{0}: attempt {1} rc={2}, no fresh done marker -> full re-execution from stage entry" -f $Name, $i, $rc)
        }
        else {
            Write-Host ("{0}: attempt {1} rc={2} -> re-execution" -f $Name, $i, $rc)
        }
    }
    throw ("{0}: attempt budget exhausted ({1}); deterministic failure aborts the batch, all attempt logs kept in {2}" -f $Name, $Max, $LogDir)
}

if ($SourceOnly) { return }

if ($MaxAttempts -lt 1 -or $MaxAttempts -gt 10) {
    throw ("MaxAttempts {0} out of the sane range 1..10" -f $MaxAttempts)
}
if (-not $LogRoot) {
    $LogRoot = Join-Path $RepoRoot ('results\batch_runs\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
Write-Output ("batch log dir: " + $LogRoot)

$simStages = @('c1c2stale', 'c2clean', 'c3', 'c5', 'contract')
$plan = @()
$plan += @{ name = 'init'; done = (Join-Path $StagedDir 'manifest.mat') }
foreach ($s in $simStages) {
    $plan += @{ name = $s; done = (Join-Path $StagedDir ($s + '.done.mat')) }
}
$plan += @{ name = 'report'; done = $null }

foreach ($p in $plan) {
    if ($Stages -notcontains $p.name) { continue }
    $stageArg = "verify_m2_round4_closure('" + $p.name + "')"
    $doneFile = $p.done
    $matlabExe = $Matlab
    $adapter = $AdapterDir
    $invoke = { param($logPath)
        Push-Location $adapter
        try {
            & $matlabExe -batch $stageArg 2>&1 | Out-File -FilePath $logPath -Encoding utf8
            $LASTEXITCODE
        }
        finally { Pop-Location }
    }.GetNewClosure()
    Invoke-StageWithRetry -Name $p.name -Invoke $invoke -DoneFile $doneFile -Max $MaxAttempts -LogDir $LogRoot | Out-Null
}

Write-Output 'stage attempts (persistent markers):'
foreach ($s in $simStages) {
    $mk = Join-Path $StagedDir ($s + '.attempts')
    if (Test-Path $mk) {
        Write-Output ("  {0}={1}" -f $s, (Get-Content $mk -Raw).Trim())
    }
}
Write-Output 'BATCH PASS'
exit 0
