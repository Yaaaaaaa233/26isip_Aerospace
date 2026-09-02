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
    S6  rc=0 WITHOUT done marker           -> still a retryable crash outcome (launcher can
                                             exit 0 on a heap-corrupted child, live case
                                             20260902_225209); budget aborts when persistent
    S7  report-style archive evidence      -> a NEW directory under $DoneDir counts as the
                                             fresh done marker; no new dir -> retry
    S8  log encoding round trip (R9-F2)    -> a native command emitting ANSI-page CJK
                                             bytes is captured by the driver's own
                                             Invoke-LoggedNative with the original text
                                             intact and ZERO U+FFFD in the UTF-8 log

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

# --- S6: rc=0 without done -> still a retryable crash, budget aborts --------
# Live basis results/batch_runs/20260902_225209: the R2022b heap
# corruption killed the c2clean child and the matlab launcher exited 0.
$done = Join-Path $base 's6.done.mat'
$dir = Join-Path $base 's6'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$invoke = { param($logPath)
    'mock s6 rc=0 but the child died before stamping' | Out-File -FilePath $logPath -Encoding utf8
    return 0
}.GetNewClosure()
$threw = $false; $msg = ''
try {
    Invoke-StageWithRetry -Name 's6' -Invoke $invoke -DoneFile $done -Max 3 -LogDir $dir | Out-Null
}
catch { $threw = $true; $msg = $_.Exception.Message }
Assert-True $threw 'S6 rc=0 without done did not fake a pass; budget aborted the batch'
Assert-True ($msg -match 'budget exhausted') 'S6 abort message names the exhausted budget'
Assert-True ((Get-ChildItem $dir -Filter '*.log').Count -eq 3) 'S6 kept all 3 attempt logs'
Assert-True (-not (Test-Path $done)) 'S6 never produced a done marker'

# --- S7: report-style evidence -- a NEW directory under $DoneDir ------------
$archRoot = Join-Path $base 's7_arch'
New-Item -ItemType Directory -Force -Path (Join-Path $archRoot 'old_batch') | Out-Null
$dir = Join-Path $base 's7'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$attempt = 0
$invoke = { param($logPath)
    $script:attempt++
    ("mock s7 attempt " + $script:attempt) | Out-File -FilePath $logPath -Encoding utf8
    if ($script:attempt -eq 1) { return 1 }   # crash before any archive
    $d = Join-Path $archRoot ('batch_' + $script:attempt)
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return 0
}.GetNewClosure()
$n = Invoke-StageWithRetry -Name 's7' -Invoke $invoke -DoneFile $null -DoneDir $archRoot -Max 3 -LogDir $dir
Assert-True ($n -eq 2) 'S7 new archive directory accepted as fresh evidence on attempt 2'
$invoke2 = { param($logPath)
    'mock s7b crash AFTER archiving' | Out-File -FilePath $logPath -Encoding utf8
    $d = Join-Path $archRoot 'batch_late'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return 1
}.GetNewClosure()
$dir2 = Join-Path $base 's7b'; New-Item -ItemType Directory -Force -Path $dir2 | Out-Null
$n2 = Invoke-StageWithRetry -Name 's7b' -Invoke $invoke2 -DoneFile $null -DoneDir $archRoot -Max 3 -LogDir $dir2
Assert-True ($n2 -eq 1) 'S7b post-archive crash (nonzero rc, fresh dir) accepted as harmless pass'

# --- S8: log encoding round trip through the driver's own capture path -------
# Pure-ASCII test source (PS 5.1 reads no-BOM scripts as ANSI): the CJK
# text is built from code points, and the fixture file is written with
# the ANSI page bytes via cmd /c type -- the same decode layer MATLAB's
# piped output goes through (probe 2026-09-03: MATLAB -batch emits ANSI
# page bytes; the round-9 logs captured under a UTF-8 console were full
# of U+FFFD).
$cn = -join @([char]0x4E2D, [char]0x6587, [char]0x7B2C, [char]0x4E8C, [char]0x9636, [char]0x6BB5, [char]0x6D4B, [char]0x8BD5)
$fixture = Join-Path $base 's8_ansi.txt'
[System.IO.File]::WriteAllBytes($fixture, [System.Text.Encoding]::Default.GetBytes($cn + "`n"))
$dir = Join-Path $base 's8'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$log = Join-Path $dir 's8_native.log'
$rc = Invoke-LoggedNative -FilePath 'cmd.exe' -Arguments @('/c', 'type', $fixture) -LogPath $log
$captured = Get-Content -Raw -Encoding UTF8 $log
Assert-True ($rc -eq 0) 'S8 native command exited 0'
Assert-True $captured.Contains($cn) 'S8 ANSI-page CJK round-trips intact through Invoke-LoggedNative'
Assert-True (-not $captured.Contains([string][char]0xFFFD)) 'S8 log contains zero U+FFFD replacement characters'

# ---------------------------------------------------------------------------
if ($script:Failures -eq 0) {
    Write-Host 'DRIVER TESTS PASS (9 scenarios)'
    exit 0
}
Write-Host ("DRIVER TESTS FAIL ({0} assertion(s))" -f $script:Failures)
exit 1
