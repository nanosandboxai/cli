#Requires -Version 5.1
<#
.SYNOPSIS
    Nanosandbox CLI Installer for Windows.

.DESCRIPTION
    Downloads and installs the nanosb CLI binary and runtime dependencies on Windows.
    1. Downloads the nanosb.exe binary from GitHub Releases
    2. Installs runtime dependencies via install-deps
    3. Adds the install directory to the user PATH

.EXAMPLE
    # Install latest stable version
    irm https://github.com/nanosandboxai/cli/releases/latest/download/install.ps1 | iex

    # Install specific version (stable or pre-release)
    .\install.ps1 -Version v0.2.0-rc5
    .\install.ps1 -Version v0.2.0
#>

$ErrorActionPreference = "Stop"

# Wrap entire installer in a function so param() works both when run directly and via iex.
# Script-level param() creates optimized read-only variables that break under Invoke-Expression.
function Install-NanosandboxCLI {
    param(
        [string]$Version = "",
        [string]$InstallDir = "$env:USERPROFILE\.nanosandbox"
    )

    # --- Helpers ---
    function Write-Info    { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan }
    function Write-Ok      { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green }
    function Write-Warn    { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
    function Write-Err     { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

    # --- Prerequisites ---
    Write-Host ""
    Write-Host "  Nanosandbox CLI Installer for Windows" -ForegroundColor White
    Write-Host "  ======================================" -ForegroundColor DarkGray
    Write-Host ""

    $build = [System.Environment]::OSVersion.Version.Build
    if ($build -lt 17763) {
        Write-Err "Windows 10 version 1809 (build 17763) or later is required. Current build: $build"
        return
    }

    # Check Hyper-V: try the service first (works on both Server and Desktop), fall back to feature check
    $vmcompute = Get-Service vmcompute -ErrorAction SilentlyContinue
    if ($vmcompute -and $vmcompute.Status -eq 'Running') {
        Write-Ok "Hyper-V / HCS enabled (vmcompute running)"
    } else {
        $hyperv = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue
        if (-not $hyperv -or $hyperv.State -ne "Enabled") {
            Write-Warn "Hyper-V is not enabled. It is required for VM execution."
            Write-Warn "Enable it with: Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All"
        } else {
            Write-Ok "Hyper-V enabled"
        }
    }

    # --- Resolve version ---
    $releaseRepo = "nanosandboxai/cli"
    $resolvedVersion = $Version

    if (-not $resolvedVersion -or $resolvedVersion -eq "latest") {
        # No version specified: resolve latest release (including pre-releases)
        Write-Info "Resolving latest version..."
        try {
            $releases = Invoke-RestMethod "https://api.github.com/repos/$releaseRepo/releases?per_page=1"
            $resolvedVersion = $releases[0].tag_name
            if (-not $resolvedVersion) { throw "No releases found" }
        } catch {
            Write-Err "Failed to resolve latest version: $_"
            return
        }
    } else {
        # Specific version requested: verify the tag exists
        Write-Info "Verifying tag $resolvedVersion..."
        try {
            $null = Invoke-RestMethod "https://api.github.com/repos/$releaseRepo/releases/tags/$resolvedVersion"
        } catch {
            Write-Err "Release $resolvedVersion not found. Check available tags at: https://github.com/$releaseRepo/releases"
            return
        }
    }

    Write-Info "Installing nanosb $resolvedVersion"

    # --- Create install directory ---
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    }
    Write-Info "Install directory: $InstallDir"

    # --- Download nanosb.exe ---
    $binaryName = "nanosb-windows-amd64.exe"
    $downloadUrl = "https://github.com/$releaseRepo/releases/download/$resolvedVersion/$binaryName"
    $destPath = Join-Path $InstallDir "nanosb.exe"

    Write-Info "Downloading $binaryName..."
    try {
        Invoke-WebRequest -Uri $downloadUrl -OutFile $destPath -UseBasicParsing
        Write-Ok "Downloaded nanosb.exe"
    } catch {
        Write-Err "Failed to download nanosb.exe from $downloadUrl`n$_"
        return
    }

    # --- Install runtime dependencies ---
    Write-Info "Installing runtime dependencies..."
    $depsRepo = "nanosandboxai/install-deps"
    $depsTag = $null
    try {
        $depsReleases = Invoke-RestMethod "https://api.github.com/repos/$depsRepo/releases?per_page=1"
        $depsTag = $depsReleases[0].tag_name
        $depsUrl = "https://github.com/$depsRepo/releases/download/$depsTag/install.ps1"
    } catch {
        $depsUrl = "https://github.com/$depsRepo/releases/latest/download/install.ps1"
    }
    try {
        Write-Info "Fetching install-deps ($depsTag)..."
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
        # Also update the current session so the user doesn't need to open a new terminal
        $env:Path = "$env:Path;$InstallDir"
        Write-Ok "Added $InstallDir to user PATH (available immediately)"
    } else {
        Write-Info "$InstallDir already in PATH"
    }

    # --- Verify ---
    Write-Host ""
    Write-Ok "nanosb $resolvedVersion installed to $destPath"
    Write-Host ""
    Write-Host "  Get started:" -ForegroundColor White
    Write-Host "    nanosb doctor    # Check prerequisites" -ForegroundColor DarkGray
    Write-Host "    nanosb run       # Start a sandbox" -ForegroundColor DarkGray
    Write-Host ""
}

# Invoke the function - @args passes through any command-line parameters
Install-NanosandboxCLI @args
