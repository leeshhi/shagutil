#Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security # Needed ?
$scriptVersion = "25.07.25"

#region 1. Initial Script Setup & Compatibility Checks
if (-not ([Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) { # Check for Administrator privileges
    [System.Windows.Forms.MessageBox]::Show("This script must be run as an Administrator. Please restart PowerShell or the script file with administrative privileges.", "Administrator Privileges Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Stop)
    exit
}

# Windows Version Check
$buildNumber = [System.Environment]::OSVersion.Version.Build
$osName = (Get-CimInstance Win32_OperatingSystem).Caption
try { $displayVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion").DisplayVersion } catch { $displayVersion = "" }
$versionInfo = if ($displayVersion) { "$osName $displayVersion (Build $buildNumber)" } else { "$osName (Build $buildNumber)" }

if ($buildNumber -lt 22000) { # Exit if not Windows 11 or unsupported version
    [System.Windows.Forms.MessageBox]::Show("This script requires Windows 11 or newer.`n`nDetected OS: $versionInfo", "Unsupported Windows Version", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    [System.Windows.Forms.Application]::Exit()
    [System.Environment]::Exit(1)
}

if ($displayVersion -and -not (@("23H2", "24H2", "25H2") -contains $displayVersion)) { # Check supported versions
    [System.Windows.Forms.MessageBox]::Show("Unsupported Windows version.`n`nDetected: $versionInfo`nSupported: 23H2, 24H2, 25H2", "Unsupported Version", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    [System.Windows.Forms.Application]::Exit()
    [System.Environment]::Exit(1)
}

Clear-Host
Write-Host ""
Write-Host "  _________.__                    ____ ___   __  .__.__   " -ForegroundColor White
Write-Host " /   _____/|  |__ _____     ____ |    |   \_/  |_|__|  |  " -ForegroundColor White
Write-Host " \_____  \ |  |  \\__  \   / ___\|    |   /\   __\  |  |  " -ForegroundColor White
Write-Host " /        \|   Y  \/ __ \_/ /_/  >    |  /  |  | |  |  |__" -ForegroundColor White
Write-Host "/_______  /|___|  (____  /\___  /|______/   |__| |__|____/" -ForegroundColor White
Write-Host "        \/      \/     \//_____/                          " -ForegroundColor White
Write-Host ""
Write-Host "==== Welcome to ShagUtil v$scriptVersion! ====" -ForegroundColor Cyan
Write-Host "==== Windows Toolbox ====`n" -ForegroundColor White
#endregion

#region 2. Global Helper Functions
function ConvertTo-StandardTweakFormat {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Tweak
    )
    
    # Convert Hashtable to PSCustomObject if necessary
    if ($Tweak -is [System.Collections.Hashtable] -or $Tweak -is [System.Collections.Specialized.OrderedDictionary]) {
        $Tweak = [PSCustomObject]$Tweak
    }
    
    # Create a shallow copy of the tweak to avoid modifying the original
    $standardTweak = New-Object PSObject
    
    # Copy all properties to the new object
    $properties = $Tweak.PSObject.Properties | Where-Object { 
        $_.MemberType -eq 'NoteProperty' -or $_.MemberType -eq 'Property' 
    }
    
    foreach ($prop in $properties) {
        $standardTweak | Add-Member -MemberType NoteProperty -Name $prop.Name -Value $prop.Value -Force
    }
    
    # If the tweak already has a RegistrySettings array, ensure it's properly formatted
    if ($standardTweak.PSObject.Properties['RegistrySettings']) {
        if ($standardTweak.RegistrySettings -is [array]) {
            # Clean up each setting in the array
            $cleanedSettings = @()
            foreach ($setting in $standardTweak.RegistrySettings) {
                $cleanedSetting = @{
                    Path  = $setting.Path
                    Name  = $setting.Name
                    Value = $setting.Value
                    Type  = if ($setting.Type) { $setting.Type } else { "DWord" }
                }
                $cleanedSettings += $cleanedSetting
            }
            $standardTweak.RegistrySettings = $cleanedSettings
        }
        else {
            # If RegistrySettings is not an array, initialize it as an empty array
            $standardTweak.RegistrySettings = @()
        }
    }
    else {
        # Initialize the RegistrySettings array if it doesn't exist
        $standardTweak | Add-Member -MemberType NoteProperty -Name 'RegistrySettings' -Value @() -Force
    }
    # If the tweak contains a simple registry setting, add it to RegistrySettings
    if ($standardTweak.PSObject.Properties['RegistryPath'] -and $standardTweak.PSObject.Properties['ValueName']) {
        $registrySetting = @{
            Path  = $standardTweak.RegistryPath
            Name  = $standardTweak.ValueName
            Value = if ($standardTweak.PSObject.Properties['TweakValue']) { $standardTweak.TweakValue } else { $null }
            Type  = if ($standardTweak.PSObject.Properties['ValueType']) { $standardTweak.ValueType } else { "DWord" }
        }
        
        # Check if this setting already exists in RegistrySettings
        $settingExists = $false
        foreach ($existingSetting in $standardTweak.RegistrySettings) {
            if ($existingSetting.Path -eq $registrySetting.Path -and $existingSetting.Name -eq $registrySetting.Name) {
                $settingExists = $true
                break
            }
        }
        
        if (-not $settingExists) {
            $standardTweak.RegistrySettings += $registrySetting
        }
        
        # Do not remove individual properties to ensure backward compatibility
        # Die ApplyTweaks-Funktion kann nun mit beiden Formaten umgehen
    }
    
    # Ensure the tweak has a name
    if (-not $standardTweak.PSObject.Properties['Name'] -or [string]::IsNullOrWhiteSpace($standardTweak.Name)) {
        if ($standardTweak.PSObject.Properties['RegistryPath'] -and $standardTweak.PSObject.Properties['ValueName']) {
            $standardTweak | Add-Member -MemberType NoteProperty -Name 'Name' -Value "$($standardTweak.RegistryPath)\$($standardTweak.ValueName)" -Force
        }
        else {
            $standardTweak | Add-Member -MemberType NoteProperty -Name 'Name' -Value 'Unbenannter Tweak' -Force
        }
    }
    
    return $standardTweak
}

function Test-TweakDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]$Tweak
    )
    
    $issues = @()
    
    # Check if the tweak has a valid action
    $hasValidAction = ($Tweak.RegistryPath -and $Tweak.ValueName -ne $null) -or 
    ($Tweak.PSObject.Properties['RegistrySettings'] -and $Tweak.RegistrySettings -and $Tweak.RegistrySettings.Count -gt 0) -or
    ($Tweak.PSObject.Properties['InvokeScript'] -and $Tweak.InvokeScript -and $Tweak.InvokeScript.Count -gt 0)
    
    # If no valid action was found, check the required properties
    if (-not $hasValidAction) {
        $requiredProperties = @('Category', 'Name', 'Description')
        foreach ($prop in $requiredProperties) {
            if (-not $Tweak.PSObject.Properties[$prop] -or [string]::IsNullOrWhiteSpace($Tweak.$prop)) {
                $issues += "Empty required property: $prop"
            }
        }
    }
    
    # Check if either RegistrySettings or InvokeScript is present
    $hasRegistrySettings = $Tweak.PSObject.Properties['RegistrySettings'] -and $Tweak.RegistrySettings -and $Tweak.RegistrySettings.Count -gt 0
    $hasInvokeScript = $Tweak.PSObject.Properties['InvokeScript'] -and $Tweak.InvokeScript -and $Tweak.InvokeScript.Count -gt 0
    $hasRegistryPath = $Tweak.PSObject.Properties['RegistryPath'] -and $Tweak.RegistryPath -and $Tweak.PSObject.Properties['ValueName'] -and $Tweak.ValueName -ne $null
    
    if (-not $hasRegistrySettings -and -not $hasInvokeScript -and -not $hasRegistryPath) {
        $issues += "No valid action defined (neither RegistrySettings, InvokeScript, nor individual registry settings)"
    }
    
    # Check RegistrySettings if present
    if ($hasRegistrySettings) {
        foreach ($setting in $Tweak.RegistrySettings) {
            $requiredSettingProps = @('Path', 'Name', 'Value', 'Type')
            foreach ($prop in $requiredSettingProps) {
                if (-not $setting.ContainsKey($prop)) {
                    $issues += "Missing required property in RegistrySetting: $prop"
                }
            }
            
            # Check valid types
            $validTypes = @('String', 'DWord', 'QWord', 'Binary', 'ExpandString', 'MultiString')
            if ($setting.ContainsKey('Type') -and $setting.Type -notin $validTypes) {
                $issues += "Invalid registry type: $($setting.Type). Allowed types: $($validTypes -join ', ')"
            }
        }
    }
    
    # Ignore automatically added properties
    $ignoreProperties = @('IsReadOnly', 'IsFixedSize', 'IsSynchronized', 'Keys', 'Values', 'SyncRoot', 'Count')
    
    # Check for unknown properties (ignoring automatically added ones)
    $validProperties = @('Category', 'Name', 'Description', 'RegistryPath', 'ValueName', 'TweakValue', 'DefaultValue', 'ValueType', 'RegistrySettings', 'InvokeScript', 'UndoScript', 'Action', 'Service')
    foreach ($prop in $Tweak.PSObject.Properties.Name) {
        if ($prop -notin $validProperties -and $prop -notin $ignoreProperties) {
            $issues += "Unknown property: $prop"
        }
    }
    
    return [PSCustomObject]@{
        Name                = $Tweak.Name
        HasRegistrySettings = $hasRegistrySettings
        HasInvokeScript     = $hasInvokeScript
        Issues              = $issues
        IsValid             = $issues.Count -eq 0
    }
}

function CheckUpdates {
    # Function: Check for script updates
    param([string]$currentVersion = $scriptVersion, [string]$githubRawUrl = "https://raw.githubusercontent.com/leeshhi/shagutil/main/version.txt")
    try {
        $remoteVersionText = Invoke-RestMethod -Uri $githubRawUrl -ErrorAction Stop
        $remoteVersion = $remoteVersionText.Trim()
        $currentVersionObject = [Version]$currentVersion
        $remoteVersionObject = [Version]$remoteVersion

        if ($remoteVersionObject -gt $currentVersionObject) {
            return @{
                UpdateAvailable = $true;
                RemoteVersion   = $remoteVersion;
                CurrentVersion  = $currentVersion;
                RepoLink        = "https://github.com/leeshhi/shagutil"
            }
        }
        else {
            return @{ UpdateAvailable = $false }
        }
    }
    catch {
        return @{
            UpdateAvailable = $false;
            Error           = $_.Exception.Message
        }
    }
}

<#
.SYNOPSIS
    Executes a winget command with timeout and error handling.
.DESCRIPTION
    Runs winget with the specified arguments, captures output and errors, and handles timeouts.
    Writes detailed logs to a temporary file for debugging purposes.
.PARAMETER arguments
    The arguments to pass to winget
.PARAMETER timeoutSeconds
    Maximum time to wait for the command to complete (default: 120 seconds)
.OUTPUTS
    Returns a PSCustomObject with the following properties:
    - ExitCode: The exit code from winget (or $null if error/timeout)
    - Output: Standard output from the command
    - Errors: Standard error output
    - TimedOut: Boolean indicating if the command timed out
    - LogPath: Path to the log file with full command details
#>
function Invoke-WingetCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$arguments,
        
        [Parameter()]
        [ValidateRange(10, 600)] # 10 seconds to 10 minutes
        [int]$timeoutSeconds = 120
    )
    
    # Check if winget is available
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{
            ExitCode   = $null
            Output     = ""
            Errors     = "Winget is not installed or not available in PATH."
            TimedOut   = $false
            LogPath    = $null
        }
    }
    
    $logPath = [System.IO.Path]::GetTempFileName()
    $process = $null
    
    try {
        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = "winget"
        $processInfo.Arguments = $arguments
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true
        $processInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $processInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        
        # Log command start
        "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Starting: winget $arguments" | Out-File -FilePath $logPath -Force
        
        $startTime = Get-Date
        $process.Start() | Out-Null
        
        # Read output asynchronously
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()
        
        if ($process.WaitForExit($timeoutSeconds * 1000)) {
            $output = $outputTask.Result
            $errors = $errorTask.Result
            $exitCode = $process.ExitCode
            $duration = (Get-Date) - $startTime
            
            # Log results
            "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] Exit Code: $exitCode" | Out-File -FilePath $logPath -Append
            "Duration: $($duration.TotalSeconds.ToString('0.00')) seconds" | Out-File -FilePath $logPath -Append
            "`n--- OUTPUT ---`n$output`n" | Out-File -FilePath $logPath -Append
            
            if (-not [string]::IsNullOrWhiteSpace($errors)) {
                "`n--- ERRORS ---`n$errors`n" | Out-File -FilePath $logPath -Append
            }
            
            return [PSCustomObject]@{
                ExitCode   = $exitCode
                Output     = $output
                Errors     = $errors
                TimedOut   = $false
                LogPath    = $logPath
            }
        }
        else {
            # Command timed out
            $process.Kill()
            $errorMsg = "Winget command timed out after ${timeoutSeconds} seconds. See log for details: $logPath"
            
            "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] COMMAND TIMED OUT" | Out-File -FilePath $logPath -Append
            $errorMsg | Out-File -FilePath $logPath -Append
            
            return [PSCustomObject]@{
                ExitCode   = $null
                Output     = ""
                Errors     = $errorMsg
                TimedOut   = $true
                LogPath    = $logPath
            }
        }
    }
    catch [System.Exception] {
        $errorMsg = "Unexpected error when running winget: $_"
        "`n[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] ERROR: $errorMsg" | Out-File -FilePath $logPath -Append
        $_.ScriptStackTrace | Out-File -FilePath $logPath -Append
        
        return [PSCustomObject]@{
            ExitCode   = $null
            Output     = ""
            Errors     = $errorMsg
            TimedOut   = $false
            LogPath    = $logPath
        }
    }
    finally {
        if ($null -ne $process) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                }
                $process.Dispose()
            }
            catch {
                # Ignore errors during cleanup
            }
        }
    }
}
#endregion

#region 3. Main Form & TabControl Setup
$global:hasChanges = $false
$global:restartNeeded = $false
$global:IgnoreCheckEvent = $false # For General tab TreeView
$global:IgnoreCheckEventDownloads = $false # For Downloads tab TreeView
# Form
$form = New-Object System.Windows.Forms.Form
$form.MinimumSize = New-Object System.Drawing.Size(600, 700)
$form.Text = "Shag Windows Utility - Version $scriptVersion"
$form.Size = New-Object System.Drawing.Size(700, 800)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'Sizable' #FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ForeColor = [System.Drawing.Color]::Black
$form.Font = New-Object System.Drawing.Font("Segoe UI", 11)

# TabControl setup  #  > Make tab size bigger
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = 'Fill'
$tabControl.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed

$tabControl.Add_DrawItem({ # DrawItem Event for individual tab text color
        param($sender, $e)
        $tab = $sender.TabPages[$e.Index]
        $font = $tabControl.Font
        $text = $tab.Text

        if ($text -eq "Untested") {
            $color = [System.Drawing.Color]::Red
        }
        else {
            $color = [System.Drawing.Color]::Black
        }

        $rect = $sender.GetTabRect($e.Index)
        if ($rect -is [System.Array]) { $rect = $rect[0] } # Ensure it's a single Rectangle
        $e.Graphics.FillRectangle([System.Drawing.Brushes]::DeepSkyBlue, $rect)
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
        $pointX = [float]($rect.X) + ([float]($rect.Width) / 2)
        $pointY = [float]($rect.Y) + ([float]($rect.Height) / 2)
        $point = New-Object System.Drawing.PointF($pointX, $pointY)
        $brush = New-Object System.Drawing.SolidBrush($color)
        $e.Graphics.DrawString($text, $font, $brush, $point, $sf)
        $brush.Dispose()
    })
    
[void]$form.Controls.Add($tabControl)

$form.Add_Load({ # Form Load Event (for Update Check)
        $updateInfo = CheckUpdates
        if ($updateInfo.UpdateAvailable) {
            Clear-Host
            Write-Host ""
            Write-Host ">>> UPDATE AVAILABLE! <<<" -ForegroundColor Red
            Write-Host "A new version ($($updateInfo.RemoteVersion)) is available!" -ForegroundColor Yellow
            Write-Host "Your current version is $($updateInfo.CurrentVersion)." -ForegroundColor Yellow
            Write-Host "Run the start command again to use the new version." -ForegroundColor Yellow
            Write-Host ""
        }
        elseif ($updateInfo.Error) {
            [System.Windows.Forms.MessageBox]::Show(
                "Error checking for updates: $($updateInfo.Error)",
                "Update Error",
                [System.Windows.Forms.MessageBoxButtons]::OK,
                [System.Windows.Forms.MessageBoxIcon]::Warning
            )
        }
        $null
    })
#endregion

#region 4. Tab: Home
$tabHome = New-Object System.Windows.Forms.TabPage "Home"
[void]$tabControl.TabPages.Add($tabHome)

function Initialize-HomeTabContent {
    param($systemInfoPanel, $form, $systemInfoTitle)
    $controlsToRemove = $systemInfoPanel.Controls | Where-Object { $_ -ne $systemInfoTitle }

    foreach ($control in $controlsToRemove) {
        $systemInfoPanel.Controls.Remove($control)
        $control.Dispose()
    }

    $loadingLabel = New-Object System.Windows.Forms.Label
    $loadingLabel.Text = "Loading system information, please wait..."
    $loadingLabel.AutoSize = $true
    $loadingLabel.Location = New-Object System.Drawing.Point(10, 40)
    [void]$systemInfoPanel.Controls.Add($loadingLabel)
    $form.Refresh()

    $job = Start-Job -ScriptBlock {
        function Get-OsInfo {
            try {
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                return "OS: $($os.Caption) Version $($os.Version) (Build $($os.BuildNumber))"
            }
            catch { return "OS: Error retrieving info ($($_.Exception.Message))" }
        }
        function Get-CpuInfo {
            try {
                $cpu = Get-CimInstance Win32_Processor -ErrorAction Stop
                return "CPU: $($cpu.Name) ($($cpu.NumberOfCores) Cores, $($cpu.NumberOfLogicalProcessors) Threads)"
            }
            catch { return "CPU: Error retrieving info ($($_.Exception.Message))" }
        }
        function Get-RamInfo {
            try {
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $ram = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                $totalMemoryGB = [Math]::Round(($ram.TotalPhysicalMemory / 1GB), 2)
                $freeMemoryGB = [Math]::Round(($os.FreePhysicalMemory / (1024 * 1024)), 2)
                return "RAM: ${totalMemoryGB}GB Total / ${freeMemoryGB}GB Available"
            }
            catch { return "RAM: Error retrieving info ($($_.Exception.Message))" }
        }
        function Get-GpuInfo {
            try {
                $gpus = Get-CimInstance Win32_VideoController -ErrorAction Stop | Select-Object Name
                $gpuStrings = @()
                foreach ($gpu in $gpus) { $gpuStrings += "$($gpu.Name)" }
                if ($gpuStrings.Count -gt 0) { return "GPU: " + ($gpuStrings -join ", ") } else { return "GPU: Not found" }
            }
            catch { return "GPU: Error retrieving info ($($_.Exception.Message))" }
        }
        function Get-MotherboardInfo {
            try {
                $board = Get-CimInstance Win32_BaseBoard -ErrorAction Stop
                return "Motherboard: $($board.Manufacturer) $($board.Product)"
            }
            catch { return "Motherboard: Error retrieving info ($($_.Exception.Message))" }
        }
        function Get-BiosInfo {
            try {
                $bios = Get-CimInstance Win32_BIOS -ErrorAction Stop
                return "BIOS: $($bios.Caption) Version $($bios.SMBIOSBIOSVersion) (Date: $($bios.ReleaseDate))"
            }
            catch { return "BIOS: Error retrieving info ($($_.Exception.Message))" }
        }
        function Get-NetworkInfo {
            try {
                return "Device Name: $env:COMPUTERNAME"
            }
            catch { return "Network: Error retrieving info ($($_.Exception.Message))" }
        }
        function Get-SystemInformation { 
            @((Get-OsInfo), (Get-CpuInfo), (Get-RamInfo), (Get-GpuInfo), (Get-MotherboardInfo), (Get-BiosInfo), (Get-NetworkInfo)) 
        }
        Get-SystemInformation
    }

    $jobMonitorTimer = New-Object System.Windows.Forms.Timer
    $jobMonitorTimer.Interval = 500
    $jobMonitorTimer.Tag = @{
        Job             = $job;
        LoadingLabel    = $loadingLabel;
        SystemInfoPanel = $systemInfoPanel;
        Form            = $form;
        SystemInfoTitle = $systemInfoTitle
    }
    $jobMonitorTimer.Add_Tick({
            param($sender, $eventArgs) # $sender is the timer itself
            $data = $sender.Tag
            $currentJob = $data.Job
            $loadingLabel = $data.LoadingLabel
            $systemInfoPanel = $data.SystemInfoPanel
            $form = $data.Form
            $systemInfoTitle = $data.SystemInfoTitle

            if ($currentJob -eq $null -or $systemInfoPanel -eq $null -or $loadingLabel -eq $null -or $form -eq $null) {
                $sender.Stop()
                $sender.Dispose()
                if ($loadingLabel -ne $null -and $systemInfoPanel -ne $null -and $systemInfoPanel.Controls.Contains($loadingLabel)) {
                    $systemInfoPanel.Controls.Remove($loadingLabel)
                    $loadingLabel.Dispose()
                }
                [System.Windows.Forms.MessageBox]::Show("A critical UI component or job reference was lost. Please restart the application.", "Fatal Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }

            if ($currentJob.State -eq 'Completed') {
                $sender.Stop()
                $sender.Dispose() # Dispose the timer itself
                if ($systemInfoPanel.Controls.Contains($loadingLabel)) {
                    $systemInfoPanel.Controls.Remove($loadingLabel)
                    $loadingLabel.Dispose()
                }
                $systemInfoLabels = Receive-Job $currentJob
                $yPos = 40
                foreach ($line in $systemInfoLabels) {
                    if ($line -is [array]) {
                        foreach ($subLine in $line) {
                            $label = New-Object System.Windows.Forms.Label
                            $label.Text = $subLine
                            $label.AutoSize = $true
                            $label.Location = New-Object System.Drawing.Point(10, $yPos)
                            [void]$systemInfoPanel.Controls.Add($label)
                            $yPos += 25
                        }
                    }
                    else {
                        $label = New-Object System.Windows.Forms.Label
                        $label.Text = $line
                        $label.AutoSize = $true
                        $label.Location = New-Object System.Drawing.Point(10, $yPos)
                        [void]$systemInfoPanel.Controls.Add($label)
                        $yPos += 25
                    }
                }
                $systemInfoPanel.Refresh()
                Remove-Job $currentJob -Force
            }
            elseif ($currentJob.State -eq 'Failed' -or $currentJob.State -eq 'Stopped') {
                $sender.Stop()
                $sender.Dispose() # Dispose the timer itself
                if ($systemInfoPanel.Controls.Contains($loadingLabel)) {
                    $systemInfoPanel.Controls.Remove($loadingLabel)
                    $loadingLabel.Dispose()
                }
                $jobError = Receive-Job $currentJob -ErrorAction SilentlyContinue | Out-String
                [System.Windows.Forms.MessageBox]::Show(
                    "Error loading system information: $($currentJob.JobStateInfo.Reason)`n`nDetails: $($jobError)",
                    "Loading Error",
                    [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error
                )
                Remove-Job $currentJob -Force
            }
        })
    $jobMonitorTimer.Start()
}

# Main container for the Home tab
$homeContainer = New-Object System.Windows.Forms.TableLayoutPanel
$homeContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$homeContainer.RowCount = 2
$homeContainer.ColumnCount = 1
[void]$homeContainer.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 440)))  # 400 + 20px padding top + 20px gap
[void]$homeContainer.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$homeContainer.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$homeContainer.Padding = New-Object System.Windows.Forms.Padding(20)
[void]$tabHome.Controls.Add($homeContainer)

# Panel for System Information (top section)
$systemInfoPanel = New-Object System.Windows.Forms.Panel
$systemInfoPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$systemInfoPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
[void]$homeContainer.Controls.Add($systemInfoPanel, 0, 0)

# Title for System Information in the panel
$systemInfoTitle = New-Object System.Windows.Forms.Label
$systemInfoTitle.Text = "System Information"
$systemInfoTitle.Font = New-Object System.Drawing.Font($systemInfoTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
$systemInfoTitle.AutoSize = $true
$systemInfoTitle.Location = New-Object System.Drawing.Point(10, 10)
[void]$systemInfoPanel.Controls.Add($systemInfoTitle)

# Container for the bottom section (Quick Links + Contact)
$bottomContainerPanel = New-Object System.Windows.Forms.Panel
$bottomContainerPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
[void]$homeContainer.Controls.Add($bottomContainerPanel, 0, 1)

# Create a table layout for the bottom section
$tableLayout = New-Object System.Windows.Forms.TableLayoutPanel
$tableLayout.Dock = [System.Windows.Forms.DockStyle]::Fill
$tableLayout.ColumnCount = 2
$tableLayout.RowCount = 1
[void]$tableLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Absolute, 240)))  # Fixed width for Quick Links
[void]$tableLayout.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))  # Rest for Contact
[void]$tableLayout.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$tableLayout.CellBorderStyle = [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::Single
[void]$bottomContainerPanel.Controls.Add($tableLayout)

# Panel for Quick Links (left side)
$quickLinksPanel = New-Object System.Windows.Forms.Panel
$quickLinksPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$quickLinksPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$quickLinksPanel.AutoScroll = $true
[void]$tableLayout.Controls.Add($quickLinksPanel, 0, 0)

# Title for Quick Links
$quickLinksTitle = New-Object System.Windows.Forms.Label
$quickLinksTitle.Text = "Quick Links"
$quickLinksTitle.Font = New-Object System.Drawing.Font($quickLinksTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
$quickLinksTitle.AutoSize = $true
$quickLinksTitle.Location = New-Object System.Drawing.Point(10, 10)
[void]$quickLinksPanel.Controls.Add($quickLinksTitle)

# Quick Links Buttons
$buttonYPos = 40
$quickLinks = @(
    @{"Text" = "Task Manager"; "Action" = { Start-Process taskmgr.exe } },
    @{"Text" = "Device Manager"; "Action" = { Start-Process devmgmt.msc } },
    @{"Text" = "Control Panel"; "Action" = { Start-Process control.exe } },
    @{"Text" = "Disk Management"; "Action" = { Start-Process diskmgmt.msc } }
)

foreach ($link in $quickLinks) {
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $link.Text
    $button.Size = New-Object System.Drawing.Size(180, 30)
    $button.Location = New-Object System.Drawing.Point(10, $buttonYPos)
    $button.BackColor = [System.Drawing.Color]::DodgerBlue
    $button.Add_Click($link.Action)
    [void]$quickLinksPanel.Controls.Add($button)
    $buttonYPos += 35
}

# Contact Panel (right side)
$contactPanel = New-Object System.Windows.Forms.Panel
$contactPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$contactPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$contactPanel.AutoScroll = $true
[void]$tableLayout.Controls.Add($contactPanel, 1, 0)

# Title for Contact
$contactTitle = New-Object System.Windows.Forms.Label
$contactTitle.Text = "Connect with me"
$contactTitle.Font = New-Object System.Drawing.Font($contactTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
$contactTitle.AutoSize = $true
$contactTitle.Location = New-Object System.Drawing.Point(10, 10)
[void]$contactPanel.Controls.Add($contactTitle)

# Contact Information (LinkLabels)
$contactYPos = 40
$websiteLink = New-Object System.Windows.Forms.LinkLabel
$websiteLink.Text = "Website"
$websiteLink.AutoSize = $true
$websiteLink.Location = New-Object System.Drawing.Point(10, $contactYPos)
$websiteLink.Add_LinkClicked({ Start-Process "https://shag.gg" })
[void]$contactPanel.Controls.Add($websiteLink)
$contactYPos += 25

$githubLink = New-Object System.Windows.Forms.LinkLabel
$githubLink.Text = "GitHub"
$githubLink.AutoSize = $true
$githubLink.Location = New-Object System.Drawing.Point(10, $contactYPos)
$githubLink.Add_LinkClicked({ Start-Process "https://github.com/leeshhi" })
[void]$contactPanel.Controls.Add($githubLink)
$contactYPos += 25

$discordLink = New-Object System.Windows.Forms.LinkLabel
$discordLink.Text = "Discord"
$discordLink.AutoSize = $true
$discordLink.Location = New-Object System.Drawing.Point(10, $contactYPos)
$discordLink.Add_LinkClicked({ Start-Process "https://discord.gg/gDmjYgydb3" })
[void]$contactPanel.Controls.Add($discordLink)
$contactYPos += 25

$discord2Link = New-Object System.Windows.Forms.LinkLabel
$discord2Link.Text = "Discord (Shag.gg)"
$discord2Link.AutoSize = $true
$discord2Link.Location = New-Object System.Drawing.Point(10, $contactYPos)
$discord2Link.Add_LinkClicked({ Start-Process "https://discord.gg/qxPNcgtTqn" })
[void]$contactPanel.Controls.Add($discord2Link)
$contactYPos += 25
#endregion

#region 5. Tab: Tweaks
$tabTweaks = New-Object System.Windows.Forms.TabPage "Tweaks"
[void]$tabControl.TabPages.Add($tabTweaks)

function Create-RegistryPSPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    return $Path -replace '^HKLM\\', 'HKLM:\\' -replace '^HKCU\\', 'HKCU:\\' -replace '^HKU\\', 'HKU:\\' -replace '^HKCR\\', 'HKCR:\\' -replace '^HKCC\\', 'HKCC:\\'
}

function Get-RegistryValue {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Name
    )
    try {
        # Convert registry path to PowerShell format (add colon after HKLM, HKCU, etc.)
        $psPath = Create-RegistryPSPath -Path $Path
        
        if (Test-Path -LiteralPath $psPath -ErrorAction SilentlyContinue) {
            $value = Get-ItemProperty -Path $psPath -Name $Name -ErrorAction SilentlyContinue | 
            Select-Object -ExpandProperty $Name -ErrorAction SilentlyContinue
            return $value
        }
    }
    catch {
        # Fehler unterdrücken, keine Ausgabe erzeugen
        # Für Debugging können Sie die folgende Zeile einkommentieren:
        # Write-Debug "Could not get registry value '$Name' from '$psPath': $($_.Exception.Message)"
    }
    return $null # Return $null if path or name does not exist, or on error
}

function Set-RegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $false)]
        $Value,
        [Parameter(Mandatory = $true)]
        [ValidateSet("DWord", "String", "ExpandString", "Binary", "MultiString", "QWord")]
        [string]$Type,
        [switch]$RemoveEntry
    )
    
    # Convert registry path to PowerShell format (add colon after HKLM, HKCU, etc.)
    $psPath = Create-RegistryPSPath -Path $Path
    
    # Check if running as administrator for HKLM access
    if ($psPath -like 'HKLM:*' -or $psPath -like 'HKCR:*' -or $psPath -like 'HKCC:*') {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        if (-not $isAdmin) {
            Write-Host "  [WARNING] Administrator rights required for $psPath. Please run as administrator." -ForegroundColor Yellow
            return $false
        }
    }
    
    try {
        # Create the registry key if it doesn't exist
        if (-not (Test-Path -Path $psPath)) {
            try {
                $null = New-Item -Path $psPath -Force -ErrorAction Stop
                Write-Host "  [INFO] Created registry path: $psPath" -ForegroundColor Green
            }
            catch {
                Write-Host "  [ERROR] Failed to create registry path '$psPath': $_" -ForegroundColor Red
                return $false
            }
        }
        
        # Handle RemoveEntry case
        if ($RemoveEntry) {
            if (Test-Path -Path $psPath) {
                $prop = Get-ItemProperty -Path $psPath -Name $Name -ErrorAction SilentlyContinue
                if ($null -ne $prop) {
                    Remove-ItemProperty -Path $psPath -Name $Name -Force -ErrorAction Stop
                    Write-Host "  [SUCCESS] Removed registry value: $Name from $Path" -ForegroundColor Green
                    return $true
                }
                else {
                    Write-Host "  [INFO] Registry value $Name does not exist in $Path" -ForegroundColor Cyan
                    return $true
                }
            }
            return $true
        }
        
        # Convert value based on type
        $valueToSet = switch ($Type) {
            "DWord" { try { [int32]::Parse($Value) } catch { [int32]0 } }
            "QWord" { try { [int64]::Parse($Value) } catch { [int64]0 } }
            "String" { [string]$Value }
            "ExpandString" { [string]$Value }
            "Binary" { [byte[]]($Value -split ',' | ForEach-Object { [byte]$_ }) }
            "MultiString" { [string[]]$Value }
            default { $Value }
        }
        
        # Check current value
        $currentValue = $null
        if (Test-Path -Path $psPath) {
            $currentValue = Get-ItemProperty -Path $psPath -Name $Name -ErrorAction SilentlyContinue | 
            Select-Object -ExpandProperty $Name -ErrorAction SilentlyContinue
        }
        
        # Compare and set if different
        if ($null -eq $currentValue -or $currentValue -ne $valueToSet) {
            # Create the key if it doesn't exist
            if (-not (Test-Path -Path $psPath)) {
                $null = New-Item -Path $psPath -Force -ErrorAction Stop
            }
            
            # Set the value
            $null = New-ItemProperty -Path $psPath -Name $Name -Value $valueToSet -PropertyType $Type -Force -ErrorAction Stop
            
            $displayValue = if ($Type -eq "DWord" -or $Type -eq "QWord") { 
                "0x$($valueToSet.ToString('X')) ($valueToSet)" 
            }
            else { 
                "'$valueToSet'"
            }
            Write-Host "  [SUCCESS] Set $Name to $displayValue in $Path" -ForegroundColor Green
            return $true
        }
        else {
            $displayValue = if ($Type -eq "DWord" -or $Type -eq "QWord") { 
                "0x$($currentValue.ToString('X')) ($currentValue)" 
            }
            else { 
                "'$currentValue'" 
            }
            Write-Host "  [INFO] $Name is already set to $displayValue in $Path" -ForegroundColor Cyan
            return $true
        }
    }
    catch {
        Write-Host "  [ERROR] Failed to set registry value '$Name' in '$Path': $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Get-ServiceStatus {
    # Function to get service start type
    param([string]$ServiceName)
    try {
        $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
        if ($service) {
            switch ($service.StartType) {
                "Boot" { return 0 }
                "System" { return 1 }
                "Automatic" { return 2 }
                "Manual" { return 3 }
                "Disabled" { return 4 }
                default { return $null }
            }
        }
        return $null
    }
    catch {
        Write-Warning ("Could not get start type for service {0}: {1}" -f $ServiceName, $_)
        return $null
    }
}

function Set-ServiceStartType {
    # Function to set service start type
    param([string]$ServiceName, [int]$StartType)
    try {
        Set-Service -Name $ServiceName -StartupType ([System.ServiceProcess.ServiceStartMode]$StartType) -ErrorAction Stop
        # Optionally, restart service if it was running and changed to Automatic/Manual
        # Get-Service -Name $ServiceName | Restart-Service -ErrorAction SilentlyContinue
        $global:hasChanges = $true
        $global:restartNeeded = $true
        return $true
    }
    catch {
        Write-Warning ("Could not set start type for service {0} to {1}: {2}" -f $ServiceName, $StartType, $_)
        return $false
    }
}

function ApplyTweaks {
    param([System.Windows.Forms.TreeView]$treeViewToApply)
    $selectedNodes = @($treeViewToApply.Nodes | Where-Object { $_.Checked -eq $true }) + 
    @($treeViewToApply.Nodes | ForEach-Object { $_.Nodes } | Where-Object { $_.Checked -eq $true })
    
    foreach ($node in $selectedNodes) {
        $tweak = $node.Tag
        if (-not $tweak) { continue }
        
        if ($tweak -is [System.Collections.Hashtable] -or $tweak -is [System.Collections.Specialized.OrderedDictionary]) { # Convert Hashtable to PSCustomObject if necessary
            $tweak = [PSCustomObject]$tweak
            $node.Tag = $tweak  # Update the tag with the converted object
        }
        
        $tweakName = if ($tweak.PSObject.Properties['Name'] -and $tweak.Name) { 
            $tweak.Name 
        }
        else { 
            "Unnamed Tweak" 
        }
        
        Write-Host "Applying tweak: $tweakName" -ForegroundColor Cyan
        $actionTaken = $false
        #Write-Host "Processing tweak: $tweakName" -ForegroundColor Cyan # Debug output
        
        if ($tweak.PSObject.Properties['InvokeScript'] -and $tweak.InvokeScript) { # 1. Prüfe auf InvokeScript (hat Vorrang)
            Write-Host "  -> Executing InvokeScript..." -ForegroundColor Yellow
            foreach ($script in $tweak.InvokeScript) {
                try {
                    Invoke-Expression $script | Out-Null
                    Write-Host "  -> Script executed successfully" -ForegroundColor Green
                    $actionTaken = $true
                }
                catch {
                    Write-Host "  -> Error executing script: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            if ($actionTaken) { continue }
        }
        
        if ($tweak.PSObject.Properties['RegistrySettings'] -and $tweak.RegistrySettings) { # 2. Prüfe auf RegistrySettings (Array von Einstellungen)
            foreach ($setting in $tweak.RegistrySettings) {
                try {
                    $result = Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -RemoveEntry:($setting.Value -eq "<RemoveEntry>")
                    if ($result) {
                        $action = if ($setting.Value -eq "<RemoveEntry>") { "Removed" } else { "Set" }
                        Write-Host "  -> [$action] $($setting.Name) in $($setting.Path)" -ForegroundColor Green
                        $actionTaken = $true
                    }
                }
                catch {
                    Write-Host "  -> Error applying setting $($setting.Name): $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            if ($actionTaken) { continue }
        }
        
        if ($tweak.PSObject.Properties['RegistryPath'] -and $tweak.RegistryPath -and 
            $tweak.PSObject.Properties['ValueName'] -and $tweak.ValueName -ne $null) { # 3. Prüfe auf einfache Registry-Einstellungen
            $value = if ($tweak.PSObject.Properties['TweakValue']) { $tweak.TweakValue } else { $null }
            $type = if ($tweak.PSObject.Properties['ValueType']) { $tweak.ValueType }else { "DWord" }
            
            try {
                $result = Set-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName -Value $value -Type $type -RemoveEntry:($value -eq "<RemoveEntry>")
                if ($result) {
                    $action = if ($value -eq "<RemoveEntry>") { "Entfernt" } else { "Gesetzt" }
                    Write-Host "  -> [$action] $($tweak.ValueName) in $($tweak.RegistryPath)" -ForegroundColor Green
                    $actionTaken = $true
                }
            }
            catch {
                Write-Host "  -> Error applying setting $($tweak.ValueName): $($_.Exception.Message)" -ForegroundColor Red
            }
            if ($actionTaken) { continue }
        }
        
        if (-not $actionTaken) { # 4. If nothing else worked
            Write-Host "  -> No executable action found for this tweak. Required properties may be missing." -ForegroundColor Yellow
            Write-Host "     Available properties: $($tweak.PSObject.Properties.Name -join ', ')" -ForegroundColor Gray
        }
    }
    
    [System.Windows.Forms.MessageBox]::Show("Selected tweaks applied. Some changes may require a system restart.", "Tweaks Applied", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Update-GeneralTweaksStatus -tweakNodes $allTweakNodes # Update status after applying
}

function ResetTweaks {
    param([System.Windows.Forms.TreeView]$treeViewToReset)
    $selectedNodes = @($treeViewToReset.Nodes | Where-Object { $_.Checked -eq $true }) + @($treeViewToReset.Nodes | ForEach-Object { $_.Nodes } | Where-Object { $_.Checked -eq $true })

    foreach ($node in $selectedNodes) {
        $tweak = $node.Tag
        if ($tweak) {
            Write-Host "Resetting tweak: $($tweak.Name)" -ForegroundColor Cyan
            if ($tweak.RegistrySettings) {
                foreach ($setting in $tweak.RegistrySettings) {
                    $remove = ($setting.OriginalValue -eq "<RemoveEntry>")
                    $result = Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.OriginalValue -Type $setting.Type -RemoveEntry $remove
                    if ($result) {
                        Write-Host "  -> Reset registry setting: $($setting.Name) in $($setting.Path)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  -> Failed to reset registry setting: $($setting.Name) in $($setting.Path)" -ForegroundColor Red
                    }
                }
            }
            elseif ($tweak.RegistryPath -and $tweak.ValueName) {
                if ($tweak.Action -eq "Service") {
                    try {
                        Set-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName -Value $tweak.DefaultValue -Type $tweak.ValueType
                        Set-Service -Name $tweak.Service -StartupType $tweak.DefaultValue -ErrorAction Stop # DefaultValue is the startup type
                        Write-Host "  -> Reset service '$($tweak.Service)' startup type to '$($tweak.DefaultValue)' and updated registry." -ForegroundColor Green
                    }
                    catch {
                        Write-Host "  -> Failed to reset service '$($tweak.Service)': $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                else {
                    $remove = ($tweak.DefaultValue -eq "<RemoveEntry>")
                    $result = Set-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName -Value $tweak.DefaultValue -Type $tweak.ValueType -RemoveEntry $remove
                    if ($result) {
                        Write-Host "  -> Reset registry tweak: $($tweak.Name)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  -> Failed to reset registry tweak: $($tweak.Name)" -ForegroundColor Red
                    }
                }
            }
            if ($tweak.UndoScript) {
                Write-Host "  -> Executing UndoScript for $($tweak.Name)..." -ForegroundColor Yellow
                foreach ($command in $tweak.UndoScript) {
                    try {
                        Invoke-Expression $command
                        Write-Host "    - Executed: '$command'" -ForegroundColor DarkGreen
                    }
                    catch {
                        Write-Warning "    - Failed to execute undo command '$command': $($_.Exception.Message)"
                    }
                }
            }
            else {
                Write-Warning "Tweak '$($tweak.Name)' has no valid registry settings or action defined to reset."
            }
        }
    }
    [System.Windows.Forms.MessageBox]::Show("Selected tweaks reset to default. Some changes may require a system restart.", "Tweaks Reset", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    Update-GeneralTweaksStatus -tweakNodes $allTweakNodes # Update status after resetting
}

function Update-GeneralTweaksStatus {
    param(
        [System.Collections.Generic.List[System.Windows.Forms.TreeNode]]$tweakNodes,
        [switch]$Verbose
    )
    
    foreach ($node in $tweakNodes) {
        $tweak = $node.Tag
        if (-not $tweak) { continue }
        
        if ($tweak -is [System.Collections.Hashtable] -or $tweak -is [System.Collections.Specialized.OrderedDictionary]) { # Convert Hashtable to PSCustomObject if necessary
            $tweak = [PSCustomObject]$tweak
            $node.Tag = $tweak  # Update the tag with the converted object
        }
        
        $tweakName = if ($tweak.PSObject.Properties['Name'] -and $tweak.Name) { # Get tweak name
            $tweak.Name 
        }
        else { 
            "Unnamed Tweak" 
        }
        
        # Initialize status variables
        $isApplied = $false
        $statusText = @()
        $hasAnyCheck = $false
        
        if ($tweak.RegistryPath -and $tweak.ValueName -ne $null) { # 1. Check for simple registry settings
            $hasAnyCheck = $true
            $currentValue = Get-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName
            $expectedValue = if ($tweak.PSObject.Properties['TweakValue']) { $tweak.TweakValue } else { $null }
            
            if ($Verbose) {
                Write-Host "[DEBUG] Checking $tweakName" -ForegroundColor Cyan
                Write-Host "  Path: $($tweak.RegistryPath)" -ForegroundColor Gray
                Write-Host "  ValueName: $($tweak.ValueName)" -ForegroundColor Gray
                Write-Host "  Expected: $expectedValue (Type: $($expectedValue.GetType().Name))" -ForegroundColor Gray
                Write-Host "  Current: $currentValue (Type: $(if($currentValue){$currentValue.GetType().Name}else{'null'}))" -ForegroundColor Gray
            }
            
            if ($expectedValue -eq "<RemoveEntry>") {
                $isApplied = ($currentValue -eq $null)
                $statusText += "Remove $($tweak.ValueName) from $($tweak.RegistryPath): $(if ($isApplied) {'✓ Applied'} else {'✗ Not applied'})"
            }
            else { # Improved comparison handling different data types
                $isApplied = $false
                if ($currentValue -ne $null) { # Handle different data types properly
                    if ($expectedValue -is [int] -or $expectedValue -is [long]) {
                        $isApplied = ([int]$currentValue -eq [int]$expectedValue)
                    }
                    elseif ($expectedValue -is [string]) {
                        $isApplied = ([string]$currentValue -eq [string]$expectedValue)
                    }
                    else {
                        $isApplied = ($currentValue -eq $expectedValue)
                    }
                }
                $statusText += "Set $($tweak.ValueName) to '$expectedValue' in $($tweak.RegistryPath): $(if ($isApplied) {'✓ Applied'} else {'✗ Not applied'})"
                if (-not $isApplied -and $currentValue -ne $null) {
                    $statusText += "Current value: $currentValue (Type: $($currentValue.GetType().Name))"
                }
            }
        }
        
        elseif ($tweak.PSObject.Properties['RegistrySettings'] -and $tweak.RegistrySettings) { # 2. Check for RegistrySettings array
            $allSettingsApplied = $true
            $hasSettings = $false
            
            foreach ($setting in $tweak.RegistrySettings) {
                $hasSettings = $true
                $hasAnyCheck = $true
                $currentValue = Get-RegistryValue -Path $setting.Path -Name $setting.Name
                
                if ($setting.Value -eq "<RemoveEntry>") {
                    $settingApplied = ($currentValue -eq $null)
                    $statusText += "Remove $($setting.Name) from $($setting.Path): $(if ($settingApplied) {'✓ Applied'} else {'✗ Not applied'})"
                }
                else { # Improved comparison for RegistrySettings
                    $settingApplied = $false
                    if ($currentValue -ne $null) { # Handle different data types properly
                        if ($setting.Value -is [int] -or $setting.Value -is [long]) {
                            $settingApplied = ([int]$currentValue -eq [int]$setting.Value)
                        }
                        elseif ($setting.Value -is [string]) {
                            $settingApplied = ([string]$currentValue -eq [string]$setting.Value)
                        }
                        else {
                            $settingApplied = ($currentValue -eq $setting.Value)
                        }
                    }
                    $statusText += "Set $($setting.Name) to '$($setting.Value)' in $($setting.Path): $(if ($settingApplied) {'✓ Applied'} else {'✗ Not applied'})"
                    if (-not $settingApplied -and $currentValue -ne $null) {
                        $statusText += "Current value: $currentValue (Type: $($currentValue.GetType().Name))"
                    }
                }
                
                if (-not $settingApplied) {
                    $allSettingsApplied = $false
                }
            }
            
            $isApplied = $hasSettings -and $allSettingsApplied
        }
        
        if ($tweak.PSObject.Properties['InvokeScript'] -and $tweak.InvokeScript) { # 3. Check for InvokeScript (cannot be reliably verified)
            $hasAnyCheck = $true
            if ($tweak.PSObject.Properties['IsApplied'] -and $tweak.IsApplied) {
                $isApplied = $true
                $statusText += "Script execution: Successful (manually confirmed)"
            }
            else {
                $isApplied = $false
                $statusText += "Script execution: Not verified (manual verification required)"
            }
        }
        
        if ($tweak.Action -eq "Service" -and $tweak.Service) { # 4. Special handling for Service tweaks
            $hasAnyCheck = $true
            try {
                $service = Get-Service -Name $tweak.Service -ErrorAction Stop
                $startupType = (Get-CimInstance -ClassName Win32_Service -Filter "Name='$($tweak.Service)'" -ErrorAction Stop).StartMode
                $expectedStartupType = $tweak.TweakValue
                
                $isApplied = ($startupType -eq $expectedStartupType)
                $statusText += "Service '$($tweak.Service)': Startup type is '$startupType' (should be: '$expectedStartupType')"
            }
            catch {
                $isApplied = $false
                $statusText += "Service '$($tweak.Service)': Could not verify status: $($_.Exception.Message)"
            }
        }
        
        if (-not $hasAnyCheck) { # If no verification was possible, indicate that the status is unknown
            $statusText += "No verification method available for this tweak."
            $isApplied = $false
        }
        
        if ($isApplied) { # Set the color based on the status
            $node.ForeColor = [System.Drawing.Color]::Green
            $node.ToolTipText = "Applied: $tweakName`n" + ($statusText -join "`n")
        }
        else {
            $node.ForeColor = [System.Drawing.Color]::Black
            $node.ToolTipText = "Not applied: $tweakName`n" + ($statusText -join "`n")
        }
        
        #$node.Checked = $isApplied # Set the checkmark based on the status
    }
}

function GeneralTreeView {
    param([Parameter(Mandatory = $true)][System.Windows.Forms.TreeView]$treeViewToPopulate)
    $treeViewToPopulate.Nodes.Clear()
    # Use a generic list for allTweakNodes to avoid issues with array resizing performance
    $global:allTweakNodes = @()
    $categories = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[PSObject]]]::new()

    foreach ($tweak in $generalTweaks) {
        $categoryName = $tweak.Category
        if ([string]::IsNullOrEmpty($categoryName)) {
            $categoryName = "Uncategorized"
        }
        if (-not $categories.ContainsKey($categoryName)) {
            [void]$categories.Add($categoryName, [System.Collections.Generic.List[PSObject]]::new())
        }
        [void]$categories[$categoryName].Add($tweak)
    }

    foreach ($categoryEntry in $categories.GetEnumerator() | Sort-Object Name) {
        $categoryName = $categoryEntry.Key
        $tweaksInThisCategory = $categoryEntry.Value
        $parentNode = New-Object System.Windows.Forms.TreeNode $categoryName
        $parentNode.ForeColor = [System.Drawing.Color]::RoyalBlue
        $parentNode.NodeFont = New-Object System.Drawing.Font($treeViewToPopulate.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold)
        [void]$treeViewToPopulate.Nodes.Add($parentNode)
        #$parentNode.Expand()
        
        foreach ($tweak in $tweaksInThisCategory | Sort-Object Name) {
            $childNode = New-Object System.Windows.Forms.TreeNode ($tweak.Name)
            $childNode.Tag = $tweak # Store the full tweak object in the node's Tag property
            $childNode.ToolTipText = $tweak.Description
            [void]$parentNode.Nodes.Add($childNode)
            $global:allTweakNodes += $childNode
        }
    }
    # Convert to array at the end if you prefer, but List is often better for dynamic additions
    # $global:allTweakNodes = $global:allTweakNodes.ToArray() 
}

$generalTweaks = @(
    @{
        Category     = "Privacy & Security"
        Name         = "Disable ConsumerFeatures"
        Description  = "Windows 10 will not automatically install any games, third-party apps, or application links from the Windows Store for the signed-in user. Some default Apps will be inaccessible (eg. Phone Link)"
        RegistryPath = "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        ValueName    = "DisableWindowsConsumerFeatures"
        TweakValue   = 1
        DefaultValue = "<RemoveEntry>"
        ValueType    = "DWord"
    },
    @{
        Category         = "Privacy & Security"
        Name             = "Disable Activity History"
        Description      = "This erases recent docs, clipboard, and run history."
        RegistrySettings = @(
            @{
                Path          = "HKLM\SOFTWARE\Policies\Microsoft\Windows\System"
                Name          = "EnableActivityFeed"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Policies\Microsoft\Windows\System"
                Name          = "PublishUserActivities"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Policies\Microsoft\Windows\System"
                Name          = "UploadUserActivities"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            }
        )
    },
    @{
        Category         = "Privacy & Security"
        Name             = "Disable Location Tracking"
        Description      = "Disables Location Tracking."
        RegistrySettings = @(
            @{
                Path          = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
                Name          = "Value"
                Value         = "Deny"
                OriginalValue = "Allow"
                Type          = "String"
            },
            @{
                Path          = "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}"
                Name          = "SensorPermissionState"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration"
                Name          = "Status"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SYSTEM\Maps"
                Name          = "AutoUpdateEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Gaming"
        Name         = "Prefer IPv4 over IPv6"
        Description  = "To set the IPv4 preference can have latency and security benefits on private networks where IPv6 is not configured."
        RegistryPath = "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
        ValueName    = "DisabledComponents"
        TweakValue   = "32"
        DefaultValue = "0"
        ValueType    = "DWord"
    },
    @{
        Category     = "Performance"
        Name         = "Win 32 Priority Separation"
        Description  = "Adjusts how Windows allocates CPU time to foreground and background applications. Setting to '26' (hex) gives more priority to foreground applications."
        RegistryPath = "HKLM\SYSTEM\CurrentControlSet\Control\PriorityControl"
        ValueName    = "Win32PrioritySeparation"
        TweakValue   = 0x26
        DefaultValue = 0x2
        ValueType    = "DWord"
    },
    @{
        Category     = "System & Storage"
        Name         = "Enable Long Paths"
        Description  = "Enables support for file paths longer than 260 characters"
        RegistryPath = "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem"
        ValueName    = "LongPathsEnabled"
        TweakValue   = 1
        DefaultValue = 0
        ValueType    = "DWord"
    },
    @{
        Category     = "Customize Preferences"
        Name         = "Prevent Windows Update Reboots"
        Description  = "Sets active hours to prevent automatic reboots during Windows Updates"
        RegistrySettings = @(
            @{
                Path          = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                Name          = "SetActiveHours"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                Name          = "ActiveHoursStart"
                Value         = 8
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
                Name          = "ActiveHoursEnd"
                Value         = 17
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Privacy & Security"
        Name         = "Disable App Suggestions"
        Description  = "Disables app suggestions and Content Delivery Manager silent installs"
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        ValueName    = "SilentInstalledAppsEnabled"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Category     = "Performance"
        Name         = "Disable Startup Delay"
        Description  = "Removes the delay when running startup apps in Windows 11"
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize"
        ValueName    = "Startupdelayinmsec"
        TweakValue   = 0
        DefaultValue = "<RemoveEntry>"
        ValueType    = "DWord"
    },
    @{
        Category     = "File Explorer & UI"
        Name         = "Restore Classic File Explorer"
        Description  = "Restores the classic File Explorer with ribbon in Windows 11"
        RegistrySettings = @(
            @{
                Path          = "HKCU\Software\Classes\CLSID\{2aa9162e-c906-4dd9-ad0b-3d24a8eef5a0}"
                Name          = "(Default)"
                Value         = "CLSID_ItemsViewAdapter"
                OriginalValue = "<RemoveEntry>"
                Type          = "String"
            },
            @{
                Path          = "HKCU\Software\Classes\CLSID\{2aa9162e-c906-4dd9-ad0b-3d24a8eef5a0}\InProcServer32"
                Name          = "(Default)"
                Value         = "C:\\Windows\\System32\\Windows.UI.FileExplorer.dll_"
                OriginalValue = "<RemoveEntry>"
                Type          = "String"
            },
            @{
                Path          = "HKCU\Software\Classes\CLSID\{2aa9162e-c906-4dd9-ad0b-3d24a8eef5a0}\InProcServer32"
                Name          = "ThreadingModel"
                Value         = "Apartment"
                OriginalValue = "<RemoveEntry>"
                Type          = "String"
            },
            @{
                Path          = "HKCU\Software\Classes\CLSID\{6480100b-5a83-4d1e-9f69-8ae5a88e9a33}"
                Name          = "(Default)"
                Value         = "File Explorer Xaml Island View Adapter"
                OriginalValue = "<RemoveEntry>"
                Type          = "String"
            },
            @{
                Path          = "HKCU\Software\Classes\CLSID\{6480100b-5a83-4d1e-9f69-8ae5a88e9a33}\InProcServer32"
                Name          = "(Default)"
                Value         = "C:\\Windows\\System32\\Windows.UI.FileExplorer.dll_"
                OriginalValue = "<RemoveEntry>"
                Type          = "String"
            },
            @{
                Path          = "HKCU\Software\Classes\CLSID\{6480100b-5a83-4d1e-9f69-8ae5a88e9a33}\InProcServer32"
                Name          = "ThreadingModel"
                Value         = "Apartment"
                OriginalValue = "<RemoveEntry>"
                Type          = "String"
            },
            @{
                Path          = "HKCU\Software\Microsoft\Internet Explorer\Toolbar\ShellBrowser"
                Name          = "ITBar7Layout"
                Value         = @(0x13,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x20,0x00,0x00,0x00,0x10,0x00,0x01,0x00,0x00,0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,0x07,0x00,0x00,0x5e,0x01,0x00,0x00)
                OriginalValue = "<RemoveEntry>"
                Type          = "Binary"
            }
        )
    },
    @{
        Category     = "Performance"
        Name         = "Disable Modern Standby"
        Description  = "Disables Modern Standby in Windows 10 and Windows 11"
        RegistryPath = "HKLM\SYSTEM\CurrentControlSet\Control\Power"
        ValueName    = "PlatformAoAcOverride"
        TweakValue   = 0
        DefaultValue = "<RemoveEntry>"
        ValueType    = "DWord"
    },
    @{
        Category     = "Customize Preferences"
        Name         = "Disable Mouse Pointer Trails"
        Description  = "Disables mouse pointer trails in Windows 11"
        RegistryPath = "HKCU\Control Panel\Mouse"
        ValueName    = "MouseTrails"
        TweakValue   = "0"
        DefaultValue = "2"
        ValueType    = "String"
    },
    @{
        Category     = "File Explorer & UI"
        Name         = "Disable AutoSuggest in Run Dialog"
        Description  = "Disables AutoSuggest in Run and File Explorer Address Bar"
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoComplete"
        ValueName    = "AutoSuggest"
        TweakValue   = "no"
        DefaultValue = "<RemoveEntry>"
        ValueType    = "String"
    },
    @{
        Category     = "File Explorer & UI"
        Name         = "Disable Sync Provider Notifications"
        Description  = "Disables sync provider notifications in File Explorer"
        RegistryPath = "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        ValueName    = "ShowSyncProviderNotifications"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Category     = "File Explorer & UI"
        Name         = "Show File Extensions"
        Description  = "Shows file name extensions for known file types"
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        ValueName    = "HideFileExt"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Category     = "File Explorer & UI"
        Name         = "Enable End Task in Taskbar"
        Description  = "Enables End Task option in taskbar right-click menu"
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"
        ValueName    = "TaskbarEndTask"
        TweakValue   = 1
        DefaultValue = 0
        ValueType    = "DWord"
    },
    @{
        Category     = "Privacy & Security"
        Name         = "Disable Windows Copilot"
        Description  = "Disables Windows Copilot in Windows 11"
        RegistrySettings = @(
            @{
                Path          = "HKCU\Software\Policies\Microsoft\Windows\WindowsCopilot"
                Name          = "TurnOffWindowsCopilot"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
                Name          = "TurnOffWindowsCopilot"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "File Explorer & UI"
        Name         = "Use Classic Alt+Tab"
        Description  = "Uses classic icons instead of thumbnails in Alt+Tab"
        RegistryPath = "HKCU\Software\Policies\Microsoft\Windows\Explorer"
        ValueName    = "AltTabSettings"
        TweakValue   = 1
        DefaultValue = "<RemoveEntry>"
        ValueType    = "DWord"
    },
    @{
        Category     = "System & Storage"
        Name         = "Disable Reserved Storage"
        Description  = "Disables Windows 11 reserved storage feature"
        RegistrySettings = @(
            @{
                Path          = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager"
                Name          = "MiscPolicyInfo"
                Value         = 2
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager"
                Name          = "PassedPolicy"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager"
                Name          = "ShippedWithReserves"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Performance"
        Name         = "Disable Last Access Time Stamp"
        Description  = "Disables NTFS last access time stamp updates for better performance"
        InvokeScript = @(
            "fsutil.exe behavior set disableLastAccess 1"
        )
        ResetScript  = @(
            "fsutil.exe behavior set disableLastAccess 0"
        )
    },
    @{
        Category     = "Performance"
        Name         = "Disable Search Indexing"
        Description  = "Disables Windows Search Indexing service for better performance"
        Service      = "wsearch"
        TweakValue   = "Disabled"
        DefaultValue = "Automatic"
    },
    @{
        Category     = "Customize Preferences"
        Name         = "Disable Enhance Pointer Precision"
        Description  = "Disables mouse acceleration (Enhance Pointer Precision)"
        RegistryPath = "HKCU\Control Panel\Mouse"
        ValueName    = "MouseSpeed"
        TweakValue   = "0"
        DefaultValue = "1"
        ValueType    = "String"
    },
    @{
        Category         = "Gaming"
        Name             = "Disable GameDVR"
        Description      = "GameDVR is a Windows App that is a dependency for some Store Games. I've never met someone that likes it, but it's there for the XBOX crowd."
        RegistrySettings = @(
             @{
                Path          = "HKCU\System\GameConfigStore"
                Name          = "GameDVR_FSEBehavior"
                Value         = 2
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU\System\GameConfigStore"
                Name          = "GameDVR_Enabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU\System\GameConfigStore"
                Name          = "GameDVR_HonorUserFSEBehaviorMode"
                Value         = 1
                OriginalValue = 0
                Type          = "DWord"
            },
            @{
                Path          = "HKCU\System\GameConfigStore"
                Name          = "GameDVR_EFSEFeatureFlags"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
                Name          = "AllowGameDVR"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Advanced - CAUTION"
        Name         = "Disable Background Apps"
        Description  = "Disables all Microsoft Store apps from running in the background, which has to be done individually since Win11"
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
        ValueName    = "GlobalUserDisabled"
        TweakValue   = 1
        DefaultValue = 0
        ValueType    = "DWord"
    },
    @{
        Category     = "Gaming"
        Name         = "Disable Fullscreen Optimizations"
        Description  = "Disables FSO in all applications. NOTE: This will disable Color Management in Exclusive Fullscreen"
        RegistryPath = "HKCU\System\GameConfigStore"
        ValueName    = "GameDVR_DXGIHonorFSEWindowsCompatible"
        TweakValue   = 1
        DefaultValue = 0
        ValueType    = "DWord"
    },
    @{
        Category     = "Customize Preferences"
        Name         = "Disable Bing Search in Start Menu"
        Description  = "If enable then includes web search results from Bing in your Start Menu search."
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Search"
        ValueName    = "BingSearchEnabled"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Category         = "Customize Preferences"
        Name             = "Enable NumLock on Startup"
        Description      = "Toggle the Num Lock key state when your computer starts."
        RegistrySettings = @(
             @{
                Path          = "HKU\.Default\Control Panel\Keyboard"
                Name          = "InitialKeyboardIndicators"
                Value         = 2
                OriginalValue = 0
                Type          = "DWord"
            },
            @{
                Path          = "HKCU\Control Panel\Keyboard"
                Name          = "InitialKeyboardIndicators"
                Value         = 2
                OriginalValue = 0
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Customize Preferences"
        Name         = "Verbose Messages During Logon"
        Description  = "Show detailed messages during the login process for troubleshooting and diagnostics."
        RegistryPath = "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        ValueName    = "VerboseStatus"
        TweakValue   = 1
        DefaultValue = 0
        ValueType    = "DWord"
    },
    @{
        Category         = "Customize Preferences"
        Name             = "Disable Recommendations in Start Menu"
        Description      = "If disabled then you will not see recommendations in the Start Menu. | Enables 'iseducationenvironment' | Relogin Required. | WARNING: This will also disable Windows Spotlight on your Lock Screen as a side effect."
        RegistrySettings = @(
             @{
                Path          = "HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
                Name          = "HideRecommendedSection"
                Value         = 1
                OriginalValue = 0
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Microsoft\PolicyManager\current\device\Education"
                Name          = "IsEducationEnvironment"
                Value         = 1
                OriginalValue = 0
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SOFTWARE\Policies\Microsoft\Windows\Explorer"
                Name          = "HideRecommendedSection"
                Value         = 1
                OriginalValue = 0
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Customize Preferences"
        Name         = "Remove Settings Home Page"
        Description  = "Removes the Home page in the Windows Settings app."
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        ValueName    = "SettingsPageVisibility"
        TweakValue   = "hide:home"
        DefaultValue = "show:home"
        ValueType    = "String"
    },
    @{
        Category     = "Customize Preferences"
        Name         = "Disable Sticky Keys"
        Description  = "If Enabled then Sticky Keys is activated - Sticky keys is an accessibility feature of some graphical user interfaces which assists users who have physical disabilities or help users reduce repetitive strain injury."
        RegistryPath = "HKCU\Control Panel\Accessibility\StickyKeys"
        ValueName    = "Flags"
        TweakValue   = 510
        DefaultValue = 58
        ValueType    = "DWord"
    },
    @{
        Category         = "Customize Preferences"
        Name             = "Detailed BSoD"
        Description      = "If Enabled then you will see a detailed Blue Screen of Death (BSOD) with more information."
        RegistrySettings = @(
             @{
                Path          = "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl"
                Name          = "DisplayParameters"
                Value         = 1
                OriginalValue = 0
                Type          = "DWord"
            },
            @{
                Path          = "HKLM\SYSTEM\CurrentControlSet\Control\CrashControl"
                Name          = "DisableEmoticon"
                Value         = 1
                OriginalValue = 0
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Customize Preferences"
        Name         = "Use small taskbar buttons"
        Description  = "Enables smaller taskbar buttons for a more compact taskbar"
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        ValueName    = "TaskbarSmallIcons"
        TweakValue   = 1
        DefaultValue = 0
        ValueType    = "DWord"
    },
    @{
        Category     = "File Explorer & UI"
        Name         = "Disable Snap Assist Flyout"
        Description  = "If enabled then Snap preview is disabled when maximize button is hovered."
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        ValueName    = "EnableSnapAssistFlyout"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Category     = "File Explorer & UI"
        Name         = "Disable Snap Assist Suggestion"
        Description  = "If enabled then you will get suggestions to snap other applications in the left over spaces."
        RegistryPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        ValueName    = "SnapAssist"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Category     = "Customize Preferences"
        Name         = "Disable Message 'Let Windows and apps access your location'"
        Description  = "If enabled then you will not see the message 'Let Windows and apps access your location'"
        RegistryPath = "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
        ValueName    = "ShowGlobalPrompts"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Category     = "Advanced - CAUTION"
        Name         = "Enable Network Acceleration (TCP Offload)"
        Description  = "Enables TCP Offloading and RSS for better network performance (may cause issues with some network cards)"
        RegistryPath = "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
        ValueName    = "DisableTaskOffload"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    }
)

# Main container panel for the Tweaks tab
$tweaksMainPanel = New-Object System.Windows.Forms.TableLayoutPanel
$tweaksMainPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$tweaksMainPanel.RowCount = 4
[void]$tweaksMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$tweaksMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30)))
[void]$tweaksMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 25)))
[void]$tweaksMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 60)))
$tweaksMainPanel.ColumnCount = 1
[void]$tweaksMainPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
$tweaksMainPanel.Padding = New-Object System.Windows.Forms.Padding(10)
[void]$tabTweaks.Controls.Add($tweaksMainPanel)

# TreeView for tweaks
$treeView = New-Object System.Windows.Forms.TreeView
$treeView.Dock = [System.Windows.Forms.DockStyle]::Fill
$treeView.HideSelection = $false
$treeView.CheckBoxes = $true
$treeView.ShowNodeToolTips = $true
[void]$tweaksMainPanel.Controls.Add($treeView, 0, 0)
$allTweakNodes = @()

# Status Label (Footer)
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$statusLabel.TextAlign = 'MiddleLeft'
$statusLabel.Text = "Status: Ready"
$statusLabel.BackColor = [System.Drawing.Color]::LightGray
[void]$tweaksMainPanel.Controls.Add($statusLabel, 0, 1)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Dock = [System.Windows.Forms.DockStyle]::Fill
$progressBar.Visible = $false
$tweaksMainPanel.Controls.Add($progressBar, 0, 2)

# Buttons Panel
$buttonPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$buttonPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$buttonPanel.WrapContents = $false
$buttonPanel.AutoSize = $true
$tweaksMainPanel.Controls.Add($buttonPanel, 0, 3)
# Apply Button
$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = "Apply"
$applyButton.Size = New-Object System.Drawing.Size(150, 30)
$applyButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$applyButton.BackColor = [System.Drawing.Color]::LimeGreen
$applyButton.Enabled = $false # Initially disabled
$applyButton.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$buttonPanel.Controls.Add($applyButton)

# Reset Button
$resetButton = New-Object System.Windows.Forms.Button
$resetButton.Text = "Reset selected"
$resetButton.Size = New-Object System.Drawing.Size(180, 30)
$resetButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$resetButton.BackColor = [System.Drawing.Color]::DarkOrange
$resetButton.Enabled = $false # Initially disabled
$resetButton.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$buttonPanel.Controls.Add($resetButton)

# Uncheck All Button for General Tab
$generalUncheckAllButton = New-Object System.Windows.Forms.Button
$generalUncheckAllButton.Text = "Uncheck all"
$generalUncheckAllButton.Size = New-Object System.Drawing.Size(100, 30)
$generalUncheckAllButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$generalUncheckAllButton.BackColor = [System.Drawing.Color]::SlateGray
$generalUncheckAllButton.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$buttonPanel.Controls.Add($generalUncheckAllButton)

# Recommended Button
$recommendedButton = New-Object System.Windows.Forms.Button
$recommendedButton.Text = "Recommended"
$recommendedButton.Size = New-Object System.Drawing.Size(120, 30)
$recommendedButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$recommendedButton.BackColor = [System.Drawing.Color]::LightBlue
$recommendedButton.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$buttonPanel.Controls.Add($recommendedButton)

# Function to set recommended tweaks
function Set-RecommendedTweaks {
    $global:IgnoreCheckEvent = $true
    
    # First, uncheck all tweaks
    foreach ($node in $global:allTweakNodes) {
        $node.Checked = $false
    }
    
    $recommendedTweakNames = @( # Define recommended tweaks by their names
        "Disable ConsumerFeatures",
        "Disable Activity History",
        "Disable Location Tracking",
        "Prefer IPv4 over IPv6",
        "Win 32 Priority Separation",
        "Disable App Suggestions",
        "Disable Mouse Pointer Trails",
        "Disable Sync Provider Notifications",
        "Show File Extensions",
        "Enable End Task in Taskbar",
        "Disable Windows Copilot",
        "Disable Last Access Time Stamp",
        "Disable Enhance Pointer Precision",
        "Disable GameDVR",
        "Disable Background Apps",
        "Disable Bing Search in Start Menu",
        "Disable Recommendations in Start Menu",
        "Remove Settings Home Page",
        "Disable Sticky Keys",
        "Enable Network Acceleration (TCP Offload)"
    )
    
    # Check the recommended tweaks
    foreach ($node in $global:allTweakNodes) {
        if ($node.Text -in $recommendedTweakNames) {
            $node.Checked = $true
        }
    }
    
    # Update the UI
    $applyButton.Enabled = $true
    $resetButton.Enabled = $true
    $global:IgnoreCheckEvent = $false
    $statusLabel.Text = "Status: Recommended tweaks selected. Click 'Apply' to apply them."
}

$recommendedButton.Add_Click({ # Add click handler for Recommended button
    Set-RecommendedTweaks
})

$treeView.Add_AfterCheck({ # Add AfterCheck event handler
    param($sender, $e)
        if ($global:IgnoreCheckEvent) { return }
        $global:IgnoreCheckEvent = $true

        if ($e.Node.Nodes.Count -gt 0) { # Category node: Check/Uncheck all children
            foreach ($child in $e.Node.Nodes) {
                $child.Checked = $e.Node.Checked
            }
        }
        else { # Tweak node: Update parent's checked state if all children are checked/unchecked
            $parent = $e.Node.Parent
            if ($parent -ne $null) {
                $checkedChildrenCount = ($parent.Nodes | Where-Object { $_.Checked }).Count
                # Check parent if all children are checked
                $parent.Checked = ($checkedChildrenCount -eq $parent.Nodes.Count)
            }
        }

        # Enable/Disable Apply/Reset buttons based on selections
        # Use the global:allTweakNodes as a flat list of all tweak nodes
        $checkedTweaksCount = ($global:allTweakNodes | Where-Object { $_.Checked }).Count
        $uncheckedTweaksCount = ($global:allTweakNodes | Where-Object { -not $_.Checked }).Count
        $applyButton.Enabled = $checkedTweaksCount -gt 0
        # The reset button should be enabled if there are any unchecked tweaks (implying they are currently active and can be reset)
        # Or if any of the checked tweaks are currently in a "non-default" state, even if checked for application.
        # For now, we'll stick to the existing logic which seems to imply reset applies to UNCHECKED tweaks.
        # If the user's intention is to reset *selected* tweaks to default, the logic in $resetButton.Add_Click would need to change.
        $resetButton.Enabled = $uncheckedTweaksCount -gt 0 
        $global:IgnoreCheckEvent = $false
})

$applyButton.Add_Click({ # Apply Button Click for General Tab
        $checkedTweaks = $global:allTweakNodes | Where-Object { $_.Checked }
        if ($checkedTweaks.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("Please select at least one tweak to apply.", "No Tweaks Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }
    
        $dialogResult = [System.Windows.Forms.MessageBox]::Show(
            "Are you sure you want to apply the selected tweaks? This might require a system restart.",
            "Confirm Apply Tweaks",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
    
        if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            $statusLabel.Text = "Status: Applying tweaks..."
            $progressBar.Style = 'Continuous'
            $progressBar.Minimum = 0
            $progressBar.Maximum = $checkedTweaks.Count # Progressbar basiert auf der Anzahl der ausgewählten Tweaks
            $progressBar.Value = 0
            $progressBar.Visible = $true
            $form.Refresh()
            $global:hasChanges = $false
            $global:restartNeeded = $false
            ApplyTweaks -treeViewToApply $treeView # $treeView ist dein TreeView-Objekt für die Tweaks
            $progressBar.Visible = $false
            $statusLabel.Text = "Status: Tweak application complete."
            Update-GeneralTweaksStatus -tweakNodes $global:allTweakNodes # Re-check status after applying
            $form.Refresh()
    
            if ($global:restartNeeded) {
                $restartDialogResult = [System.Windows.Forms.MessageBox]::Show(
                    "Some changes require a system restart to take effect. Do you want to restart now?",
                    "Restart Required",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
                if ($restartDialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Restart-Computer -Force
                }
            }
        }
    })

$resetButton.Add_Click({ # Reset Button Click for General Tab
        $toResetTweaks = $global:allTweakNodes | Where-Object { -not $_.Checked }
    
        if ($toResetTweaks.Count -eq 0) {
            [System.Windows.Forms.MessageBox]::Show("No tweaks selected to reset. Select the tweaks you want to keep active, and then click 'Reset' to revert the unchecked ones to their default state.", "No Tweaks Selected", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
            return
        }
    
        $dialogResult = [System.Windows.Forms.MessageBox]::Show(
            "Are you sure you want to reset the unchecked tweaks to their default Windows values? This might require a system restart.",
            "Confirm Reset Tweaks",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )
    
        if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
            $statusLabel.Text = "Status: Resetting tweaks to default..."
            $progressBar.Style = 'Continuous'
            $progressBar.Minimum = 0
            $progressBar.Maximum = $toResetTweaks.Count # Progressbar basiert auf der Anzahl der zu resetierenden Tweaks
            $progressBar.Value = 0
            $progressBar.Visible = $true
            $form.Refresh()
            $global:hasChanges = $false
            $global:restartNeeded = $false
    
            ResetTweaks -treeViewToReset $treeView # $treeView ist dein TreeView-Objekt für die Tweaks
    
            $progressBar.Visible = $false
            $statusLabel.Text = "Status: Tweak reset complete."
            Update-GeneralTweaksStatus -tweakNodes $global:allTweakNodes # Re-check status after resetting
            $form.Refresh()
    
            if ($global:restartNeeded) {
                $restartDialogResult = [System.Windows.Forms.MessageBox]::Show(
                    "Some changes require a system restart to take effect. Do you want to restart now?",
                    "Restart Required",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBox.Icon]::Question
                )
                if ($restartDialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Restart-Computer -Force
                }
            }
        }
    })

$generalUncheckAllButton.Add_Click({ # Uncheck All Button Click for General Tab
        $global:IgnoreCheckEvent = $true

        foreach ($parentNode in $treeView.Nodes) {
            foreach ($childNode in $parentNode.Nodes) { 
                $childNode.Checked = $false 
            }
            $parentNode.Checked = $false
        }

        $applyButton.Enabled = $false
        $resetButton.Enabled = $false
        $statusLabel.Text = "All selections cleared."
        $global:IgnoreCheckEvent = $false
    })
#endregion

#region 6. Tab: Misc
$tabMisc = New-Object System.Windows.Forms.TabPage "Misc"
$tabControl.TabPages.Add($tabMisc)
# Example Label in Misc Tab
$miscLabel = New-Object System.Windows.Forms.Label
$miscLabel.Text = "Soon"
$miscLabel.AutoSize = $true
$miscLabel.Location = New-Object System.Drawing.Point(15, 15)
$tabMisc.Controls.Add($miscLabel)
#endregion

#region 7. Tab: Downloads
function Ensure-LatestWinget {
    param(
        [string]$MinVersion = "1.7.0"
    )
    # 1. Existenz prüfen
    $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $wingetCmd) {
        [System.Windows.Forms.MessageBox]::Show(
            "winget was not found. Attempting to install the App Installer (winget) from the Microsoft Store.",
            "winget not found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information
        )
        try {
            Start-Process -FilePath "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
            [System.Windows.Forms.MessageBox]::Show(
                "Please install the 'App Installer' from the Microsoft Store window that opens. Then click OK when the installation is complete.",
                "Installing winget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information
            )
            Start-Sleep -Seconds 5
            $wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
            if (-not $wingetCmd) {
                [System.Windows.Forms.MessageBox]::Show(
                    "winget could not be found after installation. Please restart the script or make sure winget is installed correctly.",
                    "Error in winget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error
                )
                exit
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show(
                "An error occurred while attempting to open the Microsoft Store for winget installation: $_. Please install winget manually.",
                "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error
            )
            exit
        }
    }

    # 2. Version prüfen
    $wingetVersion = & winget --version 2>$null
    if ($wingetVersion -and ($wingetVersion -match '([0-9]+\.[0-9]+\.[0-9]+)')) {
        $current = [version]$Matches[1]
        $required = [version]$MinVersion
        if ($current -lt $required) {
            $msg = "Your winget version is $current. The minimum required version is $required.`n`nWould you like to update winget now?"
            $result = [System.Windows.Forms.MessageBox]::Show($msg, "winget update recommended", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Information)
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                # Versuche Update via Store
                try {
                    Start-Process -FilePath "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1"
                    [System.Windows.Forms.MessageBox]::Show(
                        "Please update the 'App Installer' in the Microsoft Store. Click OK when done.",
                        "Update winget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information
                    )
                } catch {
                    [System.Windows.Forms.MessageBox]::Show(
                        "Could not open Microsoft Store. Please update winget manually from https://github.com/microsoft/winget-cli/releases",
                        "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error
                    )
                }
                Start-Sleep -Seconds 5
            }
        }
    }
}

$global:installedPackageIds = @{}
<#
.SYNOPSIS
    Updates the global list of installed winget packages.
.DESCRIPTION
    Queries winget for all installed packages and updates the global $installedPackageIds hashtable.
    Provides UI feedback through progress bar and status label.
.PARAMETER parentForm
    The parent Windows Form for UI updates (required for cross-thread operations)
.PARAMETER progressBar
    ProgressBar control to show operation progress
.PARAMETER statusLabel
    Label control to show status messages
.OUTPUTS
    Boolean indicating success ($true) or failure ($false) of the operation
#>
# Hilfsfunktion für sicheres UI-Update
function SafeInvoke {
    param(
        [Parameter(Mandatory=$true)]
        [object]$Form,
        [Parameter(Mandatory=$true)]
        [scriptblock]$Action
    )
    if ($null -ne $Form -and $Form.PSObject.Properties['Invoke']) {
        try { $Form.Invoke($Action) } catch { & $Action }
    } else {
        & $Action
    }
}

function Update-InstalledPackageIds {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [System.Windows.Forms.Form]$parentForm,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [System.Windows.Forms.ProgressBar]$progressBar,
        
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [System.Windows.Forms.Label]$statusLabel
    )
    
    Ensure-LatestWinget # Stelle sicher, dass winget installiert und aktuell ist
    
    # Sicherstellen, dass die UI-Elemente existieren
    if ($null -eq $parentForm -or $parentForm.IsDisposed) {
        Write-Error "Parent form is not available or has been disposed."
        return $false
    }
    
    if ($null -eq $progressBar -or $progressBar.IsDisposed) {
        Write-Error "Progress bar is not available or has been disposed."
        return $false
    }
    
    if ($null -eq $statusLabel -or $statusLabel.IsDisposed) {
        Write-Error "Status label is not available or has been disposed."
        return $false
    }
    $progressBar.Style = 'Marquee'
    $progressBar.Visible = $true
    $statusLabel.Text = "Loading installed Winget packages (may take some time)..."
    $parentForm.Refresh()
    $global:installedPackageIds.Clear()
    try {
        $wingetResult = Invoke-WingetCommand -arguments "list --source winget" -timeoutSeconds 60
        if ($wingetResult.TimedOut) {
            [System.Windows.Forms.MessageBox]::Show($wingetResult.Errors, "Winget timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            $statusLabel.Text = "Status: Loading failed (timeout)."
            return
        }
        elseif ($wingetResult.ExitCode -ne 0) {
            $errorDetails = if ([string]::IsNullOrWhiteSpace($wingetResult.Errors)) {
                "No error details available. Exit code: $($wingetResult.ExitCode)"
            } else {
                $wingetResult.Errors.Trim()
            }
            throw "Failed to check installed packages. $errorDetails"
        }
        elseif ([string]::IsNullOrWhiteSpace($wingetResult.Output)) {
            throw "No package information was returned. Winget may not be properly configured."
        }
        
        # Parse the winget output
        $installedPackagesRaw = $wingetResult.Output -split "`n"
        $packageCount = 0
        $processedCount = 0
        $totalLines = $installedPackagesRaw.Count
        
        # Update progress to determinate mode
        SafeInvoke -Form $parentForm -Action {
            $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
            $progressBar.Maximum = $totalLines
            $progressBar.Value = 0
        }
        
        foreach ($line in $installedPackagesRaw) {
            $processedCount++
            
            # Update progress every 10 packages for better performance
            if (($processedCount % 10) -eq 0) {
                SafeInvoke -Form $parentForm -Action {
                    $progressBar.Value = [Math]::Min($processedCount, $progressBar.Maximum)
                    $statusLabel.Text = "Processing packages: $processedCount of $totalLines"
                }
            }
            
            # Skip header, separator and empty lines
            if ($line -match '^\s*Name\s+Id\s+Version' -or 
                $line -match '^\s*---\s+---\s+---' -or 
                [string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            # Extract package ID (second column)
            $cols = ($line.Trim() -split '\s{2,}', 3)  # Split into max 3 columns
            if ($cols.Length -ge 2) {
                $packageId = $cols[1].Trim()
                if (-not [string]::IsNullOrWhiteSpace($packageId)) {
                    $global:installedPackageIds[$packageId] = $true
                    $packageCount++
                }
            }
        }
        
        # Final UI update
        SafeInvoke -Form $parentForm -Action {
            $statusLabel.Text = "Found $packageCount installed packages."
            $progressBar.Value = $progressBar.Maximum
        }
        
        Write-Verbose "Successfully updated installed packages list. Found $packageCount packages."
        return $true
    }
    catch [System.Exception] {
        $errorMsg = "ERROR: $($_.Exception.Message)"
        Write-Error $errorMsg -ErrorAction Continue
        
        SafeInvoke -Form $parentForm -Action {
            $statusLabel.Text = $errorMsg
            $statusLabel.ForeColor = [System.Drawing.Color]::Red
            $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
            $progressBar.Value = 0
        }
        
        return $false
    }
    finally {
        # Hide progress bar after a delay using a timer
        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 3000  # 3 seconds

        $timer.Add_Tick({
            try {
                if ($null -ne $parentForm -and $parentForm.PSObject.Properties['Invoke']) {
                    $parentForm.Invoke([System.Windows.Forms.MethodInvoker]{
                        $progressBar.Visible = $false
                        $statusLabel.Visible = $false
                        $statusLabel.ForeColor = [System.Drawing.SystemColors]::ControlText
                    })
                } else {
                    $progressBar.Visible = $false
                    $statusLabel.Visible = $false
                    $statusLabel.ForeColor = [System.Drawing.SystemColors]::ControlText
                }
            } catch {}
            try { $timer.Stop(); $timer.Dispose() } catch {}
        })

        $timer.Start()
    }
}

function Test-WingetPackageInstalled {
    # Function to test if a Winget package is installed
    param([string]$packageId)
    return $global:installedPackageIds.ContainsKey($packageId)
}

function Update-InstalledProgramsStatus {
    # Function to update the visual status of programs in the TreeView
    $statusDownloadLabel.Text = "Updating program status..."
    $downloadProgressBar.Style = 'Marquee'
    $downloadProgressBar.Visible = $true
    $form.Refresh()
    try {
        # Update the list of installed packages
        Update-InstalledPackageIds -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
        # Update the visual state of each node
        foreach ($node in $allProgramNodes) {
            $pkgId = $node.Tag
            if (Test-WingetPackageInstalled -packageId $pkgId) {
                $node.ForeColor = [System.Drawing.Color]::Green
            }
            else {
                $node.ForeColor = [System.Drawing.Color]::Black
            }
        }
        $statusDownloadLabel.Text = "Program status updated."
    }
    catch {
        $statusDownloadLabel.Text = "Error updating program status: $_"
        [System.Windows.Forms.MessageBox]::Show("An error occurred while updating program status: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
    finally {
        $downloadProgressBar.Visible = $false
        $form.Refresh()
    }
}

function Get-SelectedInstallStatus {
    # Function to get selected installation status
    $selected = $allProgramNodes | Where-Object { $_.Checked }
    $installed = @()
    $notInstalled = @()

    foreach ($node in $selected) {
        if (Test-WingetPackageInstalled -packageId $node.Tag) { 
            $installed += $node
        }
        else { 
            $notInstalled += $node 
        }
    }
    return [PSCustomObject]@{
        Installed    = $installed
        NotInstalled = $notInstalled
        AllSelected  = $selected
    }
}

function Install-WingetProgram {
    # Function to install/update programs via winget
    param([string]$packageId)
    $statusDownloadLabel.Text = "Status: Install/Update $($packageId)..."
    $downloadProgressBar.Visible = $true
    $downloadProgressBar.Style = 'Marquee'
    $form.Refresh()
    $timeoutSeconds = 180
    $wingetResult = Invoke-WingetCommand -arguments "install --id $($packageId) --source winget --accept-package-agreements --accept-source-agreements" -timeoutSeconds $timeoutSeconds
    $downloadProgressBar.Visible = $false

    if ($wingetResult.TimedOut) {
        [System.Windows.Forms.MessageBox]::Show("The installation of $($packageId) has exceeded the time limit.", "Winget Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
    elseif ($wingetResult.ExitCode -ne 0) {
        $errorMessage = "Error installing/updating $($packageId). Exit Code: $($wingetResult.ExitCode). "
        if (![string]::IsNullOrEmpty($wingetResult.Errors)) { $errorMessage += "Fehler: $($wingetResult.Errors)." }
        $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
        [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget installation/update error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
    else {
        $statusDownloadLabel.Text = "$($packageId) installed/updated."
        return $true
    }
}

function Install-OrUpdate {
    # Function to install or update selected nodes
    param([System.Windows.Forms.TreeNode[]]$nodes)
    $downloadProgressBar.Style = 'Continuous'
    $downloadProgressBar.Minimum = 0
    $downloadProgressBar.Maximum = $nodes.Count
    $downloadProgressBar.Value = 0
    $downloadProgressBar.Visible = $true

    foreach ($node in $nodes) {
        $pkgId = $node.Tag
        $statusDownloadLabel.Text = "Installing/Updating $($node.Text)..."
        $form.Refresh()
        $result = Install-WingetProgram -packageId $pkgId
        if (-not $result) {
            [System.Windows.Forms.MessageBox]::Show("Installation/Update of $($node.Text) failed. Aborting.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            break
        }
        $downloadProgressBar.Value++
    }
    $downloadProgressBar.Visible = $false
    $statusDownloadLabel.Text = "Install/Update process completed."
    Update-InstalledProgramsStatus
}

function Uninstall-Programs {
    # Function to uninstall programs
    param([System.Windows.Forms.TreeNode[]]$nodes)

    $downloadProgressBar.Style = 'Continuous'
    $downloadProgressBar.Minimum = 0
    $downloadProgressBar.Maximum = $nodes.Count
    $downloadProgressBar.Value = 0
    $downloadProgressBar.Visible = $true
    $timeoutSeconds = 180

    foreach ($node in $nodes) {
        $pkgId = $node.Tag
        $statusDownloadLabel.Text = "Status: Uninstall $($node.Text) (ID: $($pkgId))..."
        $form.Refresh()
        $wingetResult = Invoke-WingetCommand -arguments "uninstall --id $($pkgId) --accept-source-agreements" -timeoutSeconds $timeoutSeconds
        
        if ($wingetResult.TimedOut) {
            [System.Windows.Forms.MessageBox]::Show("Uninstalling $($node.Text) has exceeded the time limit.", "Winget Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            break
        }
        elseif ($wingetResult.ExitCode -ne 0) {
            $errorMessage = "Error uninstalling $($node.Text). Exit Code: $($wingetResult.ExitCode). "
            if (![string]::IsNullOrEmpty($wingetResult.Errors)) { $errorMessage += "Error: $($wingetResult.Errors)." }
            $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
            [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget uninstallation error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            break
        }
        else {
            $statusDownloadLabel.Text = "$($node.Text) uninstalled."
        }
        $downloadProgressBar.Value++
    }
    $downloadProgressBar.Visible = $false
    $statusDownloadLabel.Text = "Uninstallation process completed."
    Update-InstalledProgramsStatus
}

$tabDownloads = New-Object System.Windows.Forms.TabPage "Downloads"
[void]$tabControl.TabPages.Add($tabDownloads)

$programCategories = @{ # Downloads
    "Benchmarks"            = @(
        @{Name = "AIDA64 Extreme"; Id = "FinalWire.AIDA64.Extreme" },
        @{Name = "CrystalDiskInfo"; Id = "CrystalDewWorld.CrystalDiskInfo" },
        @{Name = "Geeks3D FurMark 2"; Id = "Geeks3D.FurMark.2" },
        @{Name = "OCCT"; Id = "OCBase.OCCT.Personal" }
    )
    "Browsers"              = @(
        @{Name = "Brave"; Id = "Brave.Brave" },
        @{Name = "Chromium"; Id = "Hibbiki.Chromium" },
        @{Name = "Google Chrome"; Id = "Google.Chrome" },
        @{Name = "LibreWolf"; Id = "LibreWolf.LibreWolf" },
        @{Name = "Mozilla Firefox"; Id = "Mozilla.Firefox" },
        @{Name = "Mozilla Firefox ESR"; Id = "Mozilla.Firefox.ESR" },
        @{Name = "Vivaldi"; Id = "Vivaldi.Vivaldi" },
        @{Name = "Opera"; Id = "Opera.Opera" },
        @{Name = "Opera GX"; Id = "Opera.OperaGX" }
    )
    "Communication"         = @(
        @{Name = "Discord"; Id = "Discord.Discord" },
        @{Name = "Proton Mail"; Id = "Proton.ProtonMail" },
        @{Name = "TeamSpeak 3 Client"; Id = "TeamSpeakSystems.TeamSpeakClient" }
    )
    "Development"           = @(
        @{Name = "Docker Desktop"; Id = "Docker.DockerDesktop" },
        @{Name = "Fiddler"; Id = "Progress.Fiddler" },
        @{Name = "Git"; Id = "Git.Git" },
        @{Name = "JetBrains Toolbox"; Id = "JetBrains.Toolbox" },
        @{Name = "MongoDB Compass"; Id = "MongoDB.Compass.Full" },
        @{Name = "Node.js"; Id = "OpenJS.NodeJS" },
        @{Name = "Node.js (LTS)"; Id = "OpenJS.NodeJS.LTS" },
        @{Name = "Postman"; Id = "Postman.Postman" },
        @{Name = "Python 3"; Id = "Python.Python.3" },
        @{Name = "SmartFTP Client"; Id = "SmartSoft.SmartFTP" },
        @{Name = "Tabby"; Id = "Eugeny.Tabby" },
        @{Name = "WinSCP"; Id = "WinSCP.WinSCP" }
    )
    "Editors"               = @(
        @{Name = "Cursor"; Id = "Anysphere.Cursor" },
        @{Name = "Kate"; Id = "KDE.Kate" },
        @{Name = "Notepad++"; Id = "Notepad++.Notepad++" },
        @{Name = "Vim"; Id = "vim.vim" },
        @{Name = "Visual Studio Code"; Id = "Microsoft.VisualStudioCode" },
        @{Name = "Visual Studio Community 2022"; Id = "Microsoft.VisualStudio.2022.Community" },
        @{Name = "VSCodium"; Id = "VSCodium.VSCodium" }
    )
    "File Management"       = @(
        @{Name = "7-Zip"; Id = "7zip.7zip" },
        @{Name = "NanaZip"; Id = "M2Team.NanaZip" },
        @{Name = "Proton Drive"; Id = "Proton.ProtonDrive" },
        @{Name = "TeraCopy"; Id = "CodeSector.TeraCopy" },
        @{Name = "WinRAR"; Id = "RARLab.WinRAR" }
    )
    "Gaming"                = @(
        @{Name = "Crosshair V2"; Id = "9N1K9Q56HVXR" },
        @{Name = "EA app"; Id = "ElectronicArts.EADesktop" },
        @{Name = "Epic Games Launcher"; Id = "EpicGames.EpicGamesLauncher" },
        @{Name = "Steam"; Id = "Valve.Steam" },
        @{Name = "Ubisoft Connect"; Id = "Ubisoft.Connect" },
        @{Name = "Xbox"; Id = "9MV0B5HZVK9Z" },
        @{Name = "Game Bar"; Id = "9NZKPSTSNW4P" },
        @{Name = "FACEIT"; Id = "FACEITLTD.FACEITClient" }
    )
    "Media"                 = @(
        @{Name = "Audacity"; Id = "Audacity.Audacity" },
        @{Name = "K-Lite Codec Pack Standard"; Id = "CodecGuide.K-LiteCodecPack.Standard" },
        @{Name = "Kodi"; Id = "XBMCFoundation.Kodi" },
        @{Name = "MPV"; Id = "shinchiro.mpv" },
        @{Name = "VLC media player"; Id = "VideoLAN.VLC" }
    )
    "Misc"                  = @(
        @{Name = "grepWin"; Id = "StefansTools.grepWin" },
        @{Name = "NTLite"; Id = "Nlitesoft.NTLite" }
    )
    "Package Manager Tools" = @(
        @{Name = "Chocolatey"; Id = "Chocolatey.Choco" },
        @{Name = "Scoop"; Id = "ScoopInstaller.Scoop" }
    )
    "Streaming"             = @(
        @{Name = "Chatterino"; Id = "ChatterinoTeam.Chatterino" },
        @{Name = "Chatty"; Id = "Chatty.Chatty" },
        @{Name = "Elgato Stream Deck"; Id = "Elgato.StreamDeck" },
        @{Name = "OBS Studio"; Id = "OBSProject.OBSStudio" },
        @{Name = "StreamlabsOBS"; Id = "Streamlabs.StreamlabsOBS" },
        @{Name = "streamer.bot"; Id = "streamerbot.streamerbot" },
        @{Name = "Twitch Studio"; Id = "Twitch.TwitchStudio" }
    )
    "System Tools"          = @(
        @{Name = "CPU-Z"; Id = "CPUID.CPU-Z" },
        @{Name = "CrystalDiskMark"; Id = "CrystalDewWorld.CrystalDiskMark" },
        @{Name = "FanControl"; Id = "Rem0o.FanControl" },
        @{Name = "HWInfo"; Id = "REALiX.HWiNFO" },
        @{Name = "PowerToys"; Id = "Microsoft.PowerToys" },
        @{Name = "Process Lasso"; Id = "BitSum.ProcessLasso" },
        @{Name = "Revo Uninstaller"; Id = "RevoUninstaller.RevoUninstaller" },
        @{Name = "Rufus"; Id = "Rufus.Rufus" },
        @{Name = "Snappy Driver Installer Origin"; Id = "GlennDelahoy.SnappyDriverInstallerOrigin" },
        @{Name = "Wintoys"; Id = "9P8LTPGCBZXD" },
        @{Name = "ParkControl"; Id = "BitSum.ParkControl" },
        @{Name = "Display Driver Uninstaller"; Id = "Wagnardsoft.DisplayDriverUninstaller" }
    )
    "Utilities"             = @(
        @{Name = "EarTrumpet"; Id = "File-New-Project.EarTrumpet" },
        @{Name = "GIMP"; Id = "GIMP.GIMP.3" },
        @{Name = "Greenshot"; Id = "Greenshot.Greenshot" },
        @{Name = "Gyazo"; Id = "Nota.Gyazo" },
        @{Name = "IrfanView"; Id = "IrfanSkiljan.IrfanView" },
        @{Name = "Krita"; Id = "KDE.Krita" },
        @{Name = "Lightshot"; Id = "Skillbrains.Lightshot" },
        @{Name = "Proton Pass"; Id = "Proton.ProtonPass" },
        @{Name = "ShareX"; Id = "ShareX.ShareX" },
        @{Name = "Spotify"; Id = "Spotify.Spotify" },
        @{Name = "TranslucentTB"; Id = "CharlesMilette.TranslucentTB" },
        @{Name = "KeePassXC"; Id = "KeePassXCTeam.KeePassXC" },
        @{Name = "1Password"; Id = "AgileBits.1Password" },
        @{Name = "Bitwarden"; Id = "Bitwarden.Bitwarden" }
    )
    "Virtualization"        = @(
        @{Name = "QEMU"; Id = "qemu.qemu" },
        @{Name = "VirtualBox"; Id = "Oracle.VirtualBox" },
        @{Name = "VMware Workstation Player"; Id = "VMware.WorkstationPlayer" }
    )
}

# Main container for Downloads tab
$downloadsMainPanel = New-Object System.Windows.Forms.TableLayoutPanel
$downloadsMainPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$downloadsMainPanel.RowCount = 4
$downloadsMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30))) | Out-Null  # Label
$downloadsMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null  # TreeView
$downloadsMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 30))) | Out-Null  # Status
$downloadsMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 50))) | Out-Null  # Buttons
$downloadsMainPanel.ColumnCount = 1
$downloadsMainPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))) | Out-Null
$downloadsMainPanel.Padding = New-Object System.Windows.Forms.Padding(10)
$tabDownloads.Controls.Add($downloadsMainPanel) | Out-Null

# Label top
$downloadsLabel = New-Object System.Windows.Forms.Label
$downloadsLabel.Text = "Select the programs to install via winget:"
$downloadsLabel.AutoSize = $true
$downloadsLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$downloadsMainPanel.Controls.Add($downloadsLabel, 0, 0)

# TreeView with Checkboxes and Categories
$downloadTreeView = New-Object System.Windows.Forms.TreeView
$downloadTreeView.Dock = [System.Windows.Forms.DockStyle]::Fill
$downloadTreeView.HideSelection = $false
$downloadTreeView.CheckBoxes = $true
$downloadsMainPanel.Controls.Add($downloadTreeView, 0, 1)
$allProgramNodes = @() # List to hold all program nodes for status checks

foreach ($category in $programCategories.Keys) {
    # Populate TreeView with categories and programs
    $parentNode = New-Object System.Windows.Forms.TreeNode $category
    foreach ($prog in $programCategories[$category]) {
        $childNode = New-Object System.Windows.Forms.TreeNode $prog.Name
        $childNode.Tag = $prog.Id
        # Highlight installed programs
        if (Test-WingetPackageInstalled -packageId $prog.Id) {
            #$childNode.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
            #$childNode.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font, [System.Drawing.FontStyle]::Bold)
            $childNode.ForeColor = [System.Drawing.Color]::Green
        }
        [void]$parentNode.Nodes.Add($childNode)
        $allProgramNodes += $childNode
    }
    [void]$downloadTreeView.Nodes.Add($parentNode)
}

# Buttons Panel
$downloadButtonsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$downloadButtonsPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$downloadButtonsPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$downloadButtonsPanel.WrapContents = $false
$downloadButtonsPanel.AutoSize = $true
[void]$downloadsMainPanel.Controls.Add($downloadButtonsPanel, 0, 3)

# Install Button
$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "Install"
$installButton.Size = New-Object System.Drawing.Size(120, 30)
$installButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$installButton.BackColor = [System.Drawing.Color]::LimeGreen
$installButton.Enabled = $false
[void]$downloadButtonsPanel.Controls.Add($installButton)

# Update Button
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = "Update all"
$updateButton.Size = New-Object System.Drawing.Size(120, 30)
$updateButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$updateButton.BackColor = [System.Drawing.Color]::LightGreen
$updateButton.Enabled = $true
[void]$downloadButtonsPanel.Controls.Add($updateButton)

# Uninstall Button
$uninstallButton = New-Object System.Windows.Forms.Button
$uninstallButton.Text = "Uninstall"
$uninstallButton.Size = New-Object System.Drawing.Size(120, 30)
$uninstallButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$uninstallButton.BackColor = [System.Drawing.Color]::LightCoral
$uninstallButton.Enabled = $false
[void]$downloadButtonsPanel.Controls.Add($uninstallButton)

# Get Installed Button
$getInstalledButton = New-Object System.Windows.Forms.Button
$getInstalledButton.Text = "Get Installed"
$getInstalledButton.Size = New-Object System.Drawing.Size(120, 30)
$getInstalledButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$getInstalledButton.BackColor = [System.Drawing.Color]::DodgerBlue
$getInstalledButton.ForeColor = [System.Drawing.Color]::White
[void]$downloadButtonsPanel.Controls.Add($getInstalledButton)

# Uncheck All Button
$uncheckAllButton = New-Object System.Windows.Forms.Button
$uncheckAllButton.Text = "Uncheck all"
$uncheckAllButton.Size = New-Object System.Drawing.Size(120, 30)
$uncheckAllButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$uncheckAllButton.BackColor = [System.Drawing.Color]::LightGray
[void]$downloadButtonsPanel.Controls.Add($uncheckAllButton)

# Status Label
$statusDownloadLabel = New-Object System.Windows.Forms.Label
$statusDownloadLabel.Dock = [System.Windows.Forms.DockStyle]::Fill
$statusDownloadLabel.TextAlign = 'MiddleLeft'
$statusDownloadLabel.BackColor = [System.Drawing.Color]::LightGray
$downloadsMainPanel.Controls.Add($statusDownloadLabel, 0, 2)

# Progress Bar
$downloadProgressBar = New-Object System.Windows.Forms.ProgressBar
$downloadProgressBar.Dock = [System.Windows.Forms.DockStyle]::Fill
$downloadProgressBar.Visible = $false
# Add progress bar to a new row in the table layout
$downloadsMainPanel.RowCount = 5
$downloadsMainPanel.RowStyles.Insert(3, (New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Absolute, 25)))
$downloadsMainPanel.SetRow($downloadButtonsPanel, 4)
$downloadsMainPanel.Controls.Add($downloadProgressBar, 0, 3)
# ProgressBar wird bereits im vorherigen Schritt hinzugefügt

$downloadTreeView.Add_AfterCheck({ # TreeView AfterCheck event
        param($sender, $e)

        if ($global:IgnoreCheckEventDownloads) { return }
        $global:IgnoreCheckEventDownloads = $true

        if ($e.Node.Nodes.Count -gt 0) {
            # Category node
            foreach ($child in $e.Node.Nodes) {
                $child.Checked = $e.Node.Checked
            }
        }
        else {
            # Program node
            $parent = $e.Node.Parent
            if ($parent -ne $null) {
                $uncheckedCount = ($parent.Nodes | Where-Object { -not $_.Checked } | Measure-Object).Count
                $parent.Checked = ($uncheckedCount -eq 0)
            }
        }

        $status = Get-SelectedInstallStatus
        $countInstalled = $status.Installed.Count
        $countNotInstalled = $status.NotInstalled.Count
        $countTotal = $status.AllSelected.Count
        $installButton.Visible = $true
        $updateButton.Visible = $true
        $uninstallButton.Visible = $true

        if ($countTotal -eq 0) {
            $installButton.Enabled = $false
            $updateButton.Enabled = $true
            $uninstallButton.Enabled = $false
            $installButton.Text = "Install"
        }
        elseif ($countInstalled -eq $countTotal -and $countTotal -gt 0) {
            $installButton.Enabled = $false
            $updateButton.Enabled = $true
            $uninstallButton.Enabled = $true
        }
        elseif ($countNotInstalled -eq $countTotal) {
            $installButton.Enabled = $true
            $updateButton.Enabled = $true
            $uninstallButton.Enabled = $false
            $installButton.Text = "Install"
        }
        else {
            $installButton.Enabled = $true
            $installButton.Text = "Install/Update"
            $installButton.AutoSize = $true
            $updateButton.Enabled = $true
            $uninstallButton.Enabled = $false
        }

        $global:IgnoreCheckEventDownloads = $false
    })

$uninstallButton.Add_Click({ # Uninstall Button Click
        $status = Get-SelectedInstallStatus
        $toUninstall = $status.Installed
        if ($toUninstall.Count -eq 0) {
            $statusDownloadLabel.Text = "No installed program selected for uninstall."
            return
        }
        Uninstall-Programs -nodes $toUninstall
    })

$installButton.Add_Click({ # Install Button Click
        $status = Get-SelectedInstallStatus
        $toInstallOrUpdate = $status.AllSelected
        if ($toInstallOrUpdate.Count -eq 0) {
            $statusDownloadLabel.Text = "No program selected."
            return
        }
        Install-OrUpdate -nodes $toInstallOrUpdate
    })

$updateButton.Add_Click({ # Update Button Click
        try {
            # Get all checked nodes (programs) from the TreeView
            $selectedNodes = @()
            foreach ($parentNode in $downloadTreeView.Nodes) {
                foreach ($childNode in $parentNode.Nodes) {
                    if ($childNode.Checked) {
                        $selectedNodes += $childNode
                    }
                }
            }

            if ($selectedNodes.Count -eq 0) {
                # No specific programs selected, so "Update all"
                [System.Windows.Forms.MessageBox]::Show("No individual programs selected. Starting update for all available Winget packages.", "Update All", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        
                $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                    "Do you want to install all available Winget package updates? This may take some time.",
                    "Install all updates?",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )

                if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $statusDownloadLabel.Text = "Status: Updating all Winget packages..."
                    $downloadProgressBar.Style = 'Marquee'
                    $downloadProgressBar.Visible = $true
                    $form.Refresh()
                    $wingetResult = Invoke-WingetCommand -arguments "upgrade --all --accept-package-agreements --accept-source-agreements" -timeoutSeconds 300
            
                    if ($wingetResult.TimedOut) {
                        [System.Windows.Forms.MessageBox]::Show("The update of all Winget packages has timed out.", "Winget Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                    elseif ($wingetResult.ExitCode -ne 0) {
                        $errorMessage = "Error updating all packages. Exit Code: $($wingetResult.ExitCode). "
                        if (![string]::IsNullOrEmpty($wingetResult.Errors)) { $errorMessage += "Error: $($wingetResult.Errors)." }
                        $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
                        [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget upgrade error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    }
                    else {
                        [System.Windows.Forms.MessageBox]::Show("All Winget packages have been updated (if updates were available).", "Updates Completed", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    }
                }
            }
            else {
                # Individual programs selected for update
                $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                    "Do you want to update the selected programs?",
                    "Update programs?",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )

                if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    Install-OrUpdate -nodes $selectedNodes
                }
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("An error has occurred: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
        finally {
            Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
        }
    })

$getInstalledButton.Add_Click({ # Get Installed Button Click
        $statusDownloadLabel.Text = "Loading installed programs..."
        $downloadProgressBar.Visible = $true
        $downloadProgressBar.Style = 'Marquee'
        $getInstalledButton.Enabled = $false
        $form.Refresh()
        
        try {
            Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
            $statusDownloadLabel.Text = "Installed programs loaded successfully."
        }
        catch {
            $statusDownloadLabel.Text = "Error loading installed programs: $_"
            [System.Windows.Forms.MessageBox]::Show("An error occurred while loading installed programs: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
        finally {
            $getInstalledButton.Enabled = $true
            $downloadProgressBar.Visible = $false
            $form.Refresh()
        }
    })

$uncheckAllButton.Add_Click({ # Uncheck All Button Click
        $global:IgnoreCheckEventDownloads = $true
    
        foreach ($parentNode in $downloadTreeView.Nodes) {
            foreach ($childNode in $parentNode.Nodes) { 
                $childNode.Checked = $false 
            }
            $parentNode.Checked = $false
        }
    
        $installButton.Enabled = $false
        $updateButton.Enabled = $true
        $uninstallButton.Enabled = $false
        $statusDownloadLabel.Text = "All selections cleared."
        $global:IgnoreCheckEventDownloads = $false
    })
#endregion

#region 8. Tab: Debloat
$tabDebloat = New-Object System.Windows.Forms.TabPage "Debloat"
# Main container for Debloat tab
$debloatMainPanel = New-Object System.Windows.Forms.TableLayoutPanel
$debloatMainPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$debloatMainPanel.RowCount = 4
[void]$debloatMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$debloatMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
[void]$debloatMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
[void]$debloatMainPanel.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize)))
$debloatMainPanel.ColumnCount = 1
[void]$debloatMainPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
# Description label
$debloatDescriptionLabel = New-Object System.Windows.Forms.Label
$debloatDescriptionLabel.Text = "Select the Windows apps you want to remove and click 'Remove Selected'."
$debloatDescriptionLabel.Dock = [System.Windows.Forms.DockStyle]::Top
$debloatDescriptionLabel.Padding = New-Object System.Windows.Forms.Padding(0, 0, 0, 10)
# TreeView for debloat options
$debloatTreeView = New-Object System.Windows.Forms.TreeView
$debloatTreeView.Dock = [System.Windows.Forms.DockStyle]::Fill
$debloatTreeView.CheckBoxes = $true
$debloatTreeView.ShowNodeToolTips = $true
$debloatTreeView.ShowRootLines = $false
$debloatTreeView.ShowPlusMinus = $false
$debloatTreeView.HideSelection = $false
$debloatTreeView.FullRowSelect = $false
$debloatTreeView.Indent = 15
$debloatTreeView.ItemHeight = 20
$debloatTreeView.PathSeparator = "\"
$debloatTreeView.Sorted = $false
# Status label
$debloatStatusLabel = New-Object System.Windows.Forms.Label
$debloatStatusLabel.Text = "Ready. Select apps to remove and click 'Remove Selected'."
$debloatStatusLabel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$debloatStatusLabel.Height = 20
$debloatStatusLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
# Buttons panel
$debloatButtonsPanel = New-Object System.Windows.Forms.FlowLayoutPanel
$debloatButtonsPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$debloatButtonsPanel.Height = 40
$debloatButtonsPanel.FlowDirection = [System.Windows.Forms.FlowDirection]::LeftToRight
$debloatButtonsPanel.Padding = New-Object System.Windows.Forms.Padding(5)
# Remove Selected button
$removeSelectedButton = New-Object System.Windows.Forms.Button
$removeSelectedButton.Text = "Remove Selected"
$removeSelectedButton.Width = 150
$removeSelectedButton.Height = 30
$removeSelectedButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
# Check All button
$debloatCheckAllButton = New-Object System.Windows.Forms.Button
$debloatCheckAllButton.Text = "Select All"
$debloatCheckAllButton.Width = 120
$debloatCheckAllButton.Height = 30
$debloatCheckAllButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$debloatCheckAllButton.BackColor = [System.Drawing.Color]::LightGray
# Uncheck All button
$debloatUncheckAllButton = New-Object System.Windows.Forms.Button
$debloatUncheckAllButton.Text = "Deselect All"
$debloatUncheckAllButton.Width = 120
$debloatUncheckAllButton.Height = 30
$debloatUncheckAllButton.BackColor = [System.Drawing.Color]::LightGray

# Add buttons to panel
[void]$debloatButtonsPanel.Controls.Add($removeSelectedButton)
[void]$debloatButtonsPanel.Controls.Add($debloatCheckAllButton)
[void]$debloatButtonsPanel.Controls.Add($debloatUncheckAllButton)
# Add controls to main panel
[void]$debloatMainPanel.Controls.Add($debloatDescriptionLabel, 0, 0)
[void]$debloatMainPanel.Controls.Add($debloatTreeView, 0, 1)
[void]$debloatMainPanel.Controls.Add($debloatStatusLabel, 0, 2)
[void]$debloatMainPanel.Controls.Add($debloatButtonsPanel, 0, 3)

# Add main panel to tab
$tabDebloat.Controls.Add($debloatMainPanel)

# List of safely removable Windows 11 apps
# Only includes apps that can be safely removed without breaking Windows functionality
$bloatwareApps = @(
    # Entertainment & Social Media
    @{ Name = "3D Viewer"; PackageName = "Microsoft.Microsoft3DViewer" },
    @{ Name = "Bing Weather"; PackageName = "Microsoft.BingWeather" },
    @{ Name = "Bing Finance"; PackageName = "Microsoft.BingFinance" },
    @{ Name = "Bing News"; PackageName = "Microsoft.BingNews" },
    @{ Name = "Bing Sports"; PackageName = "Microsoft.BingSports" },
    @{ Name = "Candy Crush Saga"; PackageName = "king.com.CandyCrushSaga" },
    @{ Name = "Candy Crush Soda"; PackageName = "king.com.CandyCrushSodaSaga" },
    @{ Name = "Disney+"; PackageName = "Disney.37853FC22B2CE" },
    @{ Name = "Facebook"; PackageName = "Facebook.Facebook" },
    @{ Name = "Spotify"; PackageName = "SpotifyAB.SpotifyMusic" },
    # Microsoft Apps (safely removable)
    @{ Name = "Feedback Hub"; PackageName = "Microsoft.WindowsFeedbackHub" },
    @{ Name = "Get Help"; PackageName = "Microsoft.GetHelp" },
    @{ Name = "People"; PackageName = "Microsoft.People" },
    @{ Name = "Mail and Calendar"; PackageName = "microsoft.windowscommunicationsapps" },
    @{ Name = "Maps"; PackageName = "Microsoft.WindowsMaps" },
    @{ Name = "Microsoft Solitaire Collection"; PackageName = "Microsoft.MicrosoftSolitaireCollection" },
    @{ Name = "Microsoft To Do"; PackageName = "Microsoft.Todos" },
    @{ Name = "Mixed Reality Portal"; PackageName = "Microsoft.MixedReality.Portal" },
    @{ Name = "MSN Weather"; PackageName = "Microsoft.BingWeather" },
    @{ Name = "MSN Sports"; PackageName = "Microsoft.BingSports" },
    @{ Name = "MSN News"; PackageName = "Microsoft.BingNews" },
    @{ Name = "Office Hub"; PackageName = "Microsoft.MicrosoftOfficeHub" },
    @{ Name = "OneNote"; PackageName = "Microsoft.Office.OneNote" },
    @{ Name = "Paint 3D"; PackageName = "Microsoft.MSPaint" },
    @{ Name = "Power Automate"; PackageName = "Microsoft.Flow" },
    @{ Name = "PowerShell (Preview)"; PackageName = "Microsoft.PowerShell.Preview" },
    @{ Name = "Voice Recorder"; PackageName = "Microsoft.WindowsSoundRecorder" },
    @{ Name = "Sway"; PackageName = "Microsoft.Office.Sway" },
    @{ Name = "Tips"; PackageName = "Microsoft.Getstarted" },
    @{ Name = "Windows Camera"; PackageName = "Microsoft.WindowsCamera" },
    @{ Name = "Xbox"; PackageName = "Microsoft.XboxApp" },
    @{ Name = "Your Phone"; PackageName = "Microsoft.YourPhone" },
    @{ Name = "Groove Music"; PackageName = "Microsoft.ZuneMusic" },
    @{ Name = "Movies & TV"; PackageName = "Microsoft.ZuneVideo" }
    # Note: Microsoft Store has been removed from the list as it's required for system updates and app installations
    # @{ Name = "Microsoft Store"; PackageName = "Microsoft.WindowsStore" },
)

# Populate the TreeView with bloatware apps
foreach ($app in $bloatwareApps) {
    $node = New-Object System.Windows.Forms.TreeNode
    $node.Text = $app.Name
    $node.ToolTipText = "Package: $($app.PackageName)"
    $node.Tag = $app.PackageName
    [void]$debloatTreeView.Nodes.Add($node)
}

# Check All button click event
$debloatCheckAllButton.Add_Click({
    $global:IgnoreCheckEvent = $true
    foreach ($node in $debloatTreeView.Nodes) {
        $node.Checked = $true
    }
    $global:IgnoreCheckEvent = $false
})

# Uncheck All button click event
$debloatUncheckAllButton.Add_Click({
    $global:IgnoreCheckEvent = $true
    foreach ($node in $debloatTreeView.Nodes) {
        $node.Checked = $false
    }
    $global:IgnoreCheckEvent = $false
})

# Function to remove selected apps
function Remove-SelectedApps {
    $selectedNodes = @($debloatTreeView.Nodes | Where-Object { $_.Checked })
    
    if ($selectedNodes.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Please select at least one app to remove.", "No Apps Selected", 
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        return
    }
    
    $result = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to remove the selected apps? This action cannot be undone.", 
        "Confirmation", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Question)
    
    if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
        $progressForm = New-Object System.Windows.Forms.Form
        $progressForm.Text = "Removing Apps..."
        $progressForm.Size = New-Object System.Drawing.Size(400, 150)
        $progressForm.StartPosition = "CenterParent"
        $progressForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
        $progressForm.MaximizeBox = $false
        $progressForm.MinimizeBox = $false
        $progressForm.ControlBox = $false
        
        $progressLabel = New-Object System.Windows.Forms.Label
        $progressLabel.Text = "Preparing to remove selected apps..."
        $progressLabel.Location = New-Object System.Drawing.Point(10, 20)
        $progressLabel.Width = 380
        
        $progressBar = New-Object System.Windows.Forms.ProgressBar
        $progressBar.Location = New-Object System.Drawing.Point(10, 50)
        $progressBar.Width = 370
        $progressBar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
        
        $progressForm.Controls.Add($progressLabel)
        $progressForm.Controls.Add($progressBar)
        $progressForm.Show()
        $progressForm.Refresh()
        
        $progressBar.Maximum = $selectedNodes.Count
        $progressBar.Value = 0
        
        $removedCount = 0
        $failedApps = @()
        
        foreach ($node in $selectedNodes) {
            $progressLabel.Text = "Removing: $($node.Text)"
            $progressForm.Refresh()
            
            try {
                $packageName = $node.Tag
                Get-AppxPackage -Name $packageName -AllUsers | Remove-AppxPackage -ErrorAction Stop
                Get-AppxProvisionedPackage -Online | Where-Object { $_.PackageName -like "$packageName*" } | 
                    ForEach-Object { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction SilentlyContinue }
                $removedCount++
            }
            catch {
                $failedApps += "$($node.Text) ($($_.Exception.Message))"
            }
            
            $progressBar.Value++
            [System.Windows.Forms.Application]::DoEvents()
        }
        
        $progressForm.Close()
        
        $message = "Successfully removed $removedCount of $($selectedNodes.Count) apps."
        if ($failedApps.Count -gt 0) {
            $message += "`n`nFailed to remove the following apps:`n" + ($failedApps -join "`n")
        }
        
        [System.Windows.Forms.MessageBox]::Show($message, "Removal Complete", 
            [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        
        # Update status label
        $debloatStatusLabel.Text = "Removal complete. $removedCount of $($selectedNodes.Count) apps were removed."
    }
}

# Add click handler for remove button
$removeSelectedButton.Add_Click({
    Remove-SelectedApps
})

# Add the tab to the tab control
[void]$tabControl.TabPages.Add($tabDebloat)
#endregion

#region 9. Tab: Untested
$tabUntested = New-Object System.Windows.Forms.TabPage "Untested"
$tabControl.TabPages.Add($tabUntested) | Out-Null
# Example Label in Untested Tab
$untestedLabel = New-Object System.Windows.Forms.Label
$untestedLabel.Text = "These tweaks are untested and experimental."
$untestedLabel.AutoSize = $true
$untestedLabel.Location = New-Object System.Drawing.Point(15, 15)
$tabUntested.Controls.Add($untestedLabel) | Out-Null
#endregion

#region 10. Tab: About
$tabAbout = New-Object System.Windows.Forms.TabPage "About"
$tabControl.TabPages.Add($tabAbout) | Out-Null

# Main container for the About tab with better spacing
$aboutContainer = New-Object System.Windows.Forms.TableLayoutPanel
$aboutContainer.Dock = [System.Windows.Forms.DockStyle]::Fill
$aboutContainer.Padding = New-Object System.Windows.Forms.Padding(10)
$aboutContainer.ColumnCount = 1
$aboutContainer.RowCount = 2
$aboutContainer.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 70))) | Out-Null
$aboutContainer.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 30))) | Out-Null
[void]$tabAbout.Controls.Add($aboutContainer)

# Create a panel for the about text with better styling
$textPanel = New-Object System.Windows.Forms.Panel
$textPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$textPanel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$textPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$textPanel.Height = 250  # Fixed height for the text panel
[void]$aboutContainer.Controls.Add($textPanel, 0, 0)

# Create a rich text box for better text formatting
$aboutText = New-Object System.Windows.Forms.RichTextBox
$aboutText.Dock = [System.Windows.Forms.DockStyle]::Fill
$aboutText.ReadOnly = $true
$aboutText.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$aboutText.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$aboutText.Margin = New-Object System.Windows.Forms.Padding(15, 10, 15, 10)
$aboutText.Cursor = [System.Windows.Forms.Cursors]::Default
$aboutText.TabStop = $false
#$aboutText.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Regular)
$aboutText.Text = @"
Hello, my name is Leeshhi. I'm a hobby programmer who does this in my free time and for fun.

Additionally, I'm also a bit of a PC geek, as many would call it.

This tool was created to offer fellow gamers, like myself, genuine Windows optimizations that actually deliver results and aren't just generic nonsense that doesn't even exist.

I started this project because there are so many poor tools available on the internet.

Only tweaks and adjustments that I personally use and/or have tested will appear here.
"@
$textPanel.Controls.Add($aboutText) | Out-Null

# Create a more compact button panel with better organization
$buttonPanel = New-Object System.Windows.Forms.TableLayoutPanel
$buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$buttonPanel.ColumnCount = 2
$buttonPanel.RowCount = 2
$buttonPanel.AutoSize = $true
$buttonPanel.Padding = New-Object System.Windows.Forms.Padding(0, 15, 0, 5)
$buttonPanel.CellBorderStyle = [System.Windows.Forms.TableLayoutPanelCellBorderStyle]::None
$buttonPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
$buttonPanel.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))) | Out-Null
$aboutContainer.Controls.Add($buttonPanel, 0, 1) | Out-Null

# Function to create styled buttons
function New-StyledButton {
    param([string]$text, [string]$url, [System.Drawing.Color]$color)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $text
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button.BackColor = $color
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatAppearance.BorderSize = 0
    $button.Height = 35
    $button.Margin = New-Object System.Windows.Forms.Padding(5)
    $button.Dock = [System.Windows.Forms.DockStyle]::Fill
    $button.Cursor = [System.Windows.Forms.Cursors]::Hand
    $button.Add_Click({ Start-Process $url })
    # Store the original color in the button's Tag property
    $button.Tag = $color
    $button.Add_MouseEnter({ # Add hover effect
            $this.BackColor = [System.Drawing.Color]::FromArgb( 
                [Math]::Min(($this.BackColor.R + 40), 255), 
                [Math]::Min(($this.BackColor.G + 40), 255), 
                [Math]::Min(($this.BackColor.B + 40), 255)) 
        })
    $button.Add_MouseLeave({ 
            $this.BackColor = $this.Tag
        })
    return $button
}

# Add buttons in a 2x2 grid
$discordButton = New-StyledButton -text "Discord" -url "https://discord.gg/gDmjYgydb3" -color ([System.Drawing.Color]::DodgerBlue)
$buttonPanel.Controls.Add($discordButton, 0, 0)

$botButton = New-StyledButton -text "Shag.gg" -url "https://shag.gg" -color ([System.Drawing.Color]::FromArgb(76, 175, 80))
$buttonPanel.Controls.Add($botButton, 1, 0)

$botDcButton = New-StyledButton -text "Discord Bot" -url "https://discord.gg/qxPNcgtTqn" -color ([System.Drawing.Color]::FromArgb(76, 175, 80))
$buttonPanel.Controls.Add($botDcButton, 0, 1)

$githubButton = New-StyledButton -text "GitHub" -url "https://github.com/leeshhi" -color ([System.Drawing.Color]::DodgerBlue)
$buttonPanel.Controls.Add($githubButton, 1, 1)

# Add a small footer with version info
$footerLabel = New-Object System.Windows.Forms.Label
$footerLabel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$footerLabel.Height = 20
$footerLabel.TextAlign = [System.Drawing.ContentAlignment]::MiddleRight
$footerLabel.ForeColor = [System.Drawing.Color]::Gray
$footerLabel.Font = New-Object System.Drawing.Font("Segoe UI", 7)
$footerLabel.Text = "ShagUtil v$scriptVersion | $(Get-Date -Format 'yyyy')"
$tabAbout.Controls.Add($footerLabel)
#endregion

#region 11. Final Execution
$form.Add_Shown({ # Initial calls for Home tab info and General tab setup
        Initialize-HomeTabContent -systemInfoPanel $systemInfoPanel -form $form -systemInfoTitle $systemInfoTitle
        GeneralTreeView -treeViewToPopulate $treeView # This line should call your GeneralTreeView
        Update-GeneralTweaksStatus -tweakNodes $global:allTweakNodes # Ensure this uses $global:allTweakNodes
        if (-not $script:downloadsTabInitialized) {
            $statusDownloadLabel.Text = "Ready. Click 'Get Installed' to load installed programs."
            $script:downloadsTabInitialized = $true
        }
    })

[void]$form.ShowDialog() # Show form

Write-Host "`nGoodbye!`nThank you for using ShagUtil. <3" -ForegroundColor DarkCyan
#endregion