# WinBoost.ps1
# Main script to launch the WinBoost GUI tool

# Define base path for easier referencing of other script files
$PSScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition

. (Join-Path $PSScriptRoot "functions\UI_Functions.ps1")
. (Join-Path $PSScriptRoot "functions\SystemInfo_Functions.ps1")
. (Join-Path $PSScriptRoot "functions\Winget_Functions.ps1")
. (Join-Path $PSScriptRoot "gui\MainForm.ps1")
. (Join-Path $PSScriptRoot "gui\Tab_Home.ps1")
. (Join-Path $PSScriptRoot "gui\Tab_General.ps1")
. (Join-Path $PSScriptRoot "gui\Tab_Downloads.ps1")
. (Join-Path $PSScriptRoot "gui\Tab_Advanced.ps1")
. (Join-Path $PSScriptRoot "gui\Tab_Untested.ps1")

# Add-Type statements (keep them here or in a common initialization file)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global variables (minimize these, pass as parameters where possible)
$scriptVersion = "0.0.5"
$global:IgnoreCheckEvent = $false
$global:IgnoreCheckEventDownloads = $false
$global:hasChanges = $false
$global:restartNeeded = $false
$global:installedPackageIds = @{} # This is initialized here, but updated by Winget_Functions

# Admin Check (can stay here as it's a critical initial check)
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
    [System.Windows.Forms.MessageBox]::Show("This script must be run as an Administrator. Please restart PowerShell or the script file with administrative privileges.", "Administrator Privileges Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Stop)
    exit
}

# Welcome Message
Write-Host ""
Write-Host "█████   █   █    ███  █████     █████ █████" -ForegroundColor Green
Write-Host "█       █   █   █   █ █         █     █" -ForegroundColor Green
Write-Host "█████   █████   █████ █ ███     █ ███ █ ███" -ForegroundColor Green
Write-Host "    █   █   █   █   █ █   █     █   █ █   █" -ForegroundColor Green
Write-Host "█████   █   █   █   █ █████ █   █████ █████" -ForegroundColor Green
Write-Host ""
Write-Host "*********************************************" -ForegroundColor Cyan
Write-Host "* Welcome to WinBoost v$scriptVersion!      *" -ForegroundColor Cyan
Write-Host "* Optimizing your Windows experience.       *" -ForegroundColor Cyan
Write-Host "* Script by leeshhi                         *" -ForegroundColor Cyan
Write-Host "*********************************************" -ForegroundColor Cyan
Write-Host ""
Write-Host ""

# Call the function to create and show the main form
Initialize-MainForm

# Perform initial system info display and update check
Get-AndDisplayAllSystemInfo
Check-ForUpdates

# Initial Winget status update
# This part is crucial and should be called after the GUI is set up to show progress.
# Ensure $form, $downloadProgressBar, and $statusDownloadLabel are accessible (e.g., passed as parameters or global if unavoidable).
# For now, assuming they are accessible via the . (dot sourcing) of GUI files.
Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel

# Show form
[void]$form.ShowDialog()