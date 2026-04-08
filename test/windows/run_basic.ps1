#Requires -Version 5.1
<#
.SYNOPSIS
    Basic CLI smoke tests for Windows.

.DESCRIPTION
    Runs basic nanosb CLI commands to verify the binary works on Windows.
    These are not integration tests (no VM required), just CLI surface tests.
#>

$ErrorActionPreference = "Stop"
$script:passed = 0
$script:failed = 0

function Test-Command {
    param(
        [string]$Name,
        [string]$Command,
        [int]$ExpectedExit = 0,
        [string]$ExpectOutput = ""
    )

    Write-Host -NoNewline "  TEST: $Name ... "

    try {
        $output = Invoke-Expression $Command 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne $ExpectedExit) {
            Write-Host "FAIL (exit=$exitCode, expected=$ExpectedExit)" -ForegroundColor Red
            Write-Host "    Output: $($output.Trim().Substring(0, [Math]::Min(200, $output.Length)))" -ForegroundColor DarkGray
            $script:failed++
            return
        }

        if ($ExpectOutput -and $output -notmatch $ExpectOutput) {
            Write-Host "FAIL (output missing: $ExpectOutput)" -ForegroundColor Red
            $script:failed++
            return
        }

        Write-Host "PASS" -ForegroundColor Green
        $script:passed++
    } catch {
        Write-Host "FAIL (exception: $_)" -ForegroundColor Red
        $script:failed++
    }
}

# --- Find nanosb binary ---
$nanosb = Get-Command nanosb -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $nanosb) {
    $nanosb = "nanosb"
}
Write-Host ""
Write-Host "Nanosandbox CLI Windows Tests" -ForegroundColor White
Write-Host "Binary: $nanosb" -ForegroundColor DarkGray
Write-Host ""

# --- Tests ---
Test-Command "version" "$nanosb --version" -ExpectedExit 0 -ExpectOutput "nanosb"
Test-Command "help" "$nanosb --help" -ExpectedExit 0 -ExpectOutput "sandbox"
Test-Command "doctor" "$nanosb doctor" -ExpectedExit 0
Test-Command "images list (empty ok)" "$nanosb images list" -ExpectedExit 0
Test-Command "invalid subcommand" "$nanosb invalid-command-xyz" -ExpectedExit 2

# --- Summary ---
Write-Host ""
$total = $script:passed + $script:failed
Write-Host "Results: $script:passed/$total passed" -ForegroundColor $(if ($script:failed -eq 0) { "Green" } else { "Red" })

if ($script:failed -gt 0) {
    exit 1
}
