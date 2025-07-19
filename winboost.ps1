Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Security

$scriptVersion = "0.0.5"

#region 1. Initial Script Setup & Admin Check

# Admin Check
if (-not ([Security.Principal.WindowsPrincipal][System.Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
    [System.Windows.Forms.MessageBox]::Show("This script must be run as an Administrator. Please restart PowerShell or the script file with administrative privileges.", "Administrator Privileges Required", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Stop)
    exit
}

# Welcome Message (GEÄNDERT: 'shag.gg' ASCII Art)
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

#endregion

#region 2. Global Helper Functions

# Function: Recursively set font size for all controls within a control
function Set-FontSizeRecursive {
    param([System.Windows.Forms.Control]$control, [float]$fontSize)

    $newFont = New-Object System.Drawing.Font($control.Font.FontFamily, $fontSize, $control.Font.Style)
    $control.Font = $newFont

    foreach ($child in $control.Controls) {
        Set-FontSizeRecursive -control $child -fontSize $fontSize
    }
}

# Function: Check for script updates
function Check-ForUpdates {
    param(
        [string]$currentVersion = $scriptVersion,
        [string]$githubRawUrl = "https://raw.githubusercontent.com/leeshhi/winboost/main/version.txt"
    )

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
                RepoLink        = "https://github.com/leeshhi/winboost"
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

# Function: Invoke Winget Commands and Log Output
function Invoke-WingetCommand {
    param(
        [string]$arguments,
        [int]$timeoutSeconds = 60
    )

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

# Restart Explorer Function
function Restart-Explorer {
    Get-Process explorer | Stop-Process -Force
    Start-Sleep -Seconds 1
    Start-Process explorer.exe
}

# Global Variables for Tweaks
$global:hasChanges = $false
$global:restartNeeded = $false
$global:IgnoreCheckEvent = $false # For General tab TreeView
$global:IgnoreCheckEventDownloads = $false # For Downloads tab TreeView

#endregion

#region 3. Main Form & TabControl Setup

# Colors
$darkBackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$darkForeColor = [System.Drawing.Color]::White
$footerBackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
$accentColor = [System.Drawing.Color]::FromArgb(0, 122, 204)

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Tweaks Tool by leeshhi - Version $scriptVersion"
$form.Size = New-Object System.Drawing.Size(700, 850)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = $darkBackColor
$form.ForeColor = $darkForeColor
$form.Font = New-Object System.Drawing.Font("Segoe UI", 11)

# TabControl setup
$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = 'Fill'
$tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 14)
$tabControl.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed

# DrawItem Event for individual tab text color
$tabControl.Add_DrawItem({
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

        $e.Graphics.FillRectangle([System.Drawing.Brushes]::LightGray, $rect)

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

# Form Load Event (for Update Check)
$form.Add_Load({
        $updateInfo = Check-ForUpdates
        if ($updateInfo.UpdateAvailable) {
            Write-Host ">>> UPDATE AVAILABLE! <<<" -ForegroundColor Yellow -BackgroundColor Red
            Write-Host "A new version ($($updateInfo.RemoteVersion)) is available!" -ForegroundColor Yellow
            Write-Host "Your current version is $($updateInfo.CurrentVersion)." -ForegroundColor Yellow
            Write-Host "Please update your tool via the GitHub link: $($updateInfo.RepoLink)" -ForegroundColor Yellow
            Write-Host "Run the start command again to use the new version." -ForegroundColor Yellow
            Write-Host "*********************************************" -ForegroundColor White
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
$tabHome.BackColor = $darkBackColor
$tabHome.ForeColor = $darkForeColor
$tabControl.TabPages.Add($tabHome)

#region Home Tab - System Information Panel & Functions

# Functions to get system information
function Get-OsInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    "OS: $($os.Caption) Version $($os.Version) (Build $($os.BuildNumber))"
}

function Get-CpuInfo {
    $cpu = Get-CimInstance Win32_Processor
    "CPU: $($cpu.Name) ($($cpu.NumberOfCores) Cores, $($cpu.NumberOfLogicalProcessors) Threads)"
}

function Get-RamInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $ram = Get-CimInstance Win32_ComputerSystem
    $totalMemoryGB = [Math]::Round(($ram.TotalPhysicalMemory / 1GB), 2)
    $freeMemoryGB = [Math]::Round(($os.FreePhysicalMemory / (1024 * 1024)), 2)
    "RAM: ${totalMemoryGB}GB Total / ${freeMemoryGB}GB Available"
}

function Get-GpuInfo {
    $gpus = Get-CimInstance Win32_VideoController | Select-Object Name
    $gpuStrings = @()
    foreach ($gpu in $gpus) { $gpuStrings += "$($gpu.Name)" }
    if ($gpuStrings.Count -gt 0) { "GPU: " + ($gpuStrings -join ", ") } else { "GPU: Not found" }
}

function Get-MotherboardInfo {
    $board = Get-CimInstance Win32_BaseBoard
    "Motherboard: $($board.Manufacturer) $($board.Product)"
}

function Get-BiosInfo {
    $bios = Get-CimInstance Win32_BIOS
    "BIOS: $($bios.Caption) Version $($bios.SMBIOSBIOSVersion) (Date: $($bios.ReleaseDate))"
}

function Get-NetworkInfo {
    $computerName = $env:COMPUTERNAME
    "Device Name: $computerName"
}

# Main function to retrieve and display all system information
function Get-AndDisplayAllSystemInfo {
    $yPos = 40
    $systemInfoLabels = @(
        (Get-OsInfo),
        (Get-CpuInfo),
        (Get-RamInfo),
        (Get-GpuInfo),
        (Get-MotherboardInfo),
        (Get-BiosInfo),
        (Get-NetworkInfo)
    )

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
    $button.BackColor = $accentColor
    $button.ForeColor = [System.Drawing.Color]::White
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

Set-FontSizeRecursive -control $tabHome -fontSize 11

#endregion

#region 5. Tab: General

$tabGeneral = New-Object System.Windows.Forms.TabPage "General"
$tabGeneral.BackColor = $darkBackColor
$tabGeneral.ForeColor = $darkForeColor
$tabControl.TabPages.Add($tabGeneral)

#region General Tab - Tweak Data

$tweakCategories = @(
    @{
        Category = "Explorer Settings"
        Tweaks   = @(
            @{ Label = "Show file extensions"; RestartNeeded = $false;
                Enable = { Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 }
                Disable = { Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 1 }
                GetState = { ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt").HideFileExt -eq 0) }
                Default = $true
            },
            @{ Label = "Show hidden files"; RestartNeeded = $false;
                Enable = { Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 }
                Disable = { Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 2 }
                GetState = { ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden").Hidden -eq 1) }
                Default = $false
            }
        )
    },
    @{
        Category = "Search Function"
        Tweaks   = @(
            @{ Label = "Disable Explorer search box"; RestartNeeded = $true;
                Enable = { Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 }
                Disable = { Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1 }
                GetState = { ((Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode").SearchboxTaskbarMode -eq 0) }
                Default = $false
            }
        )
    }
)

#endregion

#region General Tab - GUI Elements

$treeView = New-Object System.Windows.Forms.TreeView
$treeView.Size = New-Object System.Drawing.Size(650, 600)
$treeView.Location = New-Object System.Drawing.Point(15, 15)
$treeView.BackColor = $darkBackColor
$treeView.ForeColor = $darkForeColor
$treeView.HideSelection = $false
$treeView.CheckBoxes = $true
$tabGeneral.Controls.Add($treeView)

# Status Label (Footer)
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Size = New-Object System.Drawing.Size(650, 30)
$statusLabel.Location = New-Object System.Drawing.Point(15, 620)
$statusLabel.TextAlign = 'MiddleLeft'
$statusLabel.Text = "Status: Ready"
$statusLabel.ForeColor = $darkForeColor
$statusLabel.BackColor = $footerBackColor
$tabGeneral.Controls.Add($statusLabel)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Size = New-Object System.Drawing.Size(650, 20)
$progressBar.Location = New-Object System.Drawing.Point(15, 655)
$progressBar.Visible = $false
$tabGeneral.Controls.Add($progressBar)

# Buttons Panel
$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Size = New-Object System.Drawing.Size(650, 50)
$buttonPanel.Location = New-Object System.Drawing.Point(15, 685)
$buttonPanel.BackColor = $darkBackColor
$tabGeneral.Controls.Add($buttonPanel)

# Apply Button
$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = "Apply"
$applyButton.Size = New-Object System.Drawing.Size(120, 30)
$applyButton.Location = New-Object System.Drawing.Point(510, 10)
$applyButton.Enabled = $false
$applyButton.BackColor = $accentColor
$applyButton.ForeColor = [System.Drawing.Color]::White
$buttonPanel.Controls.Add($applyButton)

# Restart Explorer Button
$restartButton = New-Object System.Windows.Forms.Button
$restartButton.Text = "Restart Explorer"
$restartButton.Size = New-Object System.Drawing.Size(150, 30)
$restartButton.Location = New-Object System.Drawing.Point(340, 10)
$restartButton.Visible = $false
$restartButton.BackColor = $accentColor
$restartButton.ForeColor = [System.Drawing.Color]::White
$buttonPanel.Controls.Add($restartButton)

# Reset Defaults Button
$resetButton = New-Object System.Windows.Forms.Button
$resetButton.Text = "Reset to Default"
$resetButton.Size = New-Object System.Drawing.Size(180, 30)
$resetButton.Location = New-Object System.Drawing.Point(10, 10)
$resetButton.BackColor = $accentColor
$resetButton.ForeColor = [System.Drawing.Color]::White
$buttonPanel.Controls.Add($resetButton)

# Checkbox list for tweaks (populated later)
$checkboxes = @()

# Fill TreeView with categories and tweaks
foreach ($category in $tweakCategories) {
    $nodeCat = New-Object System.Windows.Forms.TreeNode $category.Category
    $nodeCat.ForeColor = $accentColor
    foreach ($tweak in $category.Tweaks) {
        $nodeTweak = New-Object System.Windows.Forms.TreeNode $tweak.Label
        $nodeTweak.Checked = $false
        $nodeTweak.Tag = $tweak
        $nodeCat.Nodes.Add($nodeTweak) | Out-Null
        $checkboxes += $nodeTweak
    }
    $treeView.Nodes.Add($nodeCat) | Out-Null
}

Set-FontSizeRecursive -control $tabGeneral -fontSize 11

#endregion

#region General Tab - Event Handlers & Functions

# Function to update button states (Apply and Restart Explorer)
function UpdateButtons {
    $applyButton.Enabled = $global:hasChanges
    $restartButton.Visible = $global:restartNeeded
}

# Function to synchronize tweak states (from registry to checkboxes)
function Sync-TweakStates {
    $hasChangesLocal = $false
    $restartNeededLocal = $false
    foreach ($node in $checkboxes) {
        $tweak = $node.Tag
        try {
            $currentState = & $tweak.GetState
        }
        catch {
            $currentState = $false
        }
        $node.Checked = $currentState

        if ($node.Checked -ne $tweak.Default) {
            $hasChangesLocal = $true
            if ($tweak.RestartNeeded) { $restartNeededLocal = $true }
        }
    }
    $global:hasChanges = $hasChangesLocal
    $global:restartNeeded = $restartNeededLocal
    UpdateButtons
    if (-not $hasChangesLocal) {
        $statusLabel.Text = "Status: All settings are at default."
    }
    else {
        $statusLabel.Text = "Status: Changes detected, please apply."
    }
}

# TreeView AfterCheck event - sync child nodes and update parent states
$treeView.Add_AfterCheck({
        param($sender, $e)

        if ($global:IgnoreCheckEvent) { return }
        $global:IgnoreCheckEvent = $true

        if ($e.Node.Tag -eq $null) {
            # It's a category node
            foreach ($child in $e.Node.Nodes) {
                $child.Checked = $e.Node.Checked
            }
        }
        else {
            # It's a tweak node
            $parent = $e.Node.Parent
            if ($parent -ne $null) {
                $allChecked = $true
                $allUnchecked = $true
                foreach ($child in $parent.Nodes) {
                    if ($child.Checked) { $allUnchecked = $false } else { $allChecked = $false }
                }
                if ($allChecked) {
                    $parent.Checked = $true
                    $parent.StateImageIndex = -1 # No mixed state icon
                }
                elseif ($allUnchecked) {
                    $parent.Checked = $false
                    $parent.StateImageIndex = -1 # No mixed state icon
                }
                else {
                    $parent.Checked = $false # Parent checkbox remains unchecked for mixed state
                }
            }
        }

        $global:hasChanges = $true

        $restartNeededLocal = $false
        foreach ($node in $checkboxes) {
            if ($node.Checked -ne $node.Tag.Default -and $node.Tag.RestartNeeded) {
                $restartNeededLocal = $true
                break
            }
        }
        $global:restartNeeded = $restartNeededLocal

        $statusLabel.Text = "Status: Changes not applied yet."
        UpdateButtons

        $global:IgnoreCheckEvent = $false
    })

# Apply button click
$applyButton.Add_Click({
        try {
            $statusLabel.Text = "Status: Applying tweaks..."
            $progressBar.Visible = $true
            $progressBar.Minimum = 0
            $progressBar.Maximum = $checkboxes.Count
            $progressBar.Value = 0
            $form.Refresh()

            for ($i = 0; $i -lt $checkboxes.Count; $i++) {
                $node = $checkboxes[$i]
                $tweak = $node.Tag
                if ($node.Checked) {
                    & $tweak.Enable
                }
                else {
                    & $tweak.Disable
                }
                $progressBar.Value = $i + 1
                $form.Refresh()
            }

            $progressBar.Visible = $false
            Sync-TweakStates
            $statusLabel.Text = "Status: Tweaks applied."
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("An error occurred while applying tweaks: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            $progressBar.Visible = $false
        }
    })

# Restart Explorer button click
$restartButton.Add_Click({
        Restart-Explorer
        $restartButton.Visible = $false
        $statusLabel.Text = "Status: Explorer restarted."
    })

# Reset button click
$resetButton.Add_Click({
        foreach ($node in $checkboxes) {
            $node.Checked = $node.Tag.Default
        }
        $statusLabel.Text = "Status: Reset to default."
        $global:hasChanges = $true # Mark as changed to enable Apply button
        UpdateButtons
    })

# Initial sync of tweak states on form load
$form.Add_Shown({
        Sync-TweakStates
    })

#endregion

#endregion

#region 6. Tab: Advanced (Empty for now)

$tabAdvanced = New-Object System.Windows.Forms.TabPage "Advanced"
$tabAdvanced.BackColor = $darkBackColor
$tabAdvanced.ForeColor = $darkForeColor
$tabControl.TabPages.Add($tabAdvanced)

# Example Label in Advanced Tab
$advancedLabel = New-Object System.Windows.Forms.Label
$advancedLabel.Text = "Advanced tweaks use only if you know what your doing."
$advancedLabel.AutoSize = $true
$advancedLabel.Location = New-Object System.Drawing.Point(15, 15)
$advancedLabel.ForeColor = $darkForeColor
$tabAdvanced.Controls.Add($advancedLabel)

Set-FontSizeRecursive -control $tabAdvanced -fontSize 11

#endregion

#region 7. Tab: Downloads

$tabDownloads = New-Object System.Windows.Forms.TabPage "Downloads"
$tabDownloads.BackColor = $darkBackColor
$tabDownloads.ForeColor = $darkForeColor
$tabControl.TabPages.Add($tabDownloads)

#region Downloads Tab - Program Data

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

#region Downloads Tab - Winget Installation/Check

# Check/Auto install winget
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

#endregion

#region Downloads Tab - Winget Related Functions

# Function to update the list of installed Winget packages
function Update-InstalledPackageIds {
    param(
        [System.Windows.Forms.Form]$parentForm,
        [System.Windows.Forms.ProgressBar]$progressBar,
        [System.Windows.Forms.Label]$statusLabel
    )

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

# Function to test if a Winget package is installed
function Test-WingetPackageInstalled {
    param([string]$packageId)
    return $global:installedPackageIds.ContainsKey($packageId)
}

# Function to update the visual status of programs in the TreeView
function Update-InstalledProgramsStatus {
    Update-InstalledPackageIds -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel

    foreach ($node in $allProgramNodes) {
        $pkgId = $node.Tag
        if (Test-WingetPackageInstalled -packageId $pkgId) {
            $node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
            $node.ForeColor = [System.Drawing.Color]::Green
        }
        else {
            $node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Regular)
            $node.ForeColor = $darkForeColor
        }
    }
}

# Function to get selected installation status
function Get-SelectedInstallStatus {
    $selected = $allProgramNodes | Where-Object { $_.Checked }
    $installed = @()
    $notInstalled = @()

    foreach ($node in $selected) {
        if (Test-WingetPackageInstalled -packageId $node.Tag) { $installed += $node }
        else { $notInstalled += $node }
    }
    return [PSCustomObject]@{
        Installed    = $installed
        NotInstalled = $notInstalled
        AllSelected  = $selected
    }
}

# Function to install/update programs via winget
function Install-WingetProgram {
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

# Function to install or update selected nodes
function Install-OrUpdate {
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

# Function to uninstall programs
function Uninstall-Programs {
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

#region Downloads Tab - GUI Elements

# Label top
$downloadsLabel = New-Object System.Windows.Forms.Label
$downloadsLabel.Text = "Select the programs to install via winget:"
$downloadsLabel.AutoSize = $true
$downloadsLabel.Location = New-Object System.Drawing.Point(15, 15)
$downloadsLabel.ForeColor = $darkForeColor
$tabDownloads.Controls.Add($downloadsLabel)

# TreeView with Checkboxes and Categories
$downloadTreeView = New-Object System.Windows.Forms.TreeView
$downloadTreeView.Size = New-Object System.Drawing.Size(650, 600)
$downloadTreeView.Location = New-Object System.Drawing.Point(15, 50)
$downloadTreeView.BackColor = $darkBackColor
$downloadTreeView.ForeColor = $darkForeColor
$downloadTreeView.HideSelection = $false
$downloadTreeView.CheckBoxes = $true
$tabDownloads.Controls.Add($downloadTreeView)

# List to hold all program nodes for status checks
$allProgramNodes = @()

# Populate TreeView with categories and programs
foreach ($category in $programCategories.Keys) {
    $parentNode = New-Object System.Windows.Forms.TreeNode $category
    $parentNode.ForeColor = $accentColor

    foreach ($prog in $programCategories[$category]) {
        $childNode = New-Object System.Windows.Forms.TreeNode $prog.Name
        $childNode.Tag = $prog.Id

        # Highlight installed programs (bold + green)
        if (Test-WingetPackageInstalled -packageId $prog.Id) {
            $childNode.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
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
$installButton.BackColor = $accentColor
$installButton.ForeColor = [System.Drawing.Color]::Lime
$installButton.Enabled = $false
$tabDownloads.Controls.Add($installButton)

# Uninstall Button
$uninstallButton = New-Object System.Windows.Forms.Button
$uninstallButton.Text = "Uninstall"
$uninstallButton.Size = New-Object System.Drawing.Size(100, 30)
$uninstallButton.Location = New-Object System.Drawing.Point(245, 660)
$uninstallButton.BackColor = $accentColor
$uninstallButton.ForeColor = [System.Drawing.Color]::Red
$uninstallButton.Enabled = $false
$tabDownloads.Controls.Add($uninstallButton)

# Update Button
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = "Update all"
$updateButton.Size = New-Object System.Drawing.Size(100, 30)
$updateButton.Location = New-Object System.Drawing.Point(130, 660)
$updateButton.BackColor = $accentColor
$updateButton.ForeColor = [System.Drawing.Color]::Lime
$updateButton.Enabled = $true
$tabDownloads.Controls.Add($updateButton)

# Uncheck All Button
$uncheckAllButton = New-Object System.Windows.Forms.Button
$uncheckAllButton.Text = "Uncheck all"
$uncheckAllButton.Size = New-Object System.Drawing.Size(100, 30)
$uncheckAllButton.Location = New-Object System.Drawing.Point(360, 660)
$uncheckAllButton.BackColor = $accentColor
$uncheckAllButton.ForeColor = [System.Drawing.Color]::White
$tabDownloads.Controls.Add($uncheckAllButton)

# Status Label
$statusDownloadLabel = New-Object System.Windows.Forms.Label
$statusDownloadLabel.Size = New-Object System.Drawing.Size(600, 30)
$statusDownloadLabel.Location = New-Object System.Drawing.Point(15, 700)
$statusDownloadLabel.ForeColor = $darkForeColor
$tabDownloads.Controls.Add($statusDownloadLabel)

# Progress Bar
$downloadProgressBar = New-Object System.Windows.Forms.ProgressBar
$downloadProgressBar.Size = New-Object System.Drawing.Size(600, 20)
$downloadProgressBar.Location = New-Object System.Drawing.Point(15, 730)
$downloadProgressBar.Visible = $false
$tabDownloads.Controls.Add($downloadProgressBar)

Set-FontSizeRecursive -control $tabDownloads -fontSize 11

#endregion

#region Downloads Tab - Event Handlers

# TreeView AfterCheck event
$downloadTreeView.Add_AfterCheck({
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

# Initial load for Downloads tab
$form.Add_Shown({
        # Only run this once, when the form is shown (e.g., after initial GUI setup)
        # Check if this has already been run to prevent re-execution on every tab switch if not desired
        if (-not $script:downloadsTabInitialized) {
            $statusDownloadLabel.Text = "Status: Initializing Winget data..."
            $downloadProgressBar.Visible = $true
            $downloadProgressBar.Style = 'Marquee'
            $form.Refresh()
            Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
            $script:downloadsTabInitialized = $true
        }
    })

#endregion

#endregion

#region 8. Tab: Untested

$tabUntested = New-Object System.Windows.Forms.TabPage "Untested"
$tabUntested.BackColor = $darkBackColor
$tabUntested.ForeColor = $darkForeColor
$tabControl.TabPages.Add($tabUntested)

# Example Label in Untested Tab
$untestedLabel = New-Object System.Windows.Forms.Label
$untestedLabel.Text = "These tweaks are untested and experimental."
$untestedLabel.AutoSize = $true
$untestedLabel.Location = New-Object System.Drawing.Point(15, 15)
$untestedLabel.ForeColor = $darkForeColor
$tabUntested.Controls.Add($untestedLabel)

Set-FontSizeRecursive -control $tabUntested -fontSize 11

#endregion

#region 9. Final Execution

# Initial calls for Home tab info
$form.Add_Shown({
        Get-AndDisplayAllSystemInfo
    })

# Show form
[void] $form.ShowDialog()

#endregion