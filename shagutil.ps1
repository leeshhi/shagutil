Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security # Needed ?
$scriptVersion = "0.0.9"

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

#region 3. Main Form & TabControl Setup
$global:hasChanges = $false
$global:restartNeeded = $false
$global:IgnoreCheckEvent = $false # For General tab TreeView
$global:IgnoreCheckEventDownloads = $false # For Downloads tab TreeView
# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Shag Windows Utility - Version $scriptVersion"
$form.Size = New-Object System.Drawing.Size(700, 850)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'Sizable' #FixedDialog
$form.MaximizeBox = $false
$form.MinimizeBox = $true
$form.ForeColor = [System.Drawing.Color]::Black
$form.Font = New-Object System.Drawing.Font("Segoe UI", 11)

### Form ToDo:
# > https://learn.microsoft.com/de-de/dotnet/api/system.windows.forms.control.anchor?view=windowsdesktop-9.0
# > https://learn.microsoft.com/de-de/dotnet/api/system.windows.forms.form.autoscalebasesize?view=windowsdesktop-8.0#system-windows-forms-form-autoscalebasesize



# TabControl setup  #  > Make tab size bigger
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = 'Fill'
$tabControl.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed

$tabControl.Add_DrawItem({ # DrawItem Event for individual tab text color
        param($sender, $e)
        $tab = $sender.TabPages[$e.Index]
        $font = $tabControl.Font
        $text = $tab.Text

        # Make tab size bigger

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

$form.Controls.Add($tabControl)

$form.Add_Load({ # Form Load Event (for Update Check)
        $updateInfo = CheckUpdates
        if ($updateInfo.UpdateAvailable) {
            Clear-Host
            Write-Host ""
            Write-Host ">>> UPDATE AVAILABLE! <<<" -ForegroundColor Yellow -BackgroundColor Red
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
$tabControl.TabPages.Add($tabHome)

#region Home Tab - System Information Panel & Functions
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
    $systemInfoPanel.Controls.Add($loadingLabel)
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
                            $systemInfoPanel.Controls.Add($label)
                            $yPos += 25
                        }
                    }
                    else {
                        $label = New-Object System.Windows.Forms.Label
                        $label.Text = $line
                        $label.AutoSize = $true
                        $label.Location = New-Object System.Drawing.Point(10, $yPos)
                        $systemInfoPanel.Controls.Add($label)
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

# Panel for System Information (top left)
$systemInfoPanel = New-Object System.Windows.Forms.Panel
$systemInfoPanel.Size = New-Object System.Drawing.Size(550, 400)
$systemInfoPanel.Location = New-Object System.Drawing.Point(10, 10)
$systemInfoPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabHome.Controls.Add($systemInfoPanel)

# Title for System Information in the panel
$systemInfoTitle = New-Object System.Windows.Forms.Label
$systemInfoTitle.Text = "System Information"
$systemInfoTitle.Font = New-Object System.Drawing.Font($systemInfoTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
$systemInfoTitle.AutoSize = $true
$systemInfoTitle.Location = New-Object System.Drawing.Point(10, 10)
$systemInfoPanel.Controls.Add($systemInfoTitle)
#endregion

#region Home Tab - Quick Links Panel
# Panel for Quick Links (directly below System Information)
$quickLinksPanel = New-Object System.Windows.Forms.Panel
$quickLinksPanel.Size = New-Object System.Drawing.Size(200, 200)
$quickLinksPanel.Location = New-Object System.Drawing.Point(10, ($systemInfoPanel.Location.Y + $systemInfoPanel.Size.Height + 20))
$quickLinksPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabHome.Controls.Add($quickLinksPanel)

# Title for Quick Links
$quickLinksTitle = New-Object System.Windows.Forms.Label
$quickLinksTitle.Text = "Quick Links"
$quickLinksTitle.Font = New-Object System.Drawing.Font($quickLinksTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
$quickLinksTitle.AutoSize = $true
$quickLinksTitle.Location = New-Object System.Drawing.Point(10, 10)
$quickLinksPanel.Controls.Add($quickLinksTitle)

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
    $quickLinksPanel.Controls.Add($button)
    $buttonYPos += 35
}
#endregion

#region Home Tab - Contact Information Panel
$contactPanel = New-Object System.Windows.Forms.Panel
$contactPanel.Size = New-Object System.Drawing.Size(200, 200)
$contactPanel.Location = New-Object System.Drawing.Point(($quickLinksPanel.Location.X + $quickLinksPanel.Size.Width + 20), $quickLinksPanel.Location.Y)
$contactPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabHome.Controls.Add($contactPanel)

# Title for Contact
$contactTitle = New-Object System.Windows.Forms.Label
$contactTitle.Text = "Connect with me"
$contactTitle.Font = New-Object System.Drawing.Font($contactTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
$contactTitle.AutoSize = $true
$contactTitle.Location = New-Object System.Drawing.Point(10, 10)
$contactPanel.Controls.Add($contactTitle)

# Contact Information (LinkLabels)
$contactYPos = 40
$websiteLink = New-Object System.Windows.Forms.LinkLabel
$websiteLink.Text = "Website"
$websiteLink.AutoSize = $true
$websiteLink.Location = New-Object System.Drawing.Point(10, $contactYPos)
$websiteLink.Add_LinkClicked({ Start-Process "https://shag.gg" })
$contactPanel.Controls.Add($websiteLink)
$contactYPos += 25

$githubLink = New-Object System.Windows.Forms.LinkLabel
$githubLink.Text = "GitHub"
$githubLink.AutoSize = $true
$githubLink.Location = New-Object System.Drawing.Point(10, $contactYPos)
$githubLink.Add_LinkClicked({ Start-Process "https://github.com/leeshhi" })
$contactPanel.Controls.Add($githubLink)
$contactYPos += 25

$discordLink = New-Object System.Windows.Forms.LinkLabel
$discordLink.Text = "Discord"
$discordLink.AutoSize = $true
$discordLink.Location = New-Object System.Drawing.Point(10, $contactYPos)
$discordLink.Add_LinkClicked({ Start-Process "https://discord.gg/gDmjYgydb3" })
$contactPanel.Controls.Add($discordLink)
$contactYPos += 25

$discord2Link = New-Object System.Windows.Forms.LinkLabel
$discord2Link.Text = "Discord (Shag.gg)"
$discord2Link.AutoSize = $true
$discord2Link.Location = New-Object System.Drawing.Point(10, $contactYPos)
$discord2Link.Add_LinkClicked({ Start-Process "https://discord.gg/qxPNcgtTqn" })
$contactPanel.Controls.Add($discord2Link)
$contactYPos += 25
#endregion
#endregion

#region 5. Tab: General
$tabGeneral = New-Object System.Windows.Forms.TabPage "Tweaks"
$tabControl.TabPages.Add($tabGeneral)

#region Tweak functions
function Get-RegistryValue {
    # Function to get current registry value
    param([string]$Path, [string]$Name)
    try {
        $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
        if ($value) {
            return $value.$Name
        }
        return $null
    }
    catch {
        Write-Warning ("Could not read registry value {0} from {1}: {2}" -f $Name, $Path, $_)
        return $null
    }
}

function Set-RegistryValue {
    # Function to set registry value
    param([string]$Path, [string]$Name, $Value, [string]$Type)
    try {
        if (-not (Test-Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force -ErrorAction Stop
        $global:hasChanges = $true
        return $true
    }
    catch {
        Write-Warning ("Could not set registry value {0} to {1} in {2}: {3}" -f $Name, $Value, $Path, $_)
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
#endregion
#endregion

#region Tweak Data
$generalTweaks = @(
    @{
        Name         = "Disable Desktop Icons Cache"
        Description  = "Disables the caching of desktop icons, which can sometimes cause display issues or bloat."
        Category     = "Performance"
        RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        ValueName    = "DisableThumbnailCache"
        TweakValue   = 1
        DefaultValue = 0
        ValueType    = "DWord"
    },
    @{
        Name         = "Disable Diagnostic Data"
        Description  = "Stops Windows from sending diagnostic and usage data to Microsoft."
        Category     = "Privacy"
        RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Privacy"
        ValueName    = "AllowTelemetry"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Name         = "Disable Game DVR (Xbox Game Bar)"
        Description  = "Turns off the Game DVR feature, which can impact game performance."
        Category     = "Gaming"
        RegistryPath = "HKCU:\System\GameConfigStore"
        ValueName    = "GameDVR_Enabled"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Name         = "Disable Search Indexer"
        Description  = "Disables the Windows Search Indexer service, saving disk I/O and RAM."
        Category     = "Performance"
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\WSearch"
        ValueName    = "Start"
        TweakValue   = 4 # 4 = Disabled
        DefaultValue = 2 # 2 = Automatic
        ValueType    = "DWord"
        Action       = "Service" # Indicates this is a service action, not just registry
        Service      = "WSearch"
    },
    @{
        Name         = "Disable Visual Effects (Adjust for best performance)"
        Description  = "Adjusts visual effects for best performance (disables animations, shadows etc.). This typically applies multiple settings, so we'll treat it as a group or a specific set of registry changes."
        Category     = "Visuals"
        # For simplicity, we'll represent this as a single tweak, but it often involves multiple registry keys.
        # For a full implementation, you'd list all affected keys/values here, or create a specific function.
        # Example for one part:
        RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        ValueName    = "VisualFXSetting"
        TweakValue   = 2 # 2 = Adjust for best performance
        DefaultValue = 0 # 0 = Let Windows choose what's best, or a specific default
        ValueType    = "DWord"
    },
    @{
        Name        = "XXX"
        Description = "XXX"
        Category    = "Advanced - CAUTION"
        #RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        #ValueName    = "DisableThumbnailCache"
        #TweakValue   = 1
        #DefaultValue = 0
        #ValueType    = "DWord"
    }
)
#endregion

#region GUI Elements
$treeView = New-Object System.Windows.Forms.TreeView
$treeView.Size = New-Object System.Drawing.Size(650, 550)
$treeView.Location = New-Object System.Drawing.Point(15, 15)
$treeView.HideSelection = $false
$treeView.CheckBoxes = $true
$treeView.ShowNodeToolTips = $true
#$treeView.ItemHeight = 20
$tabGeneral.Controls.Add($treeView)
$allTweakNodes = @()

function GeneralTreeView {
    # Populate TreeView with categories and tweaks
    param([Parameter(Mandatory = $true)][System.Windows.Forms.TreeView]$treeViewToPopulate)
    $treeViewToPopulate.Nodes.Clear()
    $tempTweakNodes = [System.Collections.Generic.List[System.Windows.Forms.TreeNode]]::new()
    $categories = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[PSObject]]]::new()

    foreach ($tweak in $generalTweaks) {
        $categoryName = $tweak.Category
        if ([string]::IsNullOrEmpty($categoryName)) {
            $categoryName = "Uncategorized"
        }
        if (-not $categories.ContainsKey($categoryName)) {
            $categories.Add($categoryName, [System.Collections.Generic.List[PSObject]]::new())
        }
        $categories[$categoryName].Add($tweak)
    }

    foreach ($categoryEntry in $categories.GetEnumerator() | Sort-Object Name) {
        $categoryName = $categoryEntry.Key
        $tweaksInThisCategory = $categoryEntry.Value
        $parentNode = New-Object System.Windows.Forms.TreeNode $categoryName
        $parentNode.ForeColor = [System.Drawing.Color]::RoyalBlue
        #$parentNode.NodeFont = New-Object System.Drawing.Font($treeViewToPopulate.Font, [System.Drawing.FontStyle]::Bold)
        $parentNode.NodeFont = New-Object System.Drawing.Font($treeViewToPopulate.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold)
        $treeViewToPopulate.Nodes.Add($parentNode) | Out-Null
        $parentNode.Expand() 
        
        foreach ($tweak in $tweaksInThisCategory | Sort-Object Name) {
            $childNode = New-Object System.Windows.Forms.TreeNode $tweak.Name
            $childNode.Tag = $tweak
            $childNode.ToolTipText = $tweak.Description
            $parentNode.Nodes.Add($childNode) | Out-Null
            $tempTweakNodes.Add($childNode)
        }
    }
    $global:allTweakNodes = $tempTweakNodes.ToArray()
}

function Update-GeneralTweaksStatus {
    # Function to update the visual status of tweaks in the TreeView
    foreach ($node in $global:allTweakNodes) {
        if (-not ($node -is [System.Windows.Forms.TreeNode]) -or -not $node.Tag) {
            Write-Warning "Überspringe ungültigen Knoten oder Knoten ohne Tweak-Daten in allTweakNodes. Knoten: $($node | Out-String)"
            continue
        }

        $tweak = $node.Tag
        $currentValue = $null

        if (($tweak.RegistryPath -ne $null -and $tweak.RegistryPath -ne "") -or `
            ($tweak.Action -eq "Service" -and $tweak.Service -ne $null -and $tweak.Service -ne "")) {
            if ($tweak.Action -eq "Service") {
                $currentValue = Get-ServiceStatus -serviceName $tweak.Service
            }
            else {
                if (-not (Test-Path $tweak.RegistryPath)) {
                    Write-Warning "Registry-Pfad existiert nicht: $($tweak.RegistryPath). Kann Wert für $($tweak.Name) nicht lesen."
                    $node.Checked = $false
                    #$node.NodeFont = New-Object System.Drawing.Font($treeView.Font, [System.Drawing.FontStyle]::Regular)
                    continue
                }
                $currentValue = Get-RegistryValue -path $tweak.RegistryPath -name $tweak.ValueName -type $tweak.ValueType
            }
            if (($currentValue -eq $tweak.TweakValue) -or ($tweak.Action -eq "Service" -and $currentValue -eq $tweak.TweakValue)) {
                $node.Checked = $true
                #$node.NodeFont = New-Object System.Drawing.Font($treeView.Font, [System.Drawing.FontStyle]::Bold)
                #$node.NodeFont = New-Object System.Drawing.Font($treeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
                $node.ForeColor = [System.Drawing.Color]::Green
            }
            else {
                $node.Checked = $false
                #$node.NodeFont = New-Object System.Drawing.Font($treeView.Font, [System.Drawing.FontStyle]::Regular)
            }
        }
        else {
            Write-Warning "Tweak-Daten fehlen oder sind ungültig für Knoten $($node.Text): $($tweak | Out-String). Status kann nicht bestimmt werden."
            $node.Checked = $false # Standardmäßig nicht ausgewählt
            #$node.NodeFont = New-Object System.Drawing.Font($treeView.Font, [System.Drawing.FontStyle]::Regular)
        }
    }
}

# Status Label (Footer)
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Size = New-Object System.Drawing.Size(650, 30)
$statusLabel.Location = New-Object System.Drawing.Point(15, ($treeView.Location.Y + $treeView.Size.Height + 10))
$statusLabel.TextAlign = 'MiddleLeft'
$statusLabel.Text = "Status: Ready"
$statusLabel.BackColor = [System.Drawing.Color]::LightGray
$tabGeneral.Controls.Add($statusLabel)
# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Size = New-Object System.Drawing.Size(650, 20)
$progressBar.Location = New-Object System.Drawing.Point(15, ($statusLabel.Location.Y + $statusLabel.Size.Height + 5))
$progressBar.Visible = $false
$tabGeneral.Controls.Add($progressBar)
# Buttons Panel
$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Size = New-Object System.Drawing.Size(650, 50)
$buttonPanel.Location = New-Object System.Drawing.Point(15, ($progressBar.Location.Y + $progressBar.Size.Height + 5))
$tabGeneral.Controls.Add($buttonPanel)
# Apply Button
$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = "Apply tweaks(s)"
$applyButton.Size = New-Object System.Drawing.Size(100, 30)
$applyButton.Location = New-Object System.Drawing.Point(0, 10)
$applyButton.BackColor = [System.Drawing.Color]::LimeGreen
$applyButton.Enabled = $false # Initially disabled
$buttonPanel.Controls.Add($applyButton)
# Reset Button
$resetButton = New-Object System.Windows.Forms.Button
$resetButton.Text = "Reset selected to Default"
$resetButton.AutoSize = New-Object System.Drawing.Size(180, 30)
$resetButton.Location = New-Object System.Drawing.Point(120, 10)
$resetButton.BackColor = [System.Drawing.Color]::DarkOrange
$resetButton.Enabled = $false # Initially disabled
$buttonPanel.Controls.Add($resetButton)
# Uncheck All Button for General Tab
$generalUncheckAllButton = New-Object System.Windows.Forms.Button
$generalUncheckAllButton.Text = "Uncheck all"
$generalUncheckAllButton.Size = New-Object System.Drawing.Size(100, 30)
$generalUncheckAllButton.Location = New-Object System.Drawing.Point(320, 10)
$generalUncheckAllButton.BackColor = [System.Drawing.Color]::SlateGray
$buttonPanel.Controls.Add($generalUncheckAllButton)
#endregion

#region Event Handlers
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
            # Tweak node: Update parent's checked state
            $parent = $e.Node.Parent
            if ($parent -ne $null) {
                $checkedChildrenCount = ($parent.Nodes | Where-Object { $_.Checked }).Count
                $parent.Checked = ($checkedChildrenCount -eq $parent.Nodes.Count)
            }
        }

        # Enable/Disable Apply/Reset buttons based on selections
        $checkedTweaks = $global:allTweakNodes | Where-Object { $_.Checked }
        $uncheckedTweaks = $global:allTweakNodes | Where-Object { -not $_.Checked }
        $applyButton.Enabled = $checkedTweaks.Count -gt 0
        $resetButton.Enabled = $uncheckedTweaks.Count -gt 0 # Reset enabled if any are unchecked (implying they are currently tweaked or could be reset)
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
            $progressBar.Maximum = $checkedTweaks.Count
            $progressBar.Value = 0
            $progressBar.Visible = $true
            $form.Refresh()

            $global:hasChanges = $false
            $global:restartNeeded = $false

            foreach ($node in $checkedTweaks) {
                $tweak = $node.Tag
                $statusLabel.Text = "Applying: $($tweak.Name)..."
                $form.Refresh()

                $success = $false
                if ($tweak.Action -eq "Service") {
                    $success = Set-ServiceStartType -ServiceName $tweak.Service -StartType $tweak.TweakValue
                }
                else {
                    $success = Set-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName -Value $tweak.TweakValue -Type $tweak.ValueType
                }

                if ($success) {
                    $progressBar.Value++
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("Failed to apply tweak: $($tweak.Name). Please check console for details.", "Error Applying Tweak", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }

            $progressBar.Visible = $false
            $statusLabel.Text = "Status: Tweak application complete."
            Update-GeneralTweaksStatus # Re-check status after applying
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
        # Get all tweaks that are NOT checked (meaning we want to reset them to default)
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
            $progressBar.Maximum = $toResetTweaks.Count
            $progressBar.Value = 0
            $progressBar.Visible = $true
            $form.Refresh()
            $global:hasChanges = $false
            $global:restartNeeded = $false

            foreach ($node in $toResetTweaks) {
                $tweak = $node.Tag
                $statusLabel.Text = "Resetting: $($tweak.Name)..."
                $form.Refresh()
                $success = $false

                if ($tweak.Action -eq "Service") {
                    $success = Set-ServiceStartType -ServiceName $tweak.Service -StartType $tweak.DefaultValue
                }
                else {
                    $success = Set-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName -Value $tweak.DefaultValue -Type $tweak.ValueType
                }
                if ($success) {
                    $progressBar.Value++
                }
                else {
                    [System.Windows.Forms.MessageBox]::Show("Failed to reset tweak: $($tweak.Name). Please check console for details.", "Error Resetting Tweak", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            }

            $progressBar.Visible = $false
            $statusLabel.Text = "Status: Tweak reset complete."
            Update-GeneralTweaksStatus # Re-check status after resetting
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

$generalUncheckAllButton.Add_Click({ # Uncheck All Button Click for General Tab
        $global:IgnoreCheckEvent = $true

        foreach ($parentNode in $treeView.Nodes) {
            foreach ($childNode in $parentNode.Nodes) { $childNode.Checked = $false }
            $parentNode.Checked = $false
        }

        $applyButton.Enabled = $false
        $resetButton.Enabled = $false
        $statusLabel.Text = "All selections cleared."
        $global:IgnoreCheckEvent = $false
    })
#endregion

#region 6. Tab: Downloads
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    #region Winget Installation/Check
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
#endregion

#region Winget Related Functions
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
            if ($cols.Length -ge 2) { $global:installedPackageIds[$cols[1].Trim()] = $true }
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
    Update-InstalledPackageIds -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel

    foreach ($node in $allProgramNodes) {
        $pkgId = $node.Tag
        if (Test-WingetPackageInstalled -packageId $pkgId) {
            #$node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
            #$node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font, [System.Drawing.FontStyle]::Bold)
            $node.ForeColor = [System.Drawing.Color]::Green
        }
        else {
            #$node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Regular)
            #$node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font, [System.Drawing.FontStyle]::Regular)
        }
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
        else { $notInstalled += $node }
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
#endregion

$tabDownloads = New-Object System.Windows.Forms.TabPage "Downloads"
$tabControl.TabPages.Add($tabDownloads)

#region Program Data
$programCategories = @{
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
#endregion

#region GUI Elements
# Label top
$downloadsLabel = New-Object System.Windows.Forms.Label
$downloadsLabel.Text = "Select the programs to install via winget:"
$downloadsLabel.AutoSize = $true
$downloadsLabel.Location = New-Object System.Drawing.Point(15, 15)
$tabDownloads.Controls.Add($downloadsLabel)

# TreeView with Checkboxes and Categories
$downloadTreeView = New-Object System.Windows.Forms.TreeView
$downloadTreeView.Size = New-Object System.Drawing.Size(650, 600)
$downloadTreeView.Location = New-Object System.Drawing.Point(15, 50)
$downloadTreeView.HideSelection = $false
$downloadTreeView.CheckBoxes = $true
$tabDownloads.Controls.Add($downloadTreeView)

# List to hold all program nodes for status checks
$allProgramNodes = @()

# Populate TreeView with categories and programs
foreach ($category in $programCategories.Keys) {
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

        $parentNode.Nodes.Add($childNode) | Out-Null
        $allProgramNodes += $childNode
    }
    $downloadTreeView.Nodes.Add($parentNode) | Out-Null
}

# Install Button
$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "Install"
$installButton.Size = New-Object System.Drawing.Size(100, 30)
$installButton.Location = New-Object System.Drawing.Point(15, 660)
$installButton.BackColor = [System.Drawing.Color]::LimeGreen
$installButton.Enabled = $false
$tabDownloads.Controls.Add($installButton)

# Uninstall Button
$uninstallButton = New-Object System.Windows.Forms.Button
$uninstallButton.Text = "Uninstall"
$uninstallButton.Size = New-Object System.Drawing.Size(100, 30)
$uninstallButton.Location = New-Object System.Drawing.Point(245, 660)
$uninstallButton.BackColor = [System.Drawing.Color]::Red
$uninstallButton.Enabled = $false
$tabDownloads.Controls.Add($uninstallButton)

# Update Button
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = "Update all"
$updateButton.Size = New-Object System.Drawing.Size(100, 30)
$updateButton.Location = New-Object System.Drawing.Point(130, 660)
$updateButton.BackColor = [System.Drawing.Color]::LimeGreen
$updateButton.Enabled = $true
$tabDownloads.Controls.Add($updateButton)

# Uncheck All Button
$uncheckAllButton = New-Object System.Windows.Forms.Button
$uncheckAllButton.Text = "Uncheck all"
$uncheckAllButton.Size = New-Object System.Drawing.Size(100, 30)
$uncheckAllButton.Location = New-Object System.Drawing.Point(360, 660)
$uncheckAllButton.BackColor = [System.Drawing.Color]::SlateGray
$tabDownloads.Controls.Add($uncheckAllButton)

# Status Label
$statusDownloadLabel = New-Object System.Windows.Forms.Label
$statusDownloadLabel.Size = New-Object System.Drawing.Size(600, 30)
$statusDownloadLabel.Location = New-Object System.Drawing.Point(15, 700)
$tabDownloads.Controls.Add($statusDownloadLabel)

# Progress Bar
$downloadProgressBar = New-Object System.Windows.Forms.ProgressBar
$downloadProgressBar.Size = New-Object System.Drawing.Size(600, 20)
$downloadProgressBar.Location = New-Object System.Drawing.Point(15, 730)
$downloadProgressBar.Visible = $false
$tabDownloads.Controls.Add($downloadProgressBar)
#endregion

#region Event Handlers
# TreeView AfterCheck event
$downloadTreeView.Add_AfterCheck({
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

# Uninstall Button Click
$uninstallButton.Add_Click({
        $status = Get-SelectedInstallStatus
        $toUninstall = $status.Installed
        if ($toUninstall.Count -eq 0) {
            $statusDownloadLabel.Text = "No installed program selected for uninstall."
            return
        }
        Uninstall-Programs -nodes $toUninstall
    })

# Install Button Click
$installButton.Add_Click({
        $status = Get-SelectedInstallStatus
        $toInstallOrUpdate = $status.AllSelected
        if ($toInstallOrUpdate.Count -eq 0) {
            $statusDownloadLabel.Text = "No program selected."
            return
        }
        Install-OrUpdate -nodes $toInstallOrUpdate
    })

# Update Button Click
$updateButton.Add_Click({
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

# Uncheck All Button Click
$uncheckAllButton.Add_Click({
        $global:IgnoreCheckEventDownloads = $true
    
        foreach ($parentNode in $downloadTreeView.Nodes) {
            foreach ($childNode in $parentNode.Nodes) { $childNode.Checked = $false }
            $parentNode.Checked = $false
        }
    
        $installButton.Enabled = $false
        $updateButton.Enabled = $true
        $uninstallButton.Enabled = $false
        $statusDownloadLabel.Text = "All selections cleared."
        $global:IgnoreCheckEventDownloads = $false
    })

#region 7. Tab: Untested
$tabUntested = New-Object System.Windows.Forms.TabPage "Untested"
$tabControl.TabPages.Add($tabUntested)
# Example Label in Untested Tab
$untestedLabel = New-Object System.Windows.Forms.Label
$untestedLabel.Text = "These tweaks are untested and experimental."
$untestedLabel.AutoSize = $true
$untestedLabel.Location = New-Object System.Drawing.Point(15, 15)
$tabUntested.Controls.Add($untestedLabel)
#endregion

#region 9. Tab: About
$tabAbout = New-Object System.Windows.Forms.TabPage "About"
$tabControl.TabPages.Add($tabAbout)

# About Text Labels
$aboutLabelYPos = 15
$aboutTextLines = @(
    "Hello, my name is Leeshhi. I'm a hobby programmer who does this in my free time and for fun.",
    "Additionally, I'm also a bit of a PC geek, as many would call it.",
    "", # Empty line for spacing
    "This tool was created to offer fellow gamers, like myself, genuine Windows optimizations",
    "that actually deliver results and aren't just generic nonsense that doesn't even exist.",
    "I started this project because there are so many poor tools available on the internet.",
    "", # Empty line for spacing
    "Only tweaks and adjustments that I personally use and/or have tested will appear here."
)

foreach ($line in $aboutTextLines) {
    $label = New-Object System.Windows.Forms.Label
    $label.Text = $line
    $label.AutoSize = $true
    $label.Location = New-Object System.Drawing.Point(15, $aboutLabelYPos)
    $tabAbout.Controls.Add($label)
    $aboutLabelYPos += 25 # Vertical spacing between lines
}

# Buttons for links
$aboutButtonYPos = $aboutLabelYPos + 20 # Starting position of buttons below the text

$discordButton = New-Object System.Windows.Forms.Button
$discordButton.Text = "Discord"
$discordButton.Size = New-Object System.Drawing.Size(150, 30)
$discordButton.Location = New-Object System.Drawing.Point(15, $aboutButtonYPos)
$discordButton.BackColor = [System.Drawing.Color]::DodgerBlue
$discordButton.Add_Click({ Start-Process "https://discord.gg/gDmjYgydb3" })
$tabAbout.Controls.Add($discordButton)
$aboutButtonYPos += 35

$botButton = New-Object System.Windows.Forms.Button
$botButton.Text = "Discord-bot"
$botButton.Size = New-Object System.Drawing.Size(150, 30)
$botButton.Location = New-Object System.Drawing.Point(15, $aboutButtonYPos)
$botButton.BackColor = [System.Drawing.Color]::YellowGreen
$botButton.Add_Click({ Start-Process "https://shag.gg" })
$tabAbout.Controls.Add($botButton)
$aboutButtonYPos += 35

$botDcButton = New-Object System.Windows.Forms.Button
$botDcButton.Text = "Bot web > shag.gg"
$botDcButton.Size = New-Object System.Drawing.Size(150, 30)
$botDcButton.Location = New-Object System.Drawing.Point(15, $aboutButtonYPos)
$botDcButton.BackColor = [System.Drawing.Color]::YellowGreen
$botDcButton.Add_Click({ Start-Process "https://discord.gg/qxPNcgtTqn" })
$tabAbout.Controls.Add($botDcButton)
$aboutButtonYPos += 35

$githubProjectButton = New-Object System.Windows.Forms.Button
$githubProjectButton.Text = "GitHub"
$githubProjectButton.Size = New-Object System.Drawing.Size(150, 30)
$githubProjectButton.Location = New-Object System.Drawing.Point(15, $aboutButtonYPos)
$githubProjectButton.BackColor = [System.Drawing.Color]::DodgerBlue
$githubProjectButton.Add_Click({ Start-Process "https://github.com/leeshhi" })
$tabAbout.Controls.Add($githubProjectButton)
#endregion

#region 9. Final Execution
# Initial calls for Home tab info and General tab setup
$form.Add_Shown({
        #Initialize-HomeTabContent
        Initialize-HomeTabContent -systemInfoPanel $systemInfoPanel -form $form -systemInfoTitle $systemInfoTitle
        GeneralTreeView -treeViewToPopulate $treeView # Diese Zeile ist jetzt IMMER aktiv
        #Update-GeneralTweaksStatus
        Update-GeneralTweaksStatus -tweakNodes $allTweakNodes

        if (-not $script:downloadsTabInitialized) {
            $statusDownloadLabel.Text = "Status: Initializing Winget data..."
            $downloadProgressBar.Visible = $true
            $downloadProgressBar.Style = 'Marquee'
            $form.Refresh()
            Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
            $script:downloadsTabInitialized = $true
        }
    })

# Show form
[void] $form.ShowDialog()

Write-Host "`nGoodbye! Thank you for using ShagUtil." -ForegroundColor Green
#endregion