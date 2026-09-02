#Requires -Version 5.1
<#
.SYNOPSIS
    Driver-level tests for the bounded-retry batch driver (round-8
    R8-F2; rules v1.5 section 2 rule 7h).

.DESCRIPTION
    Dot-sources tools/run_m2_batch.ps1 with -SourceOnly and exercises
    the ACTUAL Invoke-StageWithRetry core with mock stage commands:

    S1  crash WITHOUT done marker          -> full re-execution, attempt 2 succeeds, both logs kept
    S2  crash AFTER a FRESH done marker    -> harmless, no retry, batch continues
    S3  deterministic failure to the bound -> batch aborts after exactly Max attempts, logs kept
    S4  rc-only stage (no done marker)     -> nonzero re-executes, zero succeeds
    S5  STALE done from an earlier run     -> must NOT mask a crash; retry still happens
    S6  rc=0 without a done marker         -> inconsistent stage, batch stops (throw)

    Run under BOTH PowerShell 7 and Windows PowerShell 5.1:
        pwsh -File tools\test_m2_batch_driver.ps1
        powershell -File tools\test_m2_batch_driver.ps1
#>

$driver = Join-Path $PSScriptRoot 'run_m2_batch.ps1'
. $driver -SourceOnly

$script:Failures = 0
function Assert-True {
    param([bool]$Cond, [string]$Msg)
    if ($Cond) { Write-Host ("PASS: " + $Msg) }
    else { $script:Failures++; Write-Host ("FAIL: " + $Msg) -ForegroundColor Red }
}

$base = Join-Path ([System.IO.Path]::GetTempPath()) ('m2_driver_test_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
New-Item -ItemType Directory -Force -Path $base | Out-Null
Write-Host ("test workspace: " + $base)

# --- S1: nonzero exit without done -> retry; attempt 2 succeeds ------------
$done = Join-Path $base 's1.done.mat'
$dir = Join-Path $base 's1'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$attempt = 0
$invoke = { param($logPath)
    $script:attempt++
    ("mock s1 attempt " + $script:attempt) | Out-File -FilePath $logPath -Encoding utf8
    if ($script:attempt -eq 1) { return 1 }
    Set-Content -Path $done -Value 'done'
    return 0
}.GetNewClosure()
$n = Invoke-StageWithRetry -Name 's1' -Invoke $invoke -DoneFile $done -Max 3 -LogDir $dir
Assert-True ($n -eq 2) 'S1 crash-without-done retried and succeeded on attempt 2'
Assert-True ((Get-ChildItem $dir -Filter '*.log').Count -eq 2) 'S1 kept both attempt logs'
Assert-True (Test-Path $done) 'S1 done marker written by the completing attempt'

# --- S2: nonzero exit WITH fresh done -> harmless, no retry ----------------
$done = Join-Path $base 's2.done.mat'
$dir = Join-Path $base 's2'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$attempt = 0
$invoke = { param($logPath)
    $script:attempt++
    ("mock s2 attempt " + $script:attempt) | Out-File -FilePath $logPath -Encoding utf8
    Set-Content -Path $done -Value 'done'
    return 1
}.GetNewClosure()
$n = Invoke-StageWithRetry -Name 's2' -Invoke $invoke -DoneFile $done -Max 3 -LogDir $dir
Assert-True ($n -eq 1) 'S2 post-stamp crash accepted on attempt 1 (rules v1.5 rule 7e)'
Assert-True ((Get-ChildItem $dir -Filter '*.log').Count -eq 1) 'S2 did not retry after the fresh done marker'

# --- S3: deterministic failure -> budget exhausted, batch aborts -----------
$done = Join-Path $base 's3.done.mat'
$dir = Join-Path $base 's3'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$attempt = 0
$invoke = { param($logPath)
    $script:attempt++
    ("mock s3 attempt " + $script:attempt) | Out-File -FilePath $logPath -Encoding utf8
    return 1
}.GetNewClosure()
$threw = $false; $msg = ''
try {
    Invoke-StageWithRetry -Name 's3' -Invoke $invoke -DoneFile $done -Max 3 -LogDir $dir | Out-Null
}
catch { $threw = $true; $msg = $_.Exception.Message }
Assert-True $threw 'S3 deterministic failure aborted the batch'
Assert-True ($msg -match 'budget exhausted') 'S3 abort message names the exhausted budget'
Assert-True ((Get-ChildItem $dir -Filter '*.log').Count -eq 3) 'S3 kept all 3 attempt logs'
Assert-True (-not (Test-Path $done)) 'S3 never produced a done marker'

# --- S4: rc-only stage (no done file) ---------------------------------------
$dir = Join-Path $base 's4'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$attempt = 0
$invoke = { param($logPath)
    $script:attempt++
    ("mock s4 attempt " + $script:attempt) | Out-File -FilePath $logPath -Encoding utf8
    if ($script:attempt -eq 1) { return 1 }
    return 0
}.GetNewClosure()
$n = Invoke-StageWithRetry -Name 's4' -Invoke $invoke -DoneFile $null -Max 3 -LogDir $dir
Assert-True ($n -eq 2) 'S4 rc-only stage re-executed then succeeded'
Assert-True ((Get-ChildItem $dir -Filter '*.log').Count -eq 2) 'S4 kept both attempt logs'

# --- S5: a STALE done from an earlier run must not mask a crash ------------
$done = Join-Path $base 's5.done.mat'
Set-Content -Path $done -Value 'stale done from an earlier run'
$dir = Join-Path $base 's5'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$attempt = 0
$invoke = { param($logPath)
    $script:attempt++
    ("mock s5 attempt " + $script:attempt) | Out-File -FilePath $logPath -Encoding utf8
    if ($script:attempt -eq 1) { return 1 }   # crash; done marker untouched (stale)
    Set-Content -Path $done -Value 'done'
    return 0
}.GetNewClosure()
$n = Invoke-StageWithRetry -Name 's5' -Invoke $invoke -DoneFile $done -Max 3 -LogDir $dir
Assert-True ($n -eq 2) 'S5 stale done did not mask the crash; stage re-executed'
Assert-True ((Get-Content $done -Raw).Trim() -eq 'done') 'S5 done marker rewritten by the completing attempt'

# --- S6: rc=0 without a done marker -> inconsistent, batch stops -----------
$done = Join-Path $base 's6.done.mat'
$dir = Join-Path $base 's6'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$invoke = { param($logPath)
    'mock s6' | Out-File -FilePath $logPath -Encoding utf8
    return 0
}.GetNewClosure()
$threw = $false; $msg = ''
try {
    Invoke-StageWithRetry -Name 's6' -Invoke $invoke -DoneFile $done -Max 3 -LogDir $dir | Out-Null
}
catch { $threw = $true; $msg = $_.Exception.Message }
Assert-True $threw 'S6 rc=0 without done stopped the batch'
Assert-True ($msg -match 'exited 0 but') 'S6 abort message names the rc/done inconsistency'

# ---------------------------------------------------------------------------
if ($script:Failures -eq 0) {
    Write-Host 'DRIVER TESTS PASS (6 scenarios)'
    exit 0
}
Write-Host ("DRIVER TESTS FAIL ({0} assertion(s))" -f $script:Failures)
exit 1
