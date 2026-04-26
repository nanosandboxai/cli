#Requires -Version 5.1
<#
.SYNOPSIS
    Uninstalls the Nanosandbox CLI from Windows.

.DESCRIPTION
    Removes the nanosb.exe binary, cleans up PATH, and optionally removes
    runtime dependencies (libkrunfw.dll, busybox) and cached data.

.PARAMETER InstallDir
    Install directory (default: $env:USERPROFILE\.nanosandbox).

.EXAMPLE
    # Uninstall interactively (prompts for deps removal):
    irm https://github.com/nanosandboxai/cli/releases/latest/download/uninstall.ps1 | iex
#>

$ErrorActionPreference = "Stop"

function Uninstall-NanosandboxCLI {
    param(
        [string]$InstallDir = "$env:USERPROFILE\.nanosandbox"
    )

    # --- Helpers ---
    function Write-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
    function Write-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
    function Write-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }

    Write-Host ""
    Write-Host "  Nanosandbox CLI Uninstaller for Windows" -ForegroundColor White
    Write-Host "  ========================================" -ForegroundColor DarkGray
    Write-Host ""

    # --- Remove CLI binary ---
    $nanosb = Join-Path $InstallDir "nanosb.exe"
    if (Test-Path $nanosb) {
        Remove-Item $nanosb -Force
        Write-Ok "Removed $nanosb"
    } else {
        Write-Info "nanosb.exe not found at $nanosb"
    }

    # --- Remove from PATH ---
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -like "*$InstallDir*") {
        $newPath = ($userPath -split ";" | Where-Object { $_ -ne $InstallDir }) -join ";"
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Ok "Removed $InstallDir from user PATH"
    }

    # --- Ask about runtime dependencies ---
    Write-Host ""
    $libsDir = Join-Path $InstallDir "libs"
    $depsExist = (Test-Path (Join-Path $libsDir "libkrunfw.dll")) -or
                 (Test-Path (Join-Path $libsDir "busybox")) -or
                 (Test-Path (Join-Path $libsDir "vsock_proxy")) -or
                 # Legacy: old install-deps placed deps at root level
                 (Test-Path (Join-Path $InstallDir "libkrunfw.dll")) -or
                 (Test-Path (Join-Path $InstallDir "busybox")) -or
                 (Test-Path (Join-Path $InstallDir "vsock_proxy"))

    if ($depsExist) {
        Write-Host "  Runtime dependencies found (libkrunfw.dll, busybox, vsock_proxy)." -ForegroundColor White
        $answer = Read-Host "  Also remove runtime dependencies? [y/N]"
        if ($answer -match '^[Yy]') {
            # Remove from libs/ (current layout)
            if (Test-Path $libsDir) {
                Remove-Item $libsDir -Recurse -Force
                Write-Ok "Removed $libsDir"
            }
            # Remove legacy root-level deps
            foreach ($file in @('libkrunfw.dll', 'busybox', 'vsock_proxy')) {
                $path = Join-Path $InstallDir $file
                if (Test-Path $path) {
                    Remove-Item $path -Force
                    Write-Ok "Removed $path"
                }
            }
        } else {
            Write-Info "Kept runtime dependencies"
        }
    }

    # --- Ask about cached data ---
    $dataItems = @()
    if (Test-Path $InstallDir) {
        $children = Get-ChildItem $InstallDir -ErrorAction SilentlyContinue
        # Check for cache/logs/data dirs (anything beyond the binary and deps)
        $dataItems = $children | Where-Object {
            $_.Name -notin @('nanosb.exe', 'libkrunfw.dll', 'busybox', 'vsock_proxy', 'libs')
        }
    }

    if ($dataItems.Count -gt 0) {
        Write-Host ""
        Write-Host "  Cached data found in $InstallDir`:" -ForegroundColor White
        foreach ($item in $dataItems) {
            Write-Host "    - $($item.Name)" -ForegroundColor DarkGray
        }
        $answer = Read-Host "  Remove all cached data (images, logs, VHDX)? [y/N]"
        if ($answer -match '^[Yy]') {
            Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Ok "Removed $InstallDir and all contents"
        } else {
            Write-Info "Kept cached data"
            # Still clean up if directory is now empty (only had binary)
            if ((Test-Path $InstallDir) -and @(Get-ChildItem $InstallDir).Count -eq 0) {
                Remove-Item $InstallDir -Force
                Write-Ok "Removed empty directory $InstallDir"
            }
        }
    } else {
        # No data items left, clean up if empty
        if ((Test-Path $InstallDir) -and @(Get-ChildItem $InstallDir -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item $InstallDir -Force
            Write-Ok "Removed empty directory $InstallDir"
        }
    }

    # --- Summary ---
    Write-Host ""
    Write-Ok "Nanosandbox CLI uninstalled."
    Write-Host "  Restart your terminal for PATH changes to take effect." -ForegroundColor DarkGray
    Write-Host ""
}

# Invoke the function - @args passes through any command-line parameters
Uninstall-NanosandboxCLI @args
