#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls the Nanosandbox CLI from Windows.

.DESCRIPTION
    Removes the nanosb.exe binary and cleans up PATH.
    Does NOT remove runtime dependencies (use install-deps uninstall.ps1 for that).

.PARAMETER InstallDir
    Install directory (default: $env:LOCALAPPDATA\nanosandbox).
#>

[CmdletBinding()]
param(
    [string]$InstallDir = "$env:LOCALAPPDATA\nanosandbox"
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  Nanosandbox CLI Uninstaller for Windows" -ForegroundColor White
Write-Host "  ========================================" -ForegroundColor DarkGray
Write-Host ""

# Remove binary
$nanosb = Join-Path $InstallDir "nanosb.exe"
if (Test-Path $nanosb) {
    Remove-Item $nanosb -Force
    Write-Host "[OK]   Removed $nanosb" -ForegroundColor Green
} else {
    Write-Host "[INFO] nanosb.exe not found at $nanosb" -ForegroundColor Cyan
}

# Remove from PATH
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -like "*$InstallDir*") {
    $newPath = ($userPath -split ";" | Where-Object { $_ -ne $InstallDir }) -join ";"
    [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
    Write-Host "[OK]   Removed $InstallDir from user PATH" -ForegroundColor Green
}

# Clean up install dir if empty
if ((Test-Path $InstallDir) -and -not (Get-ChildItem $InstallDir)) {
    Remove-Item $InstallDir -Force
    Write-Host "[OK]   Removed empty directory $InstallDir" -ForegroundColor Green
}

Write-Host ""
Write-Host "[OK]   Nanosandbox CLI uninstalled." -ForegroundColor Green
Write-Host "       To also remove runtime deps: run install-deps\uninstall.ps1" -ForegroundColor DarkGray
Write-Host ""
