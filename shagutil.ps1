#Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security # Needed ?
$scriptVersion = "0.1.3"

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
#endregion

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

#region 5. Tab: Tweaks
$tabTweaks = New-Object System.Windows.Forms.TabPage "Tweaks"
$tabControl.TabPages.Add($tabTweaks)

function Get-RegistryValue {
    param(
        [string]$Path,
        [string]$Name
    )
    try {
        if (Test-Path $Path) {
            # Attempt to get the value. Use -ErrorAction SilentlyContinue for non-existent names.
            # Select-Object -ExpandProperty is crucial to get the raw value, not a PS custom object.
            $value = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty $Name
            return $value
        }
    }
    catch {
        # Suppress common errors like path not found or name not found for cleaner output
        # Uncomment the line below for debugging purposes if needed
        # Write-Warning "Could not get registry value '$Name' from '$Path': $($_.Exception.Message)"
    }
    return $null # Return $null if path or name does not exist, or on error
}
function Set-RegistryValue {
    param(
        [string]$Path,
        [string]$Name,
        $Value,
        [string]$Type, # Expected types: "DWord", "String", "ExpandString", "Binary", "MultiString", "QWord"
        [switch]$RemoveEntry # If set, the registry entry will be removed instead of set
    )
    try {
        # Ensure the parent path exists before attempting to set/remove the item property
        $parentPath = Split-Path -Path $Path -Parent
        if (-not (Test-Path $parentPath)) {
            New-Item -Path $parentPath -Force | Out-Null # Create parent path if it doesn't exist
        }

        if ($RemoveEntry) {
            if (Test-Path $Path -PathType Container) {
                # Ensure the key exists before attempting removal
                Remove-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
                # Optional: Write-Host "Removed registry value '$Name' from '$Path'." -ForegroundColor Yellow
            }
            return $true # Assume success for removal attempts if no error occurred
        }
        else {
            # Use a switch statement for specific registry types
            switch ($Type) {
                "DWord" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type DWord -Force }
                "String" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type String -Force }
                "ExpandString" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type ExpandString -Force }
                "Binary" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type Binary -Force }
                "MultiString" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type MultiString -Force }
                "QWord" { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type QWord -Force }
                default {
                    # Fallback for unknown/unspecified type, defaults to String or Binary if value suggests
                    # This might need refinement based on actual common usage.
                    Write-Warning "Unknown or unspecified registry type '$Type' for '$Name' in '$Path'. Defaulting to String."
                    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Force # PowerShell often defaults to String or Binary
                }
            }
            # Optional: Write-Host "Set registry value '$Name' in '$Path' to '$Value' (Type: $Type)." -ForegroundColor Green
            return $true
        }
    }
    catch {
        Write-Warning "Failed to set/remove registry value '$Name' in '$Path': $($_.Exception.Message)"
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
    $selectedNodes = @($treeViewToApply.Nodes | Where-Object { $_.Checked -eq $true }) + @($treeViewToApply.Nodes | ForEach-Object { $_.Nodes } | Where-Object { $_.Checked -eq $true })

    foreach ($node in $selectedNodes) {
        $tweak = $node.Tag
        if ($tweak) {
            Write-Host "Applying tweak: $($tweak.Name)" -ForegroundColor Cyan
            
            # --- Bestehende Logik für RegistrySettings (Gruppierte Tweaks) ---
            if ($tweak.RegistrySettings) {
                foreach ($setting in $tweak.RegistrySettings) {
                    $result = Set-RegistryValue -Path $setting.Path -Name $setting.Name -Value $setting.Value -Type $setting.Type -RemoveEntry ($setting.Value -eq "<RemoveEntry>")
                    if ($result) {
                        Write-Host "  -> Applied registry setting: $($setting.Name) in $($setting.Path)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  -> Failed to apply registry setting: $($setting.Name) in $($setting.Path)" -ForegroundColor Red
                    }
                }
            }
            # --- Bestehende Logik für einzelne RegistryPath/ValueName (Einzelne Tweaks) ---
            elseif ($tweak.RegistryPath -and $tweak.ValueName) {
                if ($tweak.Action -eq "Service") {
                    try {
                        Set-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName -Value $tweak.TweakValue -Type $tweak.ValueType
                        Set-Service -Name $tweak.Service -StartupType $tweak.TweakValue -ErrorAction Stop # TweakValue is the startup type
                        Write-Host "  -> Set service '$($tweak.Service)' startup type to '$($tweak.TweakValue)' and updated registry." -ForegroundColor Green
                    }
                    catch {
                        Write-Host "  -> Failed to configure service '$($tweak.Service)': $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                else {
                    $result = Set-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName -Value $tweak.TweakValue -Type $tweak.ValueType -RemoveEntry ($tweak.TweakValue -eq "<RemoveEntry>")
                    if ($result) {
                        Write-Host "  -> Applied registry tweak: $($tweak.Name)" -ForegroundColor Green
                    }
                    else {
                        Write-Host "  -> Failed to apply registry tweak: $($tweak.Name)" -ForegroundColor Red
                    }
                }
            }
            # --- NEUE LOGIK: InvokeScript ausführen ---
            if ($tweak.InvokeScript) {
                Write-Host "  -> Executing InvokeScript for $($tweak.Name)..." -ForegroundColor Yellow
                foreach ($command in $tweak.InvokeScript) {
                    try {
                        # Invoke-Expression führt den String als PowerShell-Befehl aus
                        # Dies ist nützlich für powercfg.exe oder andere CLI-Befehle
                        Invoke-Expression $command
                        Write-Host "    - Executed: '$command'" -ForegroundColor DarkGreen
                    }
                    catch {
                        Write-Warning "    - Failed to execute command '$command': $($_.Exception.Message)"
                    }
                }
            }
            # --- Fallback für nicht definierte Tweaks ---
            else {
                Write-Warning "Tweak '$($tweak.Name)' has no valid registry settings or action defined to apply."
            }
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
            
            # --- Bestehende Logik für RegistrySettings (Gruppierte Tweaks) ---
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
            # --- Bestehende Logik für einzelne RegistryPath/ValueName (Einzelne Tweaks) ---
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
            # --- NEUE LOGIK: UndoScript ausführen ---
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
            # --- Fallback für nicht definierte Tweaks ---
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
        if ($tweak) {
            $isTweakActive = $true # Assume active unless proven otherwise for grouped tweaks
            if ($tweak.RegistrySettings) {
                # Check all settings for grouped tweak
                foreach ($setting in $tweak.RegistrySettings) {
                    $currentValue = Get-RegistryValue -Path $setting.Path -Name $setting.Name

                    if ($setting.Value -eq "<RemoveEntry>") {
                        # Tweak active if value is NOT present (i.e., it was successfully removed)
                        if ($null -ne $currentValue) {
                            $isTweakActive = $false
                            break # One setting not active, whole tweak is not active
                        }
                    }
                    else {
                        # Tweak active if current value matches TweakValue (case-insensitive for strings)
                        if ($null -eq $currentValue -or ($currentValue.ToString() -ne $setting.Value.ToString())) {
                            $isTweakActive = $false
                            break # One setting not active, whole tweak is not active
                        }
                    }
                }
            }
            elseif ($tweak.RegistryPath -and $tweak.ValueName) {
                # Check single registry tweak
                $currentValue = Get-RegistryValue -Path $tweak.RegistryPath -Name $tweak.ValueName

                if ($tweak.TweakValue -eq "<RemoveEntry>") {
                    # Tweak active if value is NOT present
                    if ($null -ne $currentValue) {
                        $isTweakActive = $false
                    }
                }
                else {
                    # Tweak active if current value matches TweakValue (case-insensitive for strings)
                    if ($null -eq $currentValue -or ($currentValue.ToString() -ne $tweak.TweakValue.ToString())) {
                        $isTweakActive = $false
                    }
                }
            }
            else {
                # If no registry settings are defined, consider it inactive or handle as needed
                # This could be for tweaks that don't modify registry or are not yet implemented for status checks
                $isTweakActive = $false
                # Write-Warning "Tweak $($tweak.Name) has no valid registry settings defined for status check."
            }

            # Use $global:IgnoreCheckEvent to prevent triggering AfterCheck recursively
            $global:IgnoreCheckEvent = $true 
            $node.Checked = $isTweakActive
            $global:IgnoreCheckEvent = $false

            if ($isTweakActive) {
                $node.ForeColor = [System.Drawing.Color]::Green
            }
            else {
                $node.ForeColor = [System.Drawing.Color]::Red
            }
        }
    }
}
function GeneralTreeView {
    param([Parameter(Mandatory = $true)][System.Windows.Forms.TreeView]$treeViewToPopulate)
    $treeViewToPopulate.Nodes.Clear()
    # Use a generic list for allTweakNodes to avoid issues with array resizing performance
    $global:allTweakNodes = [System.Collections.Generic.List[System.Windows.Forms.TreeNode]]::new()
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
        $parentNode.NodeFont = New-Object System.Drawing.Font($treeViewToPopulate.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold)
        $treeViewToPopulate.Nodes.Add($parentNode) | Out-Null
        $parentNode.Expand() 
        
        foreach ($tweak in $tweaksInThisCategory | Sort-Object Name) {
            $childNode = New-Object System.Windows.Forms.TreeNode ($tweak.Name)
            $childNode.Tag = $tweak # Store the full tweak object in the node's Tag property
            $childNode.ToolTipText = $tweak.Description
            $parentNode.Nodes.Add($childNode) | Out-Null
            $global:allTweakNodes.Add($childNode) # Add directly to the global list
        }
    }
    # Convert to array at the end if you prefer, but List is often better for dynamic additions
    # $global:allTweakNodes = $global:allTweakNodes.ToArray() 
}

$generalTweaks = @(
    @{
        Category     = "Visuals"
        Name         = "Disable Visual Effects (Adjust for best performance)"
        Description  = "Adjusts visual effects for best performance (disables animations, shadows etc.). This typically applies multiple settings, so we'll treat it as a group or a specific set of registry changes."
        RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
        ValueName    = "VisualFXSetting"
        TweakValue   = 2 # 2 = Adjust for best performance
        DefaultValue = 0 # 0 = Let Windows choose what's best, or a specific default
        ValueType    = "DWord"
    },
    @{
        Category     = "Privacy"
        Name         = "Disable ConsumerFeatures"
        Description  = "Windows 10 will not automatically install any games, third-party apps, or application links from the Windows Store for the signed-in user. Some default Apps will be inaccessible (eg. Phone Link)"
        RegistryPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
        ValueName    = "DisableWindowsConsumerFeatures"
        TweakValue   = 1
        DefaultValue = "<RemoveEntry>"
        ValueType    = "DWord"
    },
    @{
        Category     = "System"
        Name         = "Enable Long Paths"
        Description  = "Enables support for file paths longer than 260 characters."
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        ValueName    = "LongPathsEnabled"
        TweakValue   = 1
        DefaultValue = 0
        ValueType    = "DWord"
    },
    @{
        Category     = "Performance"
        Name         = "Set System Responsiveness (Multimedia)"
        Description  = "Optimizes system responsiveness for multimedia tasks."
        RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        ValueName    = "SystemResponsiveness"
        TweakValue   = 0
        DefaultValue = 1
        ValueType    = "DWord"
    },
    @{
        Category         = "Privacy"
        Name             = "Disable Notification Center & Push Notifications"
        Description      = "Deaktiviert das Benachrichtigungscenter, den Kalender und alle Push-Benachrichtigungen (Toast-Benachrichtigungen)."
        RegistrySettings = @(
            @{
                Path          = "HKCU:\Software\Policies\Microsoft\Windows\Explorer"
                Name          = "DisableNotificationCenter"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\PushNotifications"
                Name          = "ToastEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            }
        )
    },
    @{
        Category         = "Gaming"
        Name             = "Disable GameDVR"
        Description      = "Deaktiviert GameDVR-Funktionen in Windows."
        RegistrySettings = @(
            @{
                Path          = "HKCU:\System\GameConfigStore"
                Name          = "GameDVR_FSEBehavior"
                Value         = "2"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\System\GameConfigStore"
                Name          = "GameDVR_Enabled"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\System\GameConfigStore"
                Name          = "GameDVR_HonorUserFSEBehaviorMode"
                Value         = "1"
                OriginalValue = "0"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\System\GameConfigStore"
                Name          = "GameDVR_EFSEFeatureFlags"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
                Name          = "AllowGameDVR"
                Value         = "0"
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            }
        )
    },
    @{
        Category         = "Privacy"
        Name             = "Disable Activity History"
        Description      = "This erases recent docs, clipboard, and run history."
        RegistrySettings = @(
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
                Name          = "EnableActivityFeed"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
                Name          = "PublishUserActivities"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
                Name          = "UploadUserActivities"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            }
        )
    },
    @{
        Category         = "System"
        Name             = "Disable Hibernation"
        Description      = "Hibernation is really meant for laptops as it saves what's in memory before turning the pc off. It really should never be used, but some people are lazy and rely on it. Don't be like Bob. Bob likes hibernation."
        RegistrySettings = @(
            @{
                Path          = "HKLM:\System\CurrentControlSet\Control\Session Manager\Power"
                Name          = "HibernateEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
                Name          = "ShowHibernateOption"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            }
        )
        InvokeScript     = @("powercfg.exe /hibernate off")
        UndoScript       = @("powercfg.exe /hibernate on")
    },
    @{
        Category         = "System"
        Name             = "Disable Homegroup"
        Description      = "Disables HomeGroup - HomeGroup is a password-protected home networking service that lets you share your stuff with other PCs that are currently running and connected to your network."
        RegistrySettings = @(
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Services\HomeGroupListener"
                Name          = "Start"
                Value         = 3 # 3 = Manual
                OriginalValue = 2 # 2 = Automatic
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Services\HomeGroupProvider"
                Name          = "Start"
                Value         = 3 # 3 = Manual
                OriginalValue = 2 # 2 = Automatic
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
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location"
                Name          = "Value"
                Value         = "Deny"
                OriginalValue = "Allow"
                Type          = "String"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Sensor\Overrides\{BFA794E4-F964-4FDB-90F6-51056BFE4B44}"
                Name          = "SensorPermissionState"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Services\lfsvc\Service\Configuration"
                Name          = "Status"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\Maps"
                Name          = "AutoUpdateEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            }
        )
    },
    @{
        Category         = "Privacy"
        Name             = "Disable Telemetry"
        Description      = "Disables Microsoft Telemetry. Note: This will lock many Edge Browser settings. Microsoft spies heavily on you on using the Edge browser."
        RegistrySettings = @(
            # Registry-Einstellungen für Telemetrie und Inhaltsbereitstellung
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection"
                Name          = "AllowTelemetry"
                Value         = 0
                OriginalValue = "<RemoveEntry>" # Standard ist oft nicht vorhanden oder 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                Name          = "AllowTelemetry"
                Value         = 0
                OriginalValue = "<RemoveEntry>" # Standard ist oft nicht vorhanden oder 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "ContentDeliveryAllowed"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "OemPreInstalledAppsEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "PreInstalledAppsEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "PreInstalledAppsEverEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "SilentInstalledAppsEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "SubscribedContent-338387Enabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "SubscribedContent-338388Enabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "SubscribedContent-338389Enabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "SubscribedContent-353698Enabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
                Name          = "SystemPaneSuggestionsEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Siuf\Rules"
                Name          = "NumberOfSIUFInPeriod"
                Value         = 0
                OriginalValue = 0 # Annahme: Default ist 0 oder nicht vorhanden
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection"
                Name          = "DoNotShowFeedbackNotifications"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
                Name          = "DisableTailoredExperiencesWithDiagnosticData"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AdvertisingInfo"
                Name          = "DisabledByGroupPolicy"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\Windows Error Reporting"
                Name          = "Disabled"
                Value         = 1
                OriginalValue = 0
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
                Name          = "DODownloadMode"
                Value         = 1 # Peer-to-peer downloads (LAN only or disabled)
                OriginalValue = 1 # Standardwert, wenn nicht geändert
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance"
                Name          = "fAllowToGetHelp"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\OperationStatusManager"
                Name          = "EnthusiastMode"
                Value         = 1
                OriginalValue = 0
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Name          = "ShowTaskViewButton"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced\People"
                Name          = "PeopleBand"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Name          = "LaunchTo"
                Value         = 1 # Startet im Datei-Explorer auf 'Dieser PC'
                OriginalValue = 1 # Standardwert, wenn nicht geändert
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
                Name          = "LongPathsEnabled"
                Value         = 1
                OriginalValue = 0
                Type          = "DWord"
            },
            @{
                # Kommentar: "Driver searching is a function that should be left in" - Wert bleibt 1
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching"
                Name          = "SearchOrderConfig"
                Value         = 1
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
                Name          = "SystemResponsiveness"
                Value         = 0 # Optimiert für Multimedia
                OriginalValue = 1 # Standardwert
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
                Name          = "NetworkThrottlingIndex"
                Value         = 4294967295 # Deaktiviert Drosselung (FFFFFFFF in Hex)
                OriginalValue = 10 # Standardwert (oder 10 für Gaming)
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Control Panel\Desktop"
                Name          = "AutoEndTasks"
                Value         = 1 # Task beenden, wenn nicht reagiert
                OriginalValue = 0 # Standardwert
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management"
                Name          = "ClearPageFileAtShutdown"
                Value         = 0 # Deaktiviert das Löschen der Auslagerungsdatei beim Herunterfahren
                OriginalValue = 0 # Standardwert
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\ControlSet001\Services\Ndu"
                Name          = "Start"
                Value         = 2 # NDU (Network Diagnostic Usage) auf Manuell setzen (2=Automatic, 3=Manual, 4=Disabled)
                OriginalValue = 1 # Standardwert (Boot)
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
                Name          = "IRPStackSize"
                Value         = 30 # Erhöht IRPStackSize für größere Netzwerkpakete
                OriginalValue = 20 # Standardwert
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\Windows Feeds"
                Name          = "EnableFeeds"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Feeds"
                Name          = "ShellFeedsTaskbarViewMode"
                Value         = 2 # Ausblenden des News and Interests-Buttons
                OriginalValue = 1 # Standardwert
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
                Name          = "HideSCAMeetNow"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
                Name          = "ScoobeSystemSettingEnabled"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            }
        )
        InvokeScript     = @(
            @"
    bcdedit /set `{current`} bootmenupolicy Legacy | Out-Null
    If ((get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name CurrentBuild).CurrentBuild -lt 22557) {
        $taskmgr = Start-Process -WindowStyle Hidden -FilePath taskmgr.exe -PassThru
        Do {
            Start-Sleep -Milliseconds 100
            $preferences = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -ErrorAction SilentlyContinue
        } Until ($preferences)
        Stop-Process $taskmgr
        $preferences.Preferences[28] = 0
        Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -Type Binary -Value $preferences.Preferences
    }
    Remove-Item -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace\{0DB7E03F-FC29-4DC6-9020-FF41B59E513A}" -Recurse -ErrorAction SilentlyContinue
    If (Test-Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge") {
        Remove-Item -Path "HKLM:\SOFTWARE\Policies\Microsoft\Edge" -Recurse -ErrorAction SilentlyContinue
    }
    $ram = (Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum / 1kb
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "SvcHostSplitThresholdInKB" -Type DWord -Value $ram -Force
    
    $autoLoggerDir = "$env:PROGRAMDATA\Microsoft\Diagnosis\ETLLogs\AutoLogger"
    If (Test-Path "$autoLoggerDir\AutoLogger-Diagtrack-Listener.etl") {
        Remove-Item "$autoLoggerDir\AutoLogger-Diagtrack-Listener.etl"
    }
    icacls $autoLoggerDir /deny SYSTEM:`(OI`)`(CI`)F | Out-Null
    Set-MpPreference -SubmitSamplesConsent 2 -ErrorAction SilentlyContinue | Out-Null
    "@
        )
        UndoScript      = @(
            "schtasks /Change /TN 'Microsoft\\Windows\\Application Experience\\Microsoft Compatibility Appraiser' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Application Experience\\ProgramDataUpdater' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Autochk\\Proxy' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Customer Experience Improvement Program\\Consolidator' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Customer Experience Improvement Program\\UsbCeip' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\DiskDiagnostic\\Microsoft-Windows-DiskDiagnosticDataCollector' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Feedback\\Siuf\\DmClient' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Feedback\\Siuf\\DmClientOnScenarioDownload' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Windows Error Reporting\\QueueReporting' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Application Experience\\MareBackup' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Application Experience\\StartupAppTask' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Application Experience\\PcaPatchDbTask' /Enable | Out-Null",
            "schtasks /Change /TN 'Microsoft\\Windows\\Maps\\MapsUpdateTask' /Enable | Out-Null",
            "bcdedit /set {current} bootmenupolicy Standard | Out-Null",
    @"
    If ((get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -Name CurrentBuild).CurrentBuild -lt 22557) {
        $preferences = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -ErrorAction SilentlyContinue
        if ($preferences) {
            $preferences.Preferences[28] = 1 # Setzt den Wert auf den Standard zurück
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\TaskManager" -Name "Preferences" -Type Binary -Value $preferences.Preferences -Force
        }
    }
"@,
            @"
    $autoLoggerDir = "$env:PROGRAMDATA\Microsoft\Diagnosis\ETLLogs\AutoLogger"
    icacls $autoLoggerDir /grant SYSTEM:`(OI`)`(CI`)F | Out-Null
"@,
            "Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control' -Name 'SvcHostSplitThresholdInKB' -Type DWord -Value 380000 -Force",
            "Set-MpPreference -SubmitSamplesConsent 1 -ErrorAction SilentlyContinue | Out-Null"
        )
    },
    @{
        Category         = "Visuals"
        Name             = "Set Display for Performance"
        Description      = "Sets the system preferences to performance. You can do this manually with sysdm.cpl as well."
        RegistrySettings = @(
            @{
                Path          = "HKCU:\Control Panel\Desktop"
                Name          = "DragFullWindows"
                Value         = "0"
                OriginalValue = "1"
                Type          = "String"
            },
            @{
                Path          = "HKCU:\Control Panel\Desktop"
                Name          = "MenuShowDelay"
                Value         = "200"
                OriginalValue = "400"
                Type          = "String"
            },
            @{
                Path          = "HKCU:\Control Panel\Desktop\WindowMetrics"
                Name          = "MinAnimate"
                Value         = "0"
                OriginalValue = "1"
                Type          = "String"
            },
            @{
                Path          = "HKCU:\Control Panel\Keyboard"
                Name          = "KeyboardDelay"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Name          = "ListviewAlphaSelect"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Name          = "ListviewShadow"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Name          = "TaskbarAnimations"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
                Name          = "VisualFXSetting"
                Value         = "3" # 3 = Adjust for best performance
                OriginalValue = "1" # 1 = Let Windows choose what's best
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\DWM"
                Name          = "EnableAeroPeek"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Name          = "TaskbarMn" # Taskbar Multiple Monitors (vermutlich)
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Name          = "TaskbarDa" # Taskbar Desktop Apps (vermutlich)
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Name          = "ShowTaskViewButton"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
                Name          = "SearchboxTaskbarMode"
                Value         = "0" # 0 = Hidden
                OriginalValue = "1" # 1 = Icon only, 2 = Search box
                Type          = "DWord"
            }
        )
        InvokeScript     = @(
            @"
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" -Type Binary -Value ([byte[]](144,18,3,128,16,0,0,0))
"@
        )
        UndoScript       = @(
            @"
    Remove-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask"
"@
        )
    },
    @{
        Category     = "Taskbar"
        Name         = "Enable End Task With Right Click"
        Description  = "Enables option to end task when right clicking a program in the taskbar"
        InvokeScript = @(
            @"
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"
    $name = "TaskbarEndTask"
    $value = 1
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    New-ItemProperty -Path $path -Name $name -PropertyType DWord -Value $value -Force | Out-Null
"@
        )
        UndoScript   = @(
            @"
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings"
    $name = "TaskbarEndTask"
    $value = 0
    if (-not (Test-Path $path)) {
        New-Item -Path $path -Force | Out-Null
    }
    New-ItemProperty -Path $path -Name $name -PropertyType DWord -Value $value -Force | Out-Null
"@
        )
    },
    @{
        Category     = "System"
        Name         = "Disable Storage Sense"
        Description  = "Storage Sense deletes temp files automatically."
        InvokeScript = @(
            @"
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -Value 0 -Type Dword -Force
"@
        )
        UndoScript   = @(
            @"
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy" -Name "01" -Value 1 -Type Dword -Force
"@
        )
    },
    @{
        Category         = "Privacy"
        Name             = "Disable Microsoft Copilot"
        Description      = "Disables MS Copilot AI built into Windows since 23H2."
        RegistrySettings = @(
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot"
                Name          = "TurnOffWindowsCopilot"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot"
                Name          = "TurnOffWindowsCopilot"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                Name          = "ShowCopilotButton"
                Value         = 0
                OriginalValue = 1
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot"
                Name          = "IsCopilotAvailable"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot"
                Name          = "CopilotDisabledReason"
                Value         = "IsEnabledForGeographicRegionFailed"
                OriginalValue = "<RemoveEntry>"
                Type          = "String"
            },
            @{
                Path          = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsCopilot"
                Name          = "AllowCopilotRuntime"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Shell Extensions\Blocked"
                Name          = "{CB3B0003-8088-4EDE-8769-8B354AB2FF8C}"
                Value         = ""
                OriginalValue = "<RemoveEntry>"
                Type          = "String"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\Windows\Shell\Copilot\BingChat"
                Name          = "IsUserEligible"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            }
        )
        InvokeScript     = @(
            @"
    Write-Host "Remove Copilot"
    Get-Package | Where-Object Name -like '*copilot*' | ForEach-Object {
        if ($_.ProviderName -eq 'msi') {
            Write-Warning "MSI package $($_.Name) found. Manual uninstallation might be required if Remove-Package fails."
            try {
                Invoke-WingetCommand -arguments "uninstall --id $($_.Id) --accept-source-agreements" -timeoutSeconds 180
            } catch {
                Write-Warning "Could not uninstall $($_.Name) via winget: $($_.Exception.Message)"
            }
        } else {
            # For other package types, try Remove-Package
            try {
                Remove-Package -Name $_.Name -ErrorAction Stop
            } catch {
                Write-Warning "Could not uninstall $($_.Name) via Remove-Package: $($_.Exception.Message)"
            }
        }
    }
    Get-AppxPackage -AllUsers *Copilot* | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Get-AppxProvisionedPackage -Online | Where-Object PackageName -like '*Copilot*' | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue
    $copilotDismPackage = (Get-WindowsPackage -Online | Where-Object PackageName -like 'Microsoft.Windows.Copilot%')
    if ($copilotDismPackage) {
        Remove-WindowsPackage -Online -PackageName $copilotDismPackage.PackageName -ErrorAction SilentlyContinue
    }
"@
        )
        UndoScript       = @(
            @"
    Write-Host "Install Copilot"
    winget install --name "Microsoft Copilot" --source msstore --accept-package-agreements --accept-source-agreements --silent -ErrorAction SilentlyContinue
"@
        )
    },
    @{
        Category         = "Privacy"
        Name             = "Disable Recall"
        Description      = "Turn Recall off"
        RegistrySettings = @(
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
                Name          = "DisableAIDataAnalysis"
                Value         = 1
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI"
                Name          = "AllowRecallEnablement"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy"
                Name          = "VerifiedAndReputablePolicyState"
                Value         = 0
                OriginalValue = "<RemoveEntry>"
                Type          = "DWord"
            }
        )
        InvokeScript     = @(
            @"
    Write-Host "Disable Recall"
    DISM /Online /Disable-Feature /FeatureName:Recall /Quiet /NoRestart
    Write-Host "Please restart your computer in order for the changes to be fully applied."
"@
        )
        UndoScript       = @(
            @"
    Write-Host "Enable Recall"
    DISM /Online /Enable-Feature /FeatureName:Recall /Quiet /NoRestart
    Write-Host "Please restart your computer in order for the changes to be fully applied."
"@
        )
    },
    @{
        Category     = "Visuals"
        Name         = "Set Classic Right-Click Menu"
        Description  = "Great Windows 11 tweak to bring back good context menus when right clicking things in explorer."
        InvokeScript = @(
            @"
    New-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Name "InprocServer32" -force -value ""
    Write-Host "Restarting explorer.exe ..."
    Stop-Process -Name "explorer" -Force
"@
        )
        UndoScript   = @(
            @"
    Remove-Item -Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" -Recurse -Confirm:$false -Force
    # Restarting Explorer in the Undo Script might not be necessary, as the Registry change without restarting Explorer does work, but just to make sure.
    Write-Host "Restarting explorer.exe ..."
    Stop-Process -Name "explorer" -Force
"@
        )
    },
    @{
        Category     = "Cleanup"
        Name         = "Delete Temporary Files"
        Description  = "Erases TEMP Folders. Note: This action is irreversible and will permanently delete files."
        InvokeScript = @(
            @"
    Get-ChildItem -Path "C:\Windows\Temp" -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
    Get-ChildItem -Path $env:TEMP -Recurse -ErrorAction SilentlyContinue | Remove-Item -Force -Recurse -ErrorAction SilentlyContinue
"@
        )
    },
    @{
        Category     = "Network"
        Name         = "Prefer IPv4 over IPv6"
        Description  = "To set the IPv4 preference can have latency and security benefits on private networks where IPv6 is not configured."
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
        ValueName    = "DisabledComponents"
        TweakValue   = "32"
        DefaultValue = "0"
        ValueType    = "DWord"
    },
    @{
        Category         = "Advanced - CAUTION"
        Name             = "Disable Teredo"
        Description      = "Teredo network tunneling is a ipv6 feature that can cause additional latency, but may cause problems with some games"
        RegistrySettings = @(
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
                Name          = "DisabledComponents"
                Value         = "1"
                OriginalValue = "0"
                Type          = "DWord"
            }
        )
        InvokeScript     = @(
            @"
    netsh interface teredo set state disabled
"@
        )
        UndoScript       = @(
            @"
    netsh interface teredo set state default
"@
        )
    },
    @{
        Category         = "Advanced - CAUTION"
        Name             = "Disable IPv6"
        Description      = "Disables IPv6."
        RegistrySettings = @(
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip6\Parameters"
                Name          = "DisabledComponents"
                Value         = "255"
                OriginalValue = "0"
                Type          = "DWord"
            }
        )
        InvokeScript     = @(
            @"
    Disable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6
"@
        )
        UndoScript       = @(
            @"
    Enable-NetAdapterBinding -Name "*" -ComponentID ms_tcpip6
"@
        )
    },
    @{
        Category     = "Performance"
        Name         = "Disable Background Apps"
        Description  = "Disables all Microsoft Store apps from running in the background, which has to be done individually since Win11"
        RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications"
        ValueName    = "GlobalUserDisabled"
        TweakValue   = "1"
        DefaultValue = "0"
        ValueType    = "DWord"
    },
    @{
        Category     = "Gaming"
        Name         = "Disable Fullscreen Optimizations"
        Description  = "Disables FSO in all applications. NOTE: This will disable Color Management in Exclusive Fullscreen"
        RegistryPath = "HKCU:\System\GameConfigStore"
        ValueName    = "GameDVR_DXGIHonorFSEWindowsCompatible"
        TweakValue   = "1"
        DefaultValue = "0"
        ValueType    = "DWord"
    },
    @{
        Category     = "Privacy"
        Name         = "Bing Search in Start Menu"
        Description  = "If enabled, includes web search results from Bing in your Start Menu search."
        RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        ValueName    = "BingSearchEnabled"
        TweakValue   = "1"
        DefaultValue = "0" # OriginalValue aus deiner Angabe
        ValueType    = "DWord"
    },
    @{
        Category         = "System"
        Name             = "NumLock on Startup"
        Description      = "Toggle the Num Lock key state when your computer starts."
        RegistrySettings = @(
            @{
                Path          = "HKU:\.Default\Control Panel\Keyboard"
                Name          = "InitialKeyboardIndicators"
                Value         = "2"
                OriginalValue = "0"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Control Panel\Keyboard"
                Name          = "InitialKeyboardIndicators"
                Value         = "2"
                OriginalValue = "0"
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "System"
        Name         = "Verbose Messages During Logon"
        Description  = "Show detailed messages during the login process for troubleshooting and diagnostics."
        RegistryPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
        ValueName    = "VerboseStatus"
        TweakValue   = "1"
        DefaultValue = "0"
        ValueType    = "DWord"
    },
    @{
        Category         = "Privacy"
        Name             = "Recommendations in Start Menu"
        Description      = "If disabled then you will not see recommendations in the Start Menu. | Enables 'iseducationenvironment' | Relogin Required. | WARNING: This will also disable Windows Spotlight on your Lock Screen as a side effect."
        RegistrySettings = @(
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Start"
                Name          = "HideRecommendedSection"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\Education"
                Name          = "IsEducationEnvironment"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer"
                Name          = "HideRecommendedSection"
                Value         = "0"
                OriginalValue = "1"
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Visuals"
        Name         = "Remove Settings Home Page"
        Description  = "Removes the Home page in the Windows Settings app."
        RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer"
        ValueName    = "SettingsPageVisibility"
        TweakValue   = "hide:home"
        DefaultValue = "show:home"
        ValueType    = "String"
    },
    @{
        Category         = "Gaming"
        Name             = "Mouse Acceleration"
        Description      = "If Enabled then Cursor movement is affected by the speed of your physical mouse movements."
        RegistrySettings = @(
            @{
                Path          = "HKCU:\Control Panel\Mouse"
                Name          = "MouseSpeed"
                Value         = "1"
                OriginalValue = "0"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Control Panel\Mouse"
                Name          = "MouseThreshold1"
                Value         = "6"
                OriginalValue = "0"
                Type          = "DWord"
            },
            @{
                Path          = "HKCU:\Control Panel\Mouse"
                Name          = "MouseThreshold2"
                Value         = "10"
                OriginalValue = "0"
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Accessibility"
        Name         = "Sticky Keys"
        Description  = "If Enabled then Sticky Keys is activated - Sticky keys is an accessibility feature of some graphical user interfaces which assists users who have physical disabilities or help users reduce repetitive strain injury."
        RegistryPath = "HKCU:\Control Panel\Accessibility\StickyKeys"
        ValueName    = "Flags"
        TweakValue   = "510"
        DefaultValue = "58"
        ValueType    = "DWord"
    },
    @{
        Category     = "Taskbar"
        Name         = "Search Button in Taskbar"
        Description  = "If Enabled Search Button will be on the taskbar."
        RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        ValueName    = "SearchboxTaskbarMode"
        TweakValue   = "1"
        DefaultValue = "0"
        ValueType    = "DWord"
    },
    @{
        Category         = "System"
        Name             = "Detailed BSoD"
        Description      = "If Enabled then you will see a detailed Blue Screen of Death (BSOD) with more information."
        RegistrySettings = @(
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"
                Name          = "DisplayParameters"
                Value         = "1"
                OriginalValue = "0"
                Type          = "DWord"
            },
            @{
                Path          = "HKLM:\SYSTEM\CurrentControlSet\Control\CrashControl"
                Name          = "DisableEmoticon"
                Value         = "1"
                OriginalValue = "0"
                Type          = "DWord"
            }
        )
    },
    @{
        Category     = "Power"
        Name         = "S3 Sleep"
        Description  = "Toggles between Modern Standby and S3 sleep."
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
        ValueName    = "PlatformAoAcOverride"
        TweakValue   = "0"
        DefaultValue = "<RemoveEntry>"
        ValueType    = "DWord"
    },
    @{
        Category     = "Performance"
        Name         = "Disable Explorer Automatic Folder Discovery"
        Description  = "Windows Explorer automatically tries to guess the type of the folder based on its contents, slowing down the browsing experience."
        InvokeScript = @(
            @"
    # Previously detected folders
    $bags = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags"
    $bagMRU = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"
    Remove-Item -Path $bags -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed $bags"
    Remove-Item -Path $bagMRU -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed $bagMRU"
    $allFolders = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell"
    if (!(Test-Path $allFolders)) {
        New-Item -Path $allFolders -Force | Out-Null
        Write-Host "Created $allFolders"
    }
    New-ItemProperty -Path $allFolders -Name "FolderType" -Value "NotSpecified" -PropertyType String -Force | Out-Null
    Write-Host "Set FolderType to NotSpecified"
    Write-Host "Please sign out and back in, or restart your computer to apply the changes!"
"@
        )
        UndoScript   = @(
            @"
    $bags = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags"
    $bagMRU = "HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\BagMRU"
    Remove-Item -Path $bags -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed $bags"
    Remove-Item -Path $bagMRU -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Removed $bagMRU"
    Write-Host "Please sign out and back in, or restart your computer to apply the changes!"
"@
        )
    },
    @{
        Category     = "Performance"
        Name         = "Win 32 Priority Separation"
        Description  = "Adjusts how Windows allocates CPU time to foreground and background applications. Setting to '26' (hex) gives more priority to foreground applications."
        RegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Control\PriorityControl"
        ValueName    = "Win32PrioritySeparation"
        TweakValue   = "26" # Hexadecimal value
        DefaultValue = "2"  # Common default for Win32PrioritySeparation (hex)
        ValueType    = "DWord"
    }
)

$treeView = New-Object System.Windows.Forms.TreeView
$treeView.Size = New-Object System.Drawing.Size(650, 550)
$treeView.Location = New-Object System.Drawing.Point(15, 15)
$treeView.HideSelection = $false
$treeView.CheckBoxes = $true
$treeView.ShowNodeToolTips = $true
$tabTweaks.Controls.Add($treeView)
$allTweakNodes = @()

# Status Label (Footer)
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Size = New-Object System.Drawing.Size(650, 30)
$statusLabel.Location = New-Object System.Drawing.Point(15, ($treeView.Location.Y + $treeView.Size.Height + 10))
$statusLabel.TextAlign = 'MiddleLeft'
$statusLabel.Text = "Status: Ready"
$statusLabel.BackColor = [System.Drawing.Color]::LightGray
$tabTweaks.Controls.Add($statusLabel)
# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Size = New-Object System.Drawing.Size(650, 20)
$progressBar.Location = New-Object System.Drawing.Point(15, ($statusLabel.Location.Y + $statusLabel.Size.Height + 5))
$progressBar.Visible = $false
$tabTweaks.Controls.Add($progressBar)
# Buttons Panel
$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Size = New-Object System.Drawing.Size(650, 50)
$buttonPanel.Location = New-Object System.Drawing.Point(15, ($progressBar.Location.Y + $progressBar.Size.Height + 5))
$tabTweaks.Controls.Add($buttonPanel)
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

$tabDownloads = New-Object System.Windows.Forms.TabPage "Downloads"
$tabControl.TabPages.Add($tabDownloads)

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
            foreach ($childNode in $parentNode.Nodes) { $childNode.Checked = $false }
            $parentNode.Checked = $false
        }
    
        $installButton.Enabled = $false
        $updateButton.Enabled = $true
        $uninstallButton.Enabled = $false
        $statusDownloadLabel.Text = "All selections cleared."
        $global:IgnoreCheckEventDownloads = $false
    })
#endregion

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
$form.Add_Shown({ # Initial calls for Home tab info and General tab setup
        #Initialize-HomeTabContent
        Initialize-HomeTabContent -systemInfoPanel $systemInfoPanel -form $form -systemInfoTitle $systemInfoTitle
        GeneralTreeView -treeViewToPopulate $treeView # This line should call your GeneralTreeView
        #Update-GeneralTweaksStatus
        #Update-GeneralTweaksStatus -tweakNodes $allTweakNodes
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

# Show form
[void] $form.ShowDialog()

Write-Host "`nGoodbye! Thank you for using ShagUtil." -ForegroundColor Green
#endregion