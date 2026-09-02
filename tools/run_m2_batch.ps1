#Requires -Version 5.1
<#
.SYNOPSIS
    Bounded-retry batch driver for the M2 staged acceptance verifier
    (round-8 R8-F2; rules v1.5 section 2 rule 7).

.DESCRIPTION
    Runs verify_m2_round4_closure as a per-stage MATLAB -batch process:

        init -> c1c2stale -> c2clean -> c3 -> c5 -> contract -> report

    Retry semantics (rules v1.5, matching the verifier's own gates):

    * The AUTHORITATIVE success signal is a FRESH evidence marker for
      the attempt: a done file (or, for report, a new archive
      directory) whose LastWriteTime is later than the attempt's own
      start time. A marker left over from an earlier run can never
      mask a real crash.
    * The process exit code is ADVISORY ONLY and is recorded in the
      logs and status lines. Live case results/batch_runs/
      20260902_225209: the R2022b heap corruption (0xc0000374) killed
      a c2clean child mid-stage and the matlab.exe launcher still
      exited 0 -- so "rc==0 but no fresh done" is a RETRYABLE crash
      outcome, never a pass.
    * An attempt that leaves NO fresh marker (any exit code) is
      retried as a FULL re-execution from stage entry (the verifier
      bumps its persistent <stage>.attempts counter at entry;
      timestamped trial archives make partial-state reuse impossible).
    * A NONZERO exit WITH a fresh marker is a crash AFTER the evidence
      was atomically complete -- harmless, the batch continues (rules
      v1.5 rule 7e).
    * Retries are bounded by -MaxAttempts (default 3). A deterministic
      failure exhausts the budget and ABORTS the batch with all
      attempt logs kept. The verifier independently refuses an
      over-budget stage entry (air:M2Verify:AttemptBudget), and the
      authoritative bound is manifest.maxAttempts written by init --
      keep this default in lockstep with it.

    Every attempt's full console output is archived to

        results/batch_runs/<yyyyMMdd_HHmmss>/<stage>.attempt<N>.log

    Driver-level behavior is covered by tools/test_m2_batch_driver.ps1
    (retry classes, marker freshness, launcher-rc distrust and the
    report archive-directory evidence check), which dot-sources this
    file with -SourceOnly.

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

function Test-FreshEvidence {
    # True when the attempt produced fresh evidence: a done file newer
    # than $t0 ($DoneFile), or -- for report -- at least one NEW
    # archive directory under $DoneDir newer than $t0. Old markers can
    # never satisfy either check.
    param([string]$DoneFile, [string]$DoneDir, [datetime]$T0)
    if ($DoneFile) {
        return ((Test-Path $DoneFile) -and ((Get-Item $DoneFile).LastWriteTime -gt $T0))
    }
    if ($DoneDir) {
        $fresh = Get-ChildItem $DoneDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -gt $T0 }
        return [bool]$fresh
    }
    return $false
}

function Invoke-StageWithRetry {
    # Core bounded-retry loop, kept free of MATLAB specifics so the
    # driver tests can exercise it with mock stage commands.
    #   $Invoke: scriptblock { param($logPath) ...; return <exit code> }
    #   $DoneFile: stage evidence marker file; $null for rc-only stages.
    #   $DoneDir: alternative marker -- a NEW subdirectory under this
    #      path counts as fresh evidence (report's archive).
    # Returns the successful attempt number (1-based).
    param(
        [string]$Name,
        [scriptblock]$Invoke,
        [string]$DoneFile,
        [string]$DoneDir,
        [int]$Max,
        [string]$LogDir
    )
    for ($i = 1; $i -le $Max; $i++) {
        $log = Join-Path $LogDir ($Name + '.attempt' + $i + '.log')
        $t0 = Get-Date
        $rc = & $Invoke $log
        if ((Test-FreshEvidence -DoneFile $DoneFile -DoneDir $DoneDir -T0 $t0)) {
            if ($rc -eq 0) {
                Write-Host ("{0}: PASS (rc=0, attempt {1})" -f $Name, $i)
            }
            else {
                Write-Host ("{0}: PASS with post-stamp crash (rc={1}, fresh evidence marker; harmless per rules v1.5 rule 7e)" -f $Name, $rc)
            }
            return $i
        }
        if (-not $DoneFile -and -not $DoneDir -and $rc -eq 0) {
            # rc-only stage (none in the default plan): exit code is all
            # there is; 0 means success.
            Write-Host ("{0}: PASS (rc=0, attempt {1})" -f $Name, $i)
            return $i
        }
        # No fresh evidence: retry whatever the exit code says. The
        # launcher can exit 0 on a heap-corrupted child (live case
        # 20260902_225209); the missing fresh marker is authoritative.
        Write-Host ("{0}: attempt {1} rc={2}, no fresh evidence marker -> full re-execution from stage entry" -f $Name, $i, $rc)
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
$archRoot = Join-Path $RepoRoot 'results\round4_closure'
$plan = @()
$plan += @{ name = 'init'; done = (Join-Path $StagedDir 'manifest.mat') }
foreach ($s in $simStages) {
    $plan += @{ name = $s; done = (Join-Path $StagedDir ($s + '.done.mat')) }
}
# report's evidence is the archive directory it writes; a NEW directory
# under results\round4_closure fresher than the attempt start counts as
# the done marker (the launcher's exit code alone cannot be trusted,
# live case 20260902_225209).
$plan += @{ name = 'report'; done = $null; doneDir = $archRoot }

foreach ($p in $plan) {
    if ($Stages -notcontains $p.name) { continue }
    $stageArg = "verify_m2_round4_closure('" + $p.name + "')"
    $doneFile = $p.done
    $doneDir = $p.doneDir
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
    Invoke-StageWithRetry -Name $p.name -Invoke $invoke -DoneFile $doneFile -DoneDir $doneDir -Max $MaxAttempts -LogDir $LogRoot | Out-Null
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
