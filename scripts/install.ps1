#Requires -Version 5.1
<#
.SYNOPSIS
    Nanosandbox CLI Installer for Windows.

.DESCRIPTION
    Downloads and installs the nanosb CLI binary and runtime dependencies on Windows.
    1. Checks prerequisites (Hyper-V, WSL2) and installs WSL2 if missing
    2. Downloads the nanosb.exe binary from GitHub Releases
    3. Installs runtime dependencies via install-deps
    4. Adds the install directory to the user PATH

.EXAMPLE
    # Install latest version (use raw.githubusercontent.com — release asset URLs return octet-stream
    # which PowerShell's irm cannot pipe directly to iex)
    irm https://raw.githubusercontent.com/nanosandboxai/cli/main/scripts/install.ps1 | iex

    # Install specific version (pin to a tag)
    irm https://raw.githubusercontent.com/nanosandboxai/cli/v0.2.0-rc17/scripts/install.ps1 | iex

    # Or download and run locally:
    .\install.ps1 -Version v0.2.0-rc17
    .\install.ps1 -Version v0.2.0
#>

$ErrorActionPreference = "Stop"

# Wrap entire installer in a function so param() works both when run directly and via iex.
# Script-level param() creates optimized read-only variables that break under Invoke-Expression.
function Install-NanosandboxCLI {
    param(
        [string]$Version = "",
        [string]$InstallDir = "$env:USERPROFILE\.nanosandbox",
        # Skip the Windows Defender exclusion prompt entirely. nanosb.exe is an
        # unsigned Rust binary which Defender's ML heuristics frequently flag
        # as a generic threat (Wacatac etc.). Adding an exclusion for the
        # install dir prevents the .exe from being silently quarantined on
        # download. Pass -SkipDefenderExclusion to opt out (e.g. when the
        # install dir is already covered by an existing exclusion).
        [switch]$SkipDefenderExclusion,
        # Skip the prompt and add the exclusion automatically. Useful for
        # unattended/CI installs.
        [switch]$AddDefenderExclusion,
        # Skip WSL2 prerequisite check entirely (for advanced users who know
        # they don't need WSL2 or will install it separately).
        [switch]$SkipWsl2Check
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

    # --- WSL2 check and auto-install ---
    # nanosb on Windows uses WSL2 as the Linux kernel layer for VM execution.
    if (-not $SkipWsl2Check) {
        $wslExe = Join-Path $env:SystemRoot "System32\wsl.exe"
        $wsl2Ready = $false

        if (Test-Path $wslExe) {
            # wsl.exe exists — probe whether WSL2 is configured and responsive.
            # --status exits 0 when WSL2 kernel is present; non-zero on fresh systems.
            $wslOut = & $wslExe --status 2>&1
            if ($LASTEXITCODE -eq 0) {
                $wsl2Ready = $true
                Write-Ok "WSL2 is available"
            }
        }

        if (-not $wsl2Ready) {
            Write-Warn "WSL2 is not installed or not configured."
            Write-Info "WSL2 is required for nanosb to run Linux VMs on Windows."
            Write-Host ""

            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)

            if (-not $isAdmin) {
                Write-Warn "Installing WSL2 requires Administrator privileges."
                Write-Warn "Please re-run this installer in an elevated (Administrator) PowerShell,"
                Write-Warn "or install WSL2 manually with:"
                Write-Warn "    wsl --install"
                Write-Warn "Then restart your computer and re-run this installer."
                Write-Host ""
                $answer = Read-Host "  Continue without WSL2 (nanosb may not work)? [y/N]"
                if ($answer -notmatch '^[Yy]') {
                    Write-Info "Aborted. Re-run as Administrator to install WSL2 automatically."
                    return
                }
            } else {
                $answer = Read-Host "  Install WSL2 now? [Y/n]"
                if ($answer -notmatch '^[Nn]') {
                    Write-Info "Installing WSL2 (this may take a few minutes)..."
                    try {
                        # --no-launch prevents the Ubuntu terminal from opening immediately.
                        # WSL2 kernel + default Ubuntu distro will be set up; a reboot is
                        # required before the WSL2 kernel becomes active.
                        & $wslExe --install --no-launch 2>&1 | ForEach-Object { Write-Host "  $_" }
                        if ($LASTEXITCODE -eq 0) {
                            Write-Ok "WSL2 installed successfully."
                        } else {
                            Write-Warn "WSL2 installer exited with code $LASTEXITCODE — a reboot may still be needed."
                        }
                    } catch {
                        Write-Warn "WSL2 installation failed: $_"
                        Write-Warn "Try manually in an elevated PowerShell: wsl --install"
                    }

                    Write-Host ""
                    Write-Warn "A system restart is required to complete WSL2 setup."
                    Write-Warn "After restarting, re-run this installer to finish nanosb installation."
                    Write-Host ""
                    $restart = Read-Host "  Restart now? [y/N]"
                    if ($restart -match '^[Yy]') {
                        Restart-Computer -Force
                    } else {
                        Write-Info "Please restart your computer and then re-run this installer."
                    }
                    return
                } else {
                    Write-Warn "Skipping WSL2 installation. nanosb may not function correctly."
                }
            }
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

    # --- Windows Defender exclusion (must run BEFORE download) ---
    # Without this, Defender's ML heuristics frequently quarantine the freshly
    # downloaded nanosb.exe as a generic threat, leaving an empty install dir
    # and a confusing "command not recognized" error for the user.
    if (-not $SkipDefenderExclusion) {
        $defender = Get-MpComputerStatus -ErrorAction SilentlyContinue
        $defenderActive = $defender -and $defender.RealTimeProtectionEnabled
        if ($defenderActive) {
            $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

            $alreadyExcluded = $false
            try {
                $existing = (Get-MpPreference).ExclusionPath
                if ($existing -and ($existing -contains $InstallDir)) {
                    $alreadyExcluded = $true
                }
            } catch { }

            if ($alreadyExcluded) {
                Write-Info "$InstallDir already excluded from Windows Defender"
            } elseif (-not $isAdmin) {
                Write-Warn "Windows Defender real-time protection is active."
                Write-Warn "nanosb.exe is unsigned and may be flagged as a generic threat by Defender's ML heuristics."
                Write-Warn "To add an exclusion automatically, re-run this installer in an elevated (Administrator) PowerShell."
                Write-Warn "Or manually run, as Administrator:"
                Write-Warn "  Add-MpPreference -ExclusionPath '$InstallDir'"
                Write-Warn "  Add-MpPreference -ExclusionProcess 'nanosb.exe'"
                Write-Host ""
                $answer = Read-Host "  Continue without an exclusion (download may be quarantined)? [y/N]"
                if ($answer -notmatch '^[Yy]') {
                    Write-Info "Aborted by user. Re-run as Administrator to add the exclusion automatically."
                    return
                }
            } else {
                $consent = $AddDefenderExclusion
                if (-not $consent) {
                    Write-Warn "Windows Defender real-time protection is active."
                    Write-Warn "nanosb.exe is unsigned and may be flagged as a generic threat by Defender's ML heuristics."
                    Write-Warn "Adding a path exclusion for $InstallDir will prevent silent quarantine of the downloaded binary."
                    Write-Host ""
                    $answer = Read-Host "  Add Windows Defender exclusion for $InstallDir ? [Y/n]"
                    if ($answer -notmatch '^[Nn]') { $consent = $true }
                }
                if ($consent) {
                    try {
                        Add-MpPreference -ExclusionPath $InstallDir -ErrorAction Stop
                        Add-MpPreference -ExclusionProcess "nanosb.exe" -ErrorAction Stop
                        Write-Ok "Added Windows Defender exclusion: $InstallDir"
                        Write-Ok "Added Windows Defender process exclusion: nanosb.exe"
                    } catch {
                        Write-Warn "Failed to add Defender exclusion: $_"
                        Write-Warn "Proceeding anyway -- download may be quarantined."
                    }
                } else {
                    Write-Info "Skipped Defender exclusion -- download may be quarantined."
                }
            }
        }
    }

    # --- Download nanosb.exe ---
    $binaryName = "nanosb.exe"
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
    # cli and install-deps publish coordinated rc tags, so reuse $resolvedVersion
    # instead of re-querying the install-deps API (the default /releases ordering
    # is by tag commit date, which can return a stale tag whose install.ps1 asset
    # doesn't exist yet).
    $depsTag = $resolvedVersion
    $depsUrl = "https://github.com/$depsRepo/releases/download/$depsTag/install.ps1"
    try {
        Write-Info "Fetching install-deps ($depsTag)..."
        $depsScript = Invoke-RestMethod $depsUrl
        # The script ends with `Install-NanosandboxDeps @args`, which would run
        # with empty $args here. Strip that auto-invocation so we can call the
        # function ourselves with the version pinned.
        $depsScript = $depsScript -replace 'Install-NanosandboxDeps\s+@args\s*$', ''
        Invoke-Expression $depsScript
        Install-NanosandboxDeps -Version $resolvedVersion -InstallDir $InstallDir
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
