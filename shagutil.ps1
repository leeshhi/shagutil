#Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security # Needed ?
$scriptVersion = "0.3.0"

#region 1. Initial Script Setup & Admin Check
if (-not ([Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
    [System.Windows.Forms.MessageBox]::Show("This script must be run as an Administrator. Please restart PowerShell or the script file with administrative privileges.", "Administrator Privileges Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Stop)
    exit
}

Clear-Host
Write-Host ""
Write-Host "█████   █   █    ███  █████     █████ █████" -ForegroundColor Green
Write-Host "█       █   █   █   █ █         █     █" -ForegroundColor Green
Write-Host "█████   █████   █████ █ ███     █ ███ █ ███" -ForegroundColor Green
Write-Host "    █   █   █   █   █ █   █     █   █ █   █" -ForegroundColor Green
Write-Host "█████   █   █   █   █ █████ █   █████ █████" -ForegroundColor Green
Write-Host ""
Write-Host "==== Welcome to ShagUtil v$scriptVersion! ====" -ForegroundColor Cyan
Write-Host "==== Windows Toolbox ====" -ForegroundColor Cyan
Write-Host ""
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

function Invoke-WingetCommand {
    # Function: Invoke Winget Commands and Log Output
    param([string]$arguments, [int]$timeoutSeconds = 60)
    $tempDir = [System.IO.Path]::GetTempPath()
    $outputFile = [System.IO.Path]::Combine($tempDir, "winget_output_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
    $errorFile = [System.IO.Path]::Combine($tempDir, "winget_error_$(Get-Date -Format 'yyyyMMdd_HHmmss').log")
    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = "winget"
    $processInfo.Arguments = $arguments
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo

    try {
        $process.Start() | Out-Null
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()

        if ($process.WaitForExit($timeoutSeconds * 1000)) {
            $output = $outputTask.Result
            $errors = $errorTask.Result
            $output | Out-File -FilePath $outputFile -Encoding UTF8
            $errors | Out-File -FilePath $errorFile -Encoding UTF8

            [PSCustomObject]@{
                ExitCode   = $process.ExitCode
                Output     = $output
                Errors     = $errors
                OutputFile = $outputFile
                ErrorFile  = $errorFile
                TimedOut   = $false
            }
        }
        else {
            $process.Kill()
            [PSCustomObject]@{
                ExitCode   = $null
                Output     = ""
                Errors     = "Winget command timed out ($($timeoutSeconds)s)."
                OutputFile = $outputFile
                ErrorFile  = $errorFile
                TimedOut   = $true
            }
        }
    }
    catch {
        [PSCustomObject]@{
            ExitCode   = $null
            Output     = ""
            Errors     = "Unexpected error when running winget: $_"
            OutputFile = $outputFile
            ErrorFile  = $errorFile
            TimedOut   = $false
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
        $psPath = $Path -replace '^HKLM\\', 'HKLM:\' -replace '^HKCU\\', 'HKCU\' -replace '^HKU\\', 'HKU:\' -replace '^HKCR\\', 'HKCR:\' -replace '^HKCC\\', 'HKCC:\'
        
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
        # Split the path into parent and key name
        $keyPath = Split-Path -Path $psPath -Parent
        $keyName = Split-Path -Path $psPath -Leaf
        
        # Create parent key if it doesn't exist
        if (-not (Test-Path -Path $keyPath)) {
            try {
                $null = New-Item -Path $keyPath -Force -ErrorAction Stop
                Write-Host "  [INFO] Created registry path: $keyPath" -ForegroundColor Green
            }
            catch {
                Write-Host "  [ERROR] Failed to create registry path '$keyPath': $_" -ForegroundColor Red
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
        
        # Convert Hashtable to PSCustomObject if necessary
        if ($tweak -is [System.Collections.Hashtable] -or $tweak -is [System.Collections.Specialized.OrderedDictionary]) {
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
        
        # Debug output
        Write-Host "Processing tweak: $tweakName" -ForegroundColor Cyan
        
        # 1. Prüfe auf InvokeScript (hat Vorrang)
        if ($tweak.PSObject.Properties['InvokeScript'] -and $tweak.InvokeScript) {
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
        
        # 2. Prüfe auf RegistrySettings (Array von Einstellungen)
        if ($tweak.PSObject.Properties['RegistrySettings'] -and $tweak.RegistrySettings) {
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
        
        # 3. Prüfe auf einfache Registry-Einstellungen
        if ($tweak.PSObject.Properties['RegistryPath'] -and $tweak.RegistryPath -and 
            $tweak.PSObject.Properties['ValueName'] -and $tweak.ValueName -ne $null) {
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
        
        # 4. If nothing else worked
        if (-not $actionTaken) {
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
    param([System.Collections.Generic.List[System.Windows.Forms.TreeNode]]$tweakNodes)
    
    foreach ($node in $tweakNodes) {
        $tweak = $node.Tag
        if (-not $tweak) { continue }
        
        # Convert Hashtable to PSCustomObject if necessary
        if ($tweak -is [System.Collections.Hashtable] -or $tweak -is [System.Collections.Specialized.OrderedDictionary]) {
            $tweak = [PSCustomObject]$tweak
            $node.Tag = $tweak  # Update the tag with the converted object
        }
        
        $tweakName = if ($tweak.PSObject.Properties['Name'] -and $tweak.Name) { 
            $tweak.Name 
        }
        else { 
            "Unnamed Tweak" 
        }
        
        # Initialize status variables
        $isApplied = $false
        $statusText = @()
        $hasAnyCheck = $false
        
        # 1. Check for simple registry settings
        if ($tweak.RegistryPath -and $tweak.ValueName -ne $null) {
            $hasAnyCheck = $true
            $currentValue = Get-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName
            $expectedValue = if ($tweak.PSObject.Properties['TweakValue']) { $tweak.TweakValue } else { $null }
            
            if ($expectedValue -eq "<RemoveEntry>") {
                $isApplied = ($currentValue -eq $null)
                $statusText += "Entferne $($tweak.ValueName) aus $($tweak.RegistryPath): $(if ($isApplied) {'OK'} else {'Nicht angewendet'})"
            }
            else {
                $isApplied = ($currentValue -ne $null -and $currentValue -eq $expectedValue)
                $statusText += "Setze $($tweak.ValueName) auf '$expectedValue' in $($tweak.RegistryPath): $(if ($isApplied) {'OK'} else {'Nicht angewendet'})"
                if (-not $isApplied -and $currentValue -ne $null) {
                    $statusText += "Aktueller Wert: $currentValue"
                }
            }
        }
        
        # 2. Check for RegistrySettings array
        elseif ($tweak.PSObject.Properties['RegistrySettings'] -and $tweak.RegistrySettings) {
            $allSettingsApplied = $true
            $hasSettings = $false
            
            foreach ($setting in $tweak.RegistrySettings) {
                $hasSettings = $true
                $hasAnyCheck = $true
                
                $currentValue = Get-RegistryValue -Path $setting.Path -Name $setting.Name
                
                if ($setting.Value -eq "<RemoveEntry>") {
                    $settingApplied = ($currentValue -eq $null)
                    $statusText += "Entferne $($setting.Name) aus $($setting.Path): $(if ($settingApplied) {'OK'} else {'Nicht angewendet'})"
                }
                else {
                    $settingApplied = ($currentValue -ne $null -and $currentValue -eq $setting.Value)
                    $statusText += "Setze $($setting.Name) auf '$($setting.Value)' in $($setting.Path): $(if ($settingApplied) {'OK'} else {'Nicht angewendet'})"
                    if (-not $settingApplied -and $currentValue -ne $null) {
                        $statusText += "Aktueller Wert: $currentValue"
                    }
                }
                
                if (-not $settingApplied) {
                    $allSettingsApplied = $false
                }
            }
            
            $isApplied = $hasSettings -and $allSettingsApplied
        }
        
        # 3. Check for InvokeScript (cannot be reliably verified)
        if ($tweak.PSObject.Properties['InvokeScript'] -and $tweak.InvokeScript) {
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
        
        # 4. Special handling for Service tweaks
        if ($tweak.Action -eq "Service" -and $tweak.Service) {
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
        
        # If no verification was possible, indicate that the status is unknown
        if (-not $hasAnyCheck) {
            $statusText += "No verification method available for this tweak."
            $isApplied = $false
        }
        
        # Set the color based on the status
        if ($isApplied) {
            $node.ForeColor = [System.Drawing.Color]::Green
            $node.ToolTipText = "Applied: $tweakName`n" + ($statusText -join "`n")
        }
        else {
            $node.ForeColor = [System.Drawing.Color]::Black
            $node.ToolTipText = "Not applied: $tweakName`n" + ($statusText -join "`n")
        }
        
        # Set the checkmark based on the status
        $node.Checked = $isApplied
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
        $parentNode.Expand()
        
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
        Category     = "Privacy"
        Name         = "Disable ConsumerFeatures"
        Description  = "Windows 10 will not automatically install any games, third-party apps, or application links from the Windows Store for the signed-in user. Some default Apps will be inaccessible (eg. Phone Link)"
        RegistryPath = "HKLM\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        ValueName    = "DisableWindowsConsumerFeatures"
        TweakValue   = 1
        DefaultValue = "<RemoveEntry>"
        ValueType    = "DWord"
    },
    @{
        Category         = "Privacy"
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
        Category         = "Privacy"
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
    }
} catch {
    Write-Warning "Error checking Windows version or updating Task Manager: $_"
    if ($taskmgr -and -not $taskmgr.HasExited) {
        Stop-Process $taskmgr -Force -ErrorAction SilentlyContinue
    }
}

# Remove 3D Objects from This PC
try {
    $path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}"
    if (Test-Path $path) {
        Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
    }
} catch {
    Write-Warning "Failed to remove 3D Objects from This PC: $_"
}

# Remove Edge policies if they exist
if (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge") {
    try {
        Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Recurse -Force -ErrorAction Stop
    } catch {
        Write-Warning "Failed to remove Edge policies: $_"
    }
}

# Optimize SvcHost split threshold based on installed RAM
try {
    $ram = (Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1kb
    if ($ram -gt 0) {
        try {
            New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -Value $ram -Force -ErrorAction Stop | Out-Null
        } catch {
            Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -Value $ram -Force -ErrorAction Stop
        }
    }
} catch {
    Write-Warning "Failed to set SvcHostSplitThresholdInKB: $_"
}
    
# Disable AutoLogger
$autoLoggerDir = "$env:PROGRAMDATA\Microsoft\Diagnosis\ETLLogs\AutoLogger"
try {
    if (Test-Path "$autoLoggerDir\AutoLogger-Diagtrack-Listener.etl") {
        Remove-Item -Path "$autoLoggerDir\AutoLogger-Diagtrack-Listener.etl" -Force -ErrorAction SilentlyContinue
    }
    
    # Deny SYSTEM access to AutoLogger directory
    if (Test-Path $autoLoggerDir) {
        icacls $autoLoggerDir /deny "SYSTEM:(OI)(CI)F" /T /C | Out-Null
    }
} catch {
    Write-Warning "Failed to configure AutoLogger: $_"
}

# Disable sample submission in Windows Defender
try {
    if (Get-Command -Name Set-MpPreference -ErrorAction SilentlyContinue) {
        Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue | Out-Null
    }
} catch {
    Write-Warning "Failed to set Windows Defender sample submission preference: $_"
}
'@
        )
        UndoScript       = @(
            @"
    # Re-enable AutoLogger
    `$autoLoggerDir = "`$env:PROGRAMDATA\Microsoft\Diagnosis\ETLLogs\AutoLogger"
    if (Test-Path `$autoLoggerDir) {
        icacls `$autoLoggerDir /grant SYSTEM:(OI)(CI)F /T /C | Out-Null
    }
"@,
            @"
    # Reset SvcHostSplitThresholdInKB
    if (Test-Path 'HKLM:\SYSTEM\CurrentControlSet\Control') {
        Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'SvcHostSplitThresholdInKB' -Type DWord -Value 380000 -Force -ErrorAction SilentlyContinue
    }
"@,
            @"
    # Re-enable Windows Defender sample submission
    try {
        Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Write-Warning "Failed to re-enable Windows Defender sample submission: `$_"
    }
"@
        )
    },
    @{
        Category     = "Network"
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
        TweakValue   = 0x26 # Hexadecimal value (38 in decimal)
        DefaultValue = 0x2   # Common default for Win32PrioritySeparation (2 in decimal)
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
$applyButton.Text = "Apply tweaks(s)"
$applyButton.Size = New-Object System.Drawing.Size(150, 30)
$applyButton.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0)
$applyButton.BackColor = [System.Drawing.Color]::LimeGreen
$applyButton.Enabled = $false # Initially disabled
$applyButton.Anchor = [System.Windows.Forms.AnchorStyles]::Left
$buttonPanel.Controls.Add($applyButton)

# Reset Button
$resetButton = New-Object System.Windows.Forms.Button
$resetButton.Text = "Reset selected to Default"
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

# Add "Recommended" Button

$treeView.Add_AfterCheck({
        param($sender, $e)
        if ($global:IgnoreCheckEvent) { return }
        $global:IgnoreCheckEvent = $true

        if ($e.Node.Nodes.Count -gt 0) {
            # Category node: Check/Uncheck all children
            foreach ($child in $e.Node.Nodes) {
                $child.Checked = $e.Node.Checked
            }
        }
        else {
            # Tweak node: Update parent's checked state if all children are checked/unchecked
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
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    [System.Windows.Forms.MessageBox]::Show("winget was not found. Attempting to install the app installer (using winget) from the Microsoft Store.", "winget not found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    try {
        $process = Start-Process -FilePath "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1" -PassThru -NoNewWindow -ErrorAction Stop
        [System.Windows.Forms.MessageBox]::Show("Please install the 'App Installer' (Package ID: 9NBLGGH4NNS1) from the Microsoft Store window that opens. Then click 'OK' here when the installation is complete.", "Installing winget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        Start-Sleep -Seconds 5
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            [System.Windows.Forms.MessageBox]::Show("winget could not be found after installation. Please restart the script or make sure winget is installed correctly.", "Error in winget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            exit
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("winget was successfully detected. The script will continue.", "winget found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("An error occurred while attempting to open the Microsoft Store for winget installation: $_. Please install winget manually.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        exit
    }
}

$global:installedPackageIds = @{}
function Update-InstalledPackageIds {
    # Function to update the list of installed Winget packages
    param([System.Windows.Forms.Form]$parentForm, [System.Windows.Forms.ProgressBar]$progressBar, [System.Windows.Forms.Label]$statusLabel)
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
        if ($wingetResult.ExitCode -ne 0) {
            $errorMessage = "Winget 'list' command failed with error code $($wingetResult.ExitCode). "
            if (![string]::IsNullOrEmpty($wingetResult.Errors)) { $errorMessage += "Error: $($wingetResult.Errors)." }
            $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
            [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            $statusLabel.Text = "Status: Loading failed."
            return
        }
        if ([string]::IsNullOrEmpty($wingetResult.Output)) {
            [System.Windows.Forms.MessageBox]::Show("The winget 'list' command returned no output. Possibly a configuration issue.", "Winget warning", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            $statusLabel.Text = "Status: Loading failed."
            return
        }
        $installedPackagesRaw = $wingetResult.Output -split "`n"
        $global:installedPackageIds.Clear()
        foreach ($line in $installedPackagesRaw) {
            if ($line -match '^\s*Name\s+Id\s+Version') { continue }
            if ($line -match '^\s*---\s+---\s+---') { continue }
            if ($line -match '^\s*$') { continue }
            $cols = ($line.Trim() -split '\s{2,}')
            if ($cols.Length -ge 2) { 
                $global:installedPackageIds[$cols[1].Trim()] = $true
            }
        }
        $statusLabel.Text = "Status: Winget packages loaded."
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("An unexpected error occurred while retrieving the winget package list: $_", "Winget error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        $statusLabel.Text = "Status: Loading failed."
    }
    finally {
        $progressBar.Visible = $false
        $progressBar.Style = 'Blocks'
        $parentForm.Refresh()
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
        @{Name = "Vivaldi"; Id = "Vivaldi.Vivaldi" }
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
        @{Name = "Ubisoft Connect"; Id = "Ubisoft.Connect" }
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
        @{Name = "Wintoys"; Id = "9P8LTPGCBZXD" }
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
        @{Name = "TranslucentTB"; Id = "CharlesMilette.TranslucentTB" }
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
$tabDownloads.Controls.Add($downloadsMainPanel)| Out-Null

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
        # Highlight installed programs (bold + green)
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

        if ($global:IgnoreCheckEventDownloads) { 
            return 
        }

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
            $selectedNodes = $downloadTreeView.Nodes.Find("Installed", $true) | Where-Object { $_.Checked } # This "Installed" tag logic is problematic, fix later.

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

#region 8. Tab: Untested
$tabUntested = New-Object System.Windows.Forms.TabPage "Untested"
$tabControl.TabPages.Add($tabUntested) | Out-Null
# Example Label in Untested Tab
$untestedLabel = New-Object System.Windows.Forms.Label
$untestedLabel.Text = "These tweaks are untested and experimental."
$untestedLabel.AutoSize = $true
$untestedLabel.Location = New-Object System.Drawing.Point(15, 15)
$tabUntested.Controls.Add($untestedLabel) | Out-Null
#endregion

#region 9. Tab: About
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
$tabAbout.Controls.Add($aboutContainer) | Out-Null

# Create a panel for the about text with better styling
$textPanel = New-Object System.Windows.Forms.Panel
$textPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$textPanel.BackColor = [System.Drawing.Color]::FromArgb(245, 245, 245)
$textPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$textPanel.Height = 250  # Fixed height for the text panel
$aboutContainer.Controls.Add($textPanel, 0, 0) | Out-Null

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

#region 10. Final Execution
$form.Add_Shown({ # Initial calls for Home tab info and General tab setup
        Initialize-HomeTabContent -systemInfoPanel $systemInfoPanel -form $form -systemInfoTitle $systemInfoTitle
        GeneralTreeView -treeViewToPopulate $treeView # This line should call your GeneralTreeView
        Update-GeneralTweaksStatus -tweakNodes $global:allTweakNodes # Ensure this uses $global:allTweakNodes
        if (-not $script:downloadsTabInitialized) {
            $statusDownloadLabel.Text = "Status: Initializing Winget data..."
            $downloadProgressBar.Visible = $true
            $downloadProgressBar.Style = 'Marquee'
            $form.Refresh()
            Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
            $script:downloadsTabInitialized = $true
        }
    })

[void]$form.ShowDialog() # Show form

Write-Host "`nGoodbye! Thank you for using ShagUtil." -ForegroundColor Green
#endregion