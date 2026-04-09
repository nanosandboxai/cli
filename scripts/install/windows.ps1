#Requires -Version 5.1
<#
.SYNOPSIS
    Nanosandbox CLI Installer for Windows.

.DESCRIPTION
    Downloads and installs the nanosb CLI binary and runtime dependencies on Windows.
    1. Downloads the nanosb.exe binary from GitHub Releases
    2. Installs runtime dependencies via install-deps
    3. Adds the install directory to the user PATH

.PARAMETER Version
    Version to install (default: "latest").

.PARAMETER InstallDir
    Install directory (default: $env:LOCALAPPDATA\nanosandbox).

.PARAMETER PreRelease
    Include pre-release versions when resolving "latest".

.EXAMPLE
    # Install latest version
    irm https://github.com/nanosandboxai/cli/releases/latest/download/windows.ps1 | iex

    # Install specific version
    .\windows.ps1 -Version v0.2.0

    # Install latest pre-release
    .\windows.ps1 -PreRelease
#>

[CmdletBinding()]
param(
    [string]$Version = "latest",
    [string]$InstallDir = "$env:LOCALAPPDATA\nanosandbox",
    [switch]$PreRelease
)

$ErrorActionPreference = "Stop"

# --- Helpers ---
function Write-Info    { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Write-Ok      { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn    { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Err     { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }

# --- Prerequisites ---
Write-Host ""
Write-Host "  Nanosandbox CLI Installer for Windows" -ForegroundColor White
Write-Host "  ======================================" -ForegroundColor DarkGray
Write-Host ""

# Check Windows version (need 10 1809+ for Hyper-V / HCS)
$build = [System.Environment]::OSVersion.Version.Build
if ($build -lt 17763) {
    Write-Err "Windows 10 version 1809 (build 17763) or later is required. Current build: $build"
}

# Check Hyper-V
$hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
if (-not $hyperv -or $hyperv.State -ne "Enabled") {
    Write-Warn "Hyper-V is not enabled. It is required for VM execution."
    Write-Warn "Enable it with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
}

# --- Resolve version ---
$releaseRepo = "nanosandboxai/cli"
if ($Version -eq "latest") {
    if ($PreRelease) {
        Write-Info "Resolving latest version (including pre-releases)..."
    } else {
        Write-Info "Resolving latest version..."
    }
    try {
        if ($PreRelease) {
            $releases = Invoke-RestMethod "https://api.github.com/repos/$releaseRepo/releases?per_page=1"
            $Version = $releases[0].tag_name
        } else {
            $releaseInfo = Invoke-RestMethod "https://api.github.com/repos/$releaseRepo/releases/latest"
            $Version = $releaseInfo.tag_name
        }
    } catch {
        Write-Err "Failed to resolve latest version: $_"
    }
}
Write-Info "Installing nanosb $Version"

# --- Create install directory ---
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
Write-Info "Install directory: $InstallDir"

# --- Download nanosb.exe ---
$binaryName = "nanosb-windows-amd64.exe"
$downloadUrl = "https://github.com/$releaseRepo/releases/download/$Version/$binaryName"
$destPath = Join-Path $InstallDir "nanosb.exe"

Write-Info "Downloading $binaryName..."
try {
    Invoke-WebRequest -Uri $downloadUrl -OutFile $destPath -UseBasicParsing
    Write-Ok "Downloaded nanosb.exe"
} catch {
    Write-Err "Failed to download nanosb.exe from $downloadUrl`n$_"
}

# --- Install runtime dependencies ---
Write-Info "Installing runtime dependencies..."
if ($PreRelease) {
    $depsRepo = "nanosandboxai/install-deps"
    try {
        $depsReleases = Invoke-RestMethod "https://api.github.com/repos/$depsRepo/releases?per_page=1"
        $depsTag = $depsReleases[0].tag_name
    } catch {
        Write-Warn "Failed to resolve install-deps pre-release, falling back to latest"
        $depsTag = "latest"
    }
    if ($depsTag -ne "latest") {
        $depsUrl = "https://github.com/$depsRepo/releases/download/$depsTag/install.ps1"
    } else {
        $depsUrl = "https://github.com/$depsRepo/releases/latest/download/install.ps1"
    }
} else {
    $depsUrl = "https://github.com/nanosandboxai/install-deps/releases/latest/download/install.ps1"
}
try {
    $depsScript = Invoke-RestMethod $depsUrl
    Invoke-Expression $depsScript
    Write-Ok "Runtime dependencies installed"
} catch {
    Write-Warn "Failed to install runtime dependencies automatically: $_"
    Write-Warn "You may need to install them manually from: https://github.com/nanosandboxai/install-deps"
}

# --- Add to PATH ---
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$InstallDir*") {
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
    Write-Ok "Added $InstallDir to user PATH"
    Write-Warn "Restart your terminal for PATH changes to take effect."
} else {
    Write-Info "$InstallDir already in PATH"
}

# --- Verify ---
Write-Host ""
Write-Ok "nanosb $Version installed to $destPath"
Write-Host ""
Write-Host "  Get started:" -ForegroundColor White
Write-Host "    nanosb doctor    # Check prerequisites" -ForegroundColor DarkGray
Write-Host "    nanosb run       # Start a sandbox" -ForegroundColor DarkGray
Write-Host ""
