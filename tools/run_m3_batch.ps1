#Requires -Version 5.1
<#
.SYNOPSIS
    Bounded-retry batch driver for the M3 staged acceptance chain
    (round-3 M3-R2-F4; rules v1.7 section 2 rules 4-9, reusing the
    in-repo M2 driver discipline).

.DESCRIPTION
    Runs the M3 formal batch and the round-3 closure verifier as
    per-stage MATLAB -batch processes:

        init -> s1..s5 (batch segments) -> aggregate ->
        vunit -> vnegative -> vaggregate -> vreport

    Stage plumbing (all state in the gitignored staged directory under
    results/, so the markers never dirty the source tree):

    * init (m3_batch_init) writes the manifest: the common BATCH id
      (distinct from every segment's own execution runId), the live
      commit, clean-tree gate and SHA-256 of every governance-relevant
      file. The manifest is EVIDENCE: every consumer re-validates it
      against the source contract in m3_batch_contract.m.
    * Each segment entry (run_air_m3_trials via m3_batch_stage) bumps a
      PERSISTENT <seg>.attempts counter (atomic replace) BEFORE any work
      and refuses over-budget execution independently of this driver.
    * A segment writes its done stamp only when it completes AND passes;
      a pass=false segment exits nonzero without a stamp, so the retry
      budget applies and deterministic failures abort the batch.

    Retry semantics (rules v1.7 rule 7, identical to the M2 driver):

    * The AUTHORITATIVE success signal is a FRESH evidence marker for
      the attempt: a done file (or, for aggregate, a new archive
      directory) whose LastWriteTime is later than the attempt's own
      start time. A marker left over from an earlier run can never
      mask a real crash.
    * The process exit code is ADVISORY ONLY. Live case
      results/batch_runs/20260902_225209: the R2022b heap corruption
      (0xc0000374) killed a child mid-stage and the matlab.exe launcher
      still exited 0 -- so "rc==0 but no fresh done" is a RETRYABLE
      crash outcome, never a pass.
    * A NONZERO exit WITH a fresh marker is a crash AFTER the evidence
      was atomically complete -- harmless, the batch continues (7e).
    * Retries are bounded by -MaxAttempts (default 3, kept in lockstep
      with the manifest cap in m3_batch_contract.m). A deterministic
      failure exhausts the budget and ABORTS the batch with all attempt
      logs kept.

    LOG ENCODING (rule 9): MATLAB -batch writes its console output in
    the system ANSI code page (probe 2026-09-03: GBK on this machine).
    Invoke-LoggedNative decodes with the ANSI page explicitly and writes
    the log UTF-8; the driver test asserts a CJK round trip with zero
    U+FFFD.

    Driver-level behavior is covered by tools/test_m3_batch_driver.ps1
    (retry classes, marker freshness, launcher-rc distrust, the
    aggregate archive-directory evidence check and the log-encoding
    round trip), which dot-sources this file with -SourceOnly.

.EXAMPLE
    powershell -File tools\run_m3_batch.ps1
    powershell -File tools\run_m3_batch.ps1 -MaxAttempts 3
    powershell -File tools\run_m3_batch.ps1 -Stages init,s1,s2,s3,s4,s5,aggregate
#>
param(
    [int]$MaxAttempts = 3,
    [string]$Matlab = 'matlab',
    [string]$LogRoot = '',
    [string[]]$Stages = @('init', 's1', 's2', 's3', 's4', 's5', 'aggregate', 'vunit', 'vnegative', 'vaggregate', 'vreport'),
    [switch]$SourceOnly
)

$script:RepoRoot = Split-Path -Parent $PSScriptRoot
$script:AdapterDir = Join-Path $RepoRoot 'models\px4_x8'

function Test-FreshEvidence {
    # True when the attempt produced fresh evidence: a done file newer
    # than $t0 ($DoneFile), or -- for aggregate -- at least one NEW
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
    #      path counts as fresh evidence (aggregate's archive).
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
                Write-Host ("{0}: PASS with post-stamp crash (rc={1}, fresh evidence marker; harmless per rules v1.7 rule 7e)" -f $Name, $rc)
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

function Invoke-LoggedNative {
    # Rule 9: run a native command and write its full console output to
    # a UTF-8 log, decoding the command's output with the system ANSI
    # code page (MATLAB -batch emits ANSI-page bytes on a pipe; probe
    # 2026-09-03). Returns the exit code.
    param([string]$FilePath, [string[]]$Arguments, [string]$LogPath)
    $saved = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::Default
        & $FilePath @Arguments 2>&1 | Out-File -FilePath $LogPath -Encoding utf8
        $LASTEXITCODE
    }
    finally {
        [Console]::OutputEncoding = $saved
    }
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

$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$stagedDir = Join-Path $RepoRoot ('results\air_m3_batch_staged\' + $stamp)
New-Item -ItemType Directory -Force -Path $stagedDir | Out-Null
Write-Output ("staged dir: " + $stagedDir)

# segment stages (names must match the manifest's canonical s1..s5);
# their done markers live in the staged dir and the attempt counters
# are bumped inside run_air_m3_trials
$segStages = @('s1', 's2', 's3', 's4', 's5')
# verifier stages share the same staged bookkeeping
$vStages = @('vunit', 'vnegative', 'vaggregate', 'vreport')
$archRoot = Join-Path $RepoRoot 'results\air_m3_trials'

$plan = @()
$plan += @{ name = 'init'; done = (Join-Path $stagedDir 'manifest.mat'); cmd = "m3_batch_init('$stagedDir')" }
foreach ($s in $segStages) {
    $plan += @{ name = $s; done = (Join-Path $stagedDir ($s + '.done.mat')); cmd = "m3_batch_stage('$s','$stagedDir')" }
}
# aggregate's evidence is the archive directory it writes; a NEW
# <stamp>_aggregate directory under results\air_m3_trials fresher than
# the attempt start counts as the done marker.
$plan += @{ name = 'aggregate'; done = $null; doneDir = $archRoot; cmd = "m3_batch_aggregate('$stagedDir')" }
foreach ($s in $vStages) {
    $plan += @{ name = $s; done = (Join-Path $stagedDir ($s + '.done.mat')); cmd = "verify_m3_round3_closure('$s','$stagedDir')" }
}

foreach ($p in $plan) {
    if ($Stages -notcontains $p.name) { continue }
    $stageArg = "addpath('$AdapterDir'); " + $p.cmd
    $doneFile = $p.done
    $doneDir = $p.doneDir
    $matlabExe = $Matlab
    $invoke = { param($logPath)
        Invoke-LoggedNative -FilePath $matlabExe -Arguments @('-batch', $stageArg) -LogPath $logPath
    }.GetNewClosure()
    Invoke-StageWithRetry -Name $p.name -Invoke $invoke -DoneFile $doneFile -DoneDir $doneDir -Max $MaxAttempts -LogDir $LogRoot | Out-Null
}

Write-Output 'stage attempts (persistent markers):'
foreach ($s in (@('init') + $segStages + $vStages)) {
    $mk = Join-Path $stagedDir ($s + '.attempts')
    if (Test-Path $mk) {
        Write-Output ("  {0}={1}" -f $s, (Get-Content $mk -Raw).Trim())
    }
}
Write-Output 'BATCH PASS'
exit 0
