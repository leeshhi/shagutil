Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptVersion = "0.0.3"

# Admin Check
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole] "Administrator")) {
    # GEÄNDERT: Nachricht und Icon der MessageBox
    [System.Windows.Forms.MessageBox]::Show("Dieses Skript muss als Administrator ausgeführt werden. Bitte starten Sie PowerShell oder die Skriptdatei erneut mit Administratorrechten.", "Administratorrechte erforderlich", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Stop)
    exit
}

# Welcome Message (NEU HINZUGEFÜGT)
Write-Host "██╗    ██╗ ██████╗ ██╗  ██╗██████╗  ██████╗ ███████╗ ██████╗████████╗" -ForegroundColor Cyan
Write-Host "██║    ██║██╔═══██╗██║  ██║██╔══██╗██╔═══██╗██╔════╝██╔════╝╚══██╔══╝" -ForegroundColor Cyan
Write-Host "██║ █╗ ██║██║   ██║███████║██████╔╝██║   ██║█████╗  ██║        ██║   " -ForegroundColor Cyan
Write-Host "██║███╗██║██║   ██║██╔══██║██╔══██╗██║   ██║██╔══╝  ██║        ██║   " -ForegroundColor Cyan
Write-Host "╚███╔███╔╝╚██████╔╝██║  ██║██║  ██║╚██████╔╝███████╗╚██████╗   ██║   " -ForegroundColor Cyan
Write-Host " ╚══╝╚══╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝ ╚═════╝   ╚═╝   " -ForegroundColor Cyan
Write-Host ""
Write-Host "*********************************************" -ForegroundColor Green
Write-Host "* Welcome to WinBoost v$scriptVersion!        *" -ForegroundColor Green
Write-Host "* Optimizing your Windows experience.      *" -ForegroundColor Green
Write-Host "* *" -ForegroundColor Green
Write-Host "* Script by leeshhi (shag.gg)              *" -ForegroundColor Green
Write-Host "*********************************************" -ForegroundColor Green
Write-Host ""

# Funktion: Schriftgröße rekursiv auf alle Controls in einem Control setzen
function Set-FontSizeRecursive {
    param([System.Windows.Forms.Control]$control, [float]$fontSize)

    # Neue Font mit gleicher Familie und Stil, nur Größe geändert
    $newFont = New-Object System.Drawing.Font($control.Font.FontFamily, $fontSize, $control.Font.Style)
    $control.Font = $newFont

    foreach ($child in $control.Controls) {
        Set-FontSizeRecursive -control $child -fontSize $fontSize
    }
}

# --- FUNKTION FÜR UPDATE CHECK ---
function Check-ForUpdates {
    param(
        [string]$currentVersion = $scriptVersion, # Nimmt die aktuelle Skriptversion an
        [string]$githubRawUrl = "https://raw.githubusercontent.com/leeshhi/winboost/main/version.txt" # Deine GitHub Raw URL
    )

    try {
        # Remote-Versionsdatei von GitHub abrufen
        $remoteVersionText = Invoke-RestMethod -Uri $githubRawUrl -ErrorAction Stop
        $remoteVersion = $remoteVersionText.Trim() # Leerzeichen entfernen

        # Versionen vergleichen
        $currentVersionObject = [Version]$currentVersion
        $remoteVersionObject = [Version]$remoteVersion

        if ($remoteVersionObject -gt $currentVersionObject) {
            # Neuere Version verfügbar: Gib Details zurück
            return @{
                UpdateAvailable = $true;
                RemoteVersion   = $remoteVersion;
                CurrentVersion  = $currentVersion;
                RepoLink        = "https://github.com/leeshhi/winboost" # Dein Repository-Link
            }
        } else {
            # Keine neuere Version
            return @{ UpdateAvailable = $false }
        }
    }
    catch {
        # Fehler beim Abrufen der Updates: Gib den Fehler zurück
        return @{
            UpdateAvailable = $false;
            Error           = $_.Exception.Message
        }
    }
}
# --- END FUNKTION FÜR UPDATE CHECK ---

function Get-OsInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    "OS: $($os.Caption) Version $($os.Version) (Build $($os.BuildNumber))"
}

function Get-CpuInfo {
    $cpu = Get-CimInstance Win32_Processor
    "CPU: $($cpu.Name) ($($cpu.NumberOfCores) Cores, $($cpu.NumberOfLogicalProcessors) Threads)"
}

function Get-RamInfo {
    $os = Get-CimInstance Win32_OperatingSystem # FreePhysicalMemory ist in KB
    $ram = Get-CimInstance Win32_ComputerSystem # TotalPhysicalMemory ist in Byte

    $totalMemoryGB = [Math]::Round(($ram.TotalPhysicalMemory / 1GB), 2)
    # Korrektur: FreePhysicalMemory ist in KB, Umrechnung in GB
    $freeMemoryGB = [Math]::Round(($os.FreePhysicalMemory / (1024 * 1024)), 2)
    
    "RAM: ${totalMemoryGB}GB Total / ${freeMemoryGB}GB Available"
}

function Get-GpuInfo {
    $gpus = Get-CimInstance Win32_VideoController | Select-Object Name
    $gpuStrings = @()
    foreach ($gpu in $gpus) {
        # Zeigt nur noch den Namen an, da RAM-Info Probleme bereitet hat
        $gpuStrings += "$($gpu.Name)"
    }
    # Sicherstellen, dass "GPU: " nur einmal angezeigt wird, auch wenn mehrere GPUs vorhanden sind
    if ($gpuStrings.Count -gt 0) {
        "GPU: " + ($gpuStrings -join ", ")
    } else {
        "GPU: Not found"
    }
}

function Get-MotherboardInfo {
    $board = Get-CimInstance Win32_BaseBoard
    "Mainboard: $($board.Manufacturer) $($board.Product)"
}

function Get-BiosInfo {
    $bios = Get-CimInstance Win32_BIOS
    "BIOS: $($bios.Caption) Version $($bios.SMBIOSBIOSVersion) (Date: $($bios.ReleaseDate))"
}

function Get-NetworkInfo {
    $computerName = $env:COMPUTERNAME
    # Ping-Test entfernt, wie gewünscht, um den Start zu beschleunigen
    # Public IP wurde bereits vorher entfernt
    
    "Gerätename: $computerName" # Nur noch Gerätename
}

# Hauptfunktion zum Abrufen und Anzeigen aller Systeminformationen
function Get-AndDisplayAllSystemInfo {
    $yPos = 40 # Startposition Y für Labels

    # Funktionen aufrufen und Labels erstellen
    $systemInfoLabels = @(
        (Get-OsInfo),
        (Get-CpuInfo),
        (Get-RamInfo),
        (Get-GpuInfo),
        (Get-MotherboardInfo),
        (Get-BiosInfo),
        (Get-NetworkInfo) # NetworkInfo gibt ein Array zurück
    )

    foreach ($line in $systemInfoLabels) {
        # Wenn $line ein Array ist (wie bei Get-NetworkInfo), jedes Element einzeln verarbeiten
        if ($line -is [array]) {
            foreach ($subLine in $line) {
                $label = New-Object System.Windows.Forms.Label
                $label.Text = $subLine
                $label.AutoSize = $true
                $label.Location = New-Object System.Drawing.Point(10, $yPos)
                $systemInfoPanel.Controls.Add($label)
                $yPos += 25
            }
        } else {
            $label = New-Object System.Windows.Forms.Label
            $label.Text = $line
            $label.AutoSize = $true
            $label.Location = New-Object System.Drawing.Point(10, $yPos)
            $systemInfoPanel.Controls.Add($label)
            $yPos += 25
        }
    }
}

# --- Tweaks grouped by categories ---
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

function Restart-Explorer {
    Get-Process explorer | Stop-Process -Force
    Start-Sleep -Seconds 1
    Start-Process explorer.exe
}

# Colors
$darkBackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$darkForeColor = [System.Drawing.Color]::White
$footerBackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
$accentColor = [System.Drawing.Color]::FromArgb(0, 122, 204)

# Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "Windows Tweaks Tool by leeshhi (shag.gg) - Comparison"
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

# OwnerDraw aktivieren für individuelle Tab-Text-Farbe
$tabControl.DrawMode = [System.Windows.Forms.TabDrawMode]::OwnerDrawFixed

# DrawItem Event für individuelle Tab-Text-Farbe
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

        # Hole Rechteck für aktuellen Tab
        $rect = $sender.GetTabRect($e.Index)

        # Falls $rect ein Array ist, erstes Element nehmen
        if ($rect -is [System.Array]) {
            $rect = $rect[0]
        }

        # Hintergrund malen
        $e.Graphics.FillRectangle([System.Drawing.Brushes]::LightGray, $rect)

        # StringFormat zentriert
        $sf = New-Object System.Drawing.StringFormat
        $sf.Alignment = [System.Drawing.StringAlignment]::Center
        $sf.LineAlignment = [System.Drawing.StringAlignment]::Center

        # Mitte des Rechtecks als PointF
        $pointX = [float]($rect.X) + ([float]($rect.Width) / 2)
        $pointY = [float]($rect.Y) + ([float]($rect.Height) / 2)
        $point = New-Object System.Drawing.PointF($pointX, $pointY)

        # Text zeichnen
        $brush = New-Object System.Drawing.SolidBrush($color)
        $e.Graphics.DrawString($text, $font, $brush, $point, $sf)
        $brush.Dispose()
    })

$form.Controls.Add($tabControl)


$form.Add_Load({
    # Führe den Update-Check aus
    $updateInfo = Check-ForUpdates

    # Zeige die MessageBox basierend auf dem Ergebnis an
    if ($updateInfo.UpdateAvailable) {
        # GEÄNDERT: Statt MessageBox, eine Konsolennachricht bei verfügbarem Update
        Write-Host ">>> UPDATE VERFÜGBAR! <<<" -ForegroundColor Yellow -BackgroundColor Red
        Write-Host "Eine neue Version ($($updateInfo.RemoteVersion)) ist verfügbar!" -ForegroundColor Yellow
        Write-Host "Deine aktuelle Version ist $($updateInfo.CurrentVersion)." -ForegroundColor Yellow
        Write-Host "Bitte aktualisiere dein Tool über den GitHub Link: $($updateInfo.RepoLink)" -ForegroundColor Yellow # RepoLink wird von Check-ForUpdates zurückgegeben
        Write-Host "Führe den Startbefehl erneut aus, um die neue Version zu nutzen." -ForegroundColor Yellow
        Write-Host "*********************************************" -ForegroundColor Yellow
        Write-Host ""
    } elseif ($updateInfo.Error) {
        # Zeige Fehler an, falls beim Update-Check etwas schief ging (Diese MessageBox bleibt)
        [System.Windows.Forms.MessageBox]::Show(
            "Fehler beim Überprüfen auf Updates: $($updateInfo.Error)",
            "Update-Fehler",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        )
    }
})

# Tab 1: Home

$tabHome = New-Object System.Windows.Forms.TabPage "Home"
$tabHome.BackColor = $darkBackColor
$tabHome.ForeColor = $darkForeColor
$tabControl.TabPages.Add($tabHome)

# Panel für Systeminformationen (oben links)
$systemInfoPanel = New-Object System.Windows.Forms.Panel
$systemInfoPanel.Size = New-Object System.Drawing.Size(550, 400)
$systemInfoPanel.Location = New-Object System.Drawing.Point(10, 10)
$systemInfoPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabHome.Controls.Add($systemInfoPanel)

# Titel für Systeminformationen im Panel
$systemInfoTitle = New-Object System.Windows.Forms.Label
$systemInfoTitle.Text = "System Information"
$systemInfoTitle.Font = New-Object System.Drawing.Font($systemInfoTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
$systemInfoTitle.AutoSize = $true
$systemInfoTitle.Location = New-Object System.Drawing.Point(10, 10)
$systemInfoPanel.Controls.Add($systemInfoTitle)

# Panel für Quick Links (direkt unter Systeminformationen)
$quickLinksPanel = New-Object System.Windows.Forms.Panel
$quickLinksPanel.Size = New-Object System.Drawing.Size(200, 200)
$quickLinksPanel.Location = New-Object System.Drawing.Point(10, ($systemInfoPanel.Location.Y + $systemInfoPanel.Size.Height + 20)) # 20px Abstand
$quickLinksPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabHome.Controls.Add($quickLinksPanel)

# Titel für Quick Links
$quickLinksTitle = New-Object System.Windows.Forms.Label
$quickLinksTitle.Text = "Quick Links"
$quickLinksTitle.Font = New-Object System.Drawing.Font($quickLinksTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
$quickLinksTitle.AutoSize = $true
$quickLinksTitle.Location = New-Object System.Drawing.Point(10, 10)
$quickLinksPanel.Controls.Add($quickLinksTitle)

# Quick Links Buttons
$buttonYPos = 40
$quickLinks = @(
    @{"Text"="Task-Manager"; "Action"={ Start-Process taskmgr.exe }},
    @{"Text"="Geräte-Manager"; "Action"={ Start-Process devmgmt.msc }},
    @{"Text"="Systemsteuerung"; "Action"={ Start-Process control.exe }},
    @{"Text"="Datenträgerverwaltung"; "Action"={ Start-Process diskmgmt.msc }}
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

# --- NEU: Panel für Kontaktinformationen (rechts neben Quick Links) ---
$contactPanel = New-Object System.Windows.Forms.Panel
$contactPanel.Size = New-Object System.Drawing.Size(200, 200) # Gleiche Größe wie Quick Links Panel
# Position: Rechts vom QuickLinksPanel, oben ausgerichtet mit QuickLinksPanel
$contactPanel.Location = New-Object System.Drawing.Point(($quickLinksPanel.Location.X + $quickLinksPanel.Size.Width + 20), $quickLinksPanel.Location.Y)
$contactPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$tabHome.Controls.Add($contactPanel)

# Titel für Kontakt
$contactTitle = New-Object System.Windows.Forms.Label
$contactTitle.Text = "Connect with me"
$contactTitle.Font = New-Object System.Drawing.Font($contactTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
$contactTitle.AutoSize = $true
$contactTitle.Location = New-Object System.Drawing.Point(10, 10)
$contactPanel.Controls.Add($contactTitle)

# Kontaktinformationen (Beispiel mit LinkLabels)
$contactYPos = 40

# Website Link
$websiteLink = New-Object System.Windows.Forms.LinkLabel
$websiteLink.Text = "Website"
$websiteLink.AutoSize = $true
$websiteLink.Location = New-Object System.Drawing.Point(10, $contactYPos)
$websiteLink.Add_LinkClicked({ Start-Process "https://shag.gg" })
$contactPanel.Controls.Add($websiteLink)
$contactYPos += 25

# GitHub Link
$githubLink = New-Object System.Windows.Forms.LinkLabel
$githubLink.Text = "GitHub"
$githubLink.AutoSize = $true
$githubLink.Location = New-Object System.Drawing.Point(10, $contactYPos)
$githubLink.Add_LinkClicked({ Start-Process "https://github.com/leeshhi" })
$contactPanel.Controls.Add($githubLink)
$contactYPos += 25

# Discord Link
$discordLink = New-Object System.Windows.Forms.LinkLabel
$discordLink.Text = "Discord"
$discordLink.AutoSize = $true
$discordLink.Location = New-Object System.Drawing.Point(10, $contactYPos)
$discordLink.Add_LinkClicked({ Start-Process "https://discord.gg/gDmjYgydb3" })
$contactPanel.Controls.Add($discordLink)
$contactYPos += 25

# Discord2 Link
$discord2Link = New-Object System.Windows.Forms.LinkLabel
$discord2Link.Text = "Discord (Shag.gg)"
$discord2Link.AutoSize = $true
$discord2Link.Location = New-Object System.Drawing.Point(10, $contactYPos)
$discord2Link.Add_LinkClicked({ Start-Process "https://discord.gg/qxPNcgtTqn" })
$contactPanel.Controls.Add($discord2Link)
$contactYPos += 25

# Wichtig: Schriftgröße für den Home Tab und seine Controls setzen
Set-FontSizeRecursive -control $tabHome -fontSize 11



# Tab 2: General

$tabTree = New-Object System.Windows.Forms.TabPage "General"
$tabTree.BackColor = $darkBackColor
$tabTree.ForeColor = $darkForeColor
$tabControl.TabPages.Add($tabTree)

$treeView = New-Object System.Windows.Forms.TreeView
$treeView.Size = New-Object System.Drawing.Size(650, 600)
$treeView.Location = New-Object System.Drawing.Point(15, 15)
$treeView.BackColor = $darkBackColor
$treeView.ForeColor = $darkForeColor
$treeView.HideSelection = $false
$treeView.CheckBoxes = $true
$tabTree.Controls.Add($treeView)

# Status Label (Footer)
$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Size = New-Object System.Drawing.Size(650, 30)
$statusLabel.Location = New-Object System.Drawing.Point(15, 620)
$statusLabel.TextAlign = 'MiddleLeft'
$statusLabel.Text = "Status: Ready"
$statusLabel.ForeColor = $darkForeColor
$statusLabel.BackColor = $footerBackColor
$tabTree.Controls.Add($statusLabel)

# Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Size = New-Object System.Drawing.Size(650, 20)
$progressBar.Location = New-Object System.Drawing.Point(15, 655)
$progressBar.Visible = $false
$tabTree.Controls.Add($progressBar)

# Buttons Panel
$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Size = New-Object System.Drawing.Size(650, 50)
$buttonPanel.Location = New-Object System.Drawing.Point(15, 685)
$buttonPanel.BackColor = $darkBackColor
$tabTree.Controls.Add($buttonPanel)

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

# Checkbox list for tweaks
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

# Set font size in $tabTree and all its controls (Schriftgröße auf 12)
Set-FontSizeRecursive -control $tabTree -fontSize 11

# Tab 3: Advanced (empty for now)

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

# Set font size in $tabAdvanced and all its controls
Set-FontSizeRecursive -control $tabAdvanced -fontSize 11

# (You can add controls to $tabAdvanced later...)

# Tab 4: Downloads

$tabDownloads = New-Object System.Windows.Forms.TabPage "Downloads"
$tabDownloads.BackColor = $darkBackColor
$tabDownloads.ForeColor = $darkForeColor
$tabControl.TabPages.Add($tabDownloads)

# Label oben
$downloadsLabel = New-Object System.Windows.Forms.Label
$downloadsLabel.Text = "Select the programs to install via winget:"
$downloadsLabel.AutoSize = $true
$downloadsLabel.Location = New-Object System.Drawing.Point(15, 15)
$downloadsLabel.ForeColor = $darkForeColor
$tabDownloads.Controls.Add($downloadsLabel)

# Kategorien mit Programmen (Name + winget ID)
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

# Check/Auto install winget =
# MS Store: App Installer > 9NBLGGH4NNS1
# github.com/microsoft/winget-cli/releases/latest
# ==> Bevorzugt: MS Store variante, da es komplett nativ gemacht werden kann ohne extra downloads und temp files

# Check/Auto install winget
# MS Store: App Installer > 9NBLGGH4NNS1 (Package Family Name: Microsoft.DesktopAppInstaller_8wekyb3d8bbwe)
# github.com/microsoft/winget-cli/releases/latest
# ==> Bevorzugt: MS Store variante, da es komplett nativ gemacht werden kann ohne extra downloads und temp files

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    [System.Windows.Forms.MessageBox]::Show("winget wurde nicht gefunden. Es wird versucht, den App Installer (mit winget) aus dem Microsoft Store zu installieren.", "winget nicht gefunden", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

    try {
        # Pfad zur PowerShell-Executable
        $powershellPath = Join-Path $PSHOME "powershell.exe"

        # Kommando, um den App Installer zu starten und ggf. zu installieren
        # Hier nutzen wir den ms-windows-store URI, um die Store-Seite des App Installers zu öffnen.
        # Der Benutzer muss dann im Store auf "Installieren" klicken.
        $process = Start-Process -FilePath "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1" -PassThru -NoNewWindow -ErrorAction Stop

        # Warten, bis der Store-Prozess beendet wird, oder eine gewisse Zeit abwarten
        # Es ist schwierig, die Installation im Store zu automatisieren, daher ist Benutzerinteraktion nötig.
        [System.Windows.Forms.MessageBox]::Show("Bitte installieren Sie den 'App Installer' (Paket-ID: 9NBLGGH4NNS1) aus dem sich öffnenden Microsoft Store Fenster. Klicken Sie dann auf 'OK' hier, wenn die Installation abgeschlossen ist.", "Installation von winget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

        # Nach der Installation erneut prüfen
        Start-Sleep -Seconds 5 # Gib dem System etwas Zeit, winget nach der Installation zu registrieren
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
            [System.Windows.Forms.MessageBox]::Show("winget konnte nach der Installation nicht gefunden werden. Bitte starten Sie das Skript neu oder stellen Sie sicher, dass winget korrekt installiert ist.", "Fehler bei winget", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            exit
        }
        else {
            [System.Windows.Forms.MessageBox]::Show("winget wurde erfolgreich erkannt. Das Skript wird fortgesetzt.", "winget gefunden", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Ein Fehler ist beim Versuch aufgetreten, den Microsoft Store für die winget-Installation zu öffnen: $_. Bitte installieren Sie winget manuell.", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        exit
    }
}


$global:installedPackageIds = @{}

# Funktion zum Aktualisieren der Liste der installierten Winget-Pakete (für Windows PowerShell 5.1)
function Update-InstalledPackageIds {
    param(
        [System.Windows.Forms.Form]$parentForm,
        [System.Windows.Forms.ProgressBar]$progressBar,
        [System.Windows.Forms.Label]$statusLabel
    )

    $progressBar.Style = 'Marquee'
    $progressBar.Visible = $true
    $statusLabel.Text = "Lade installierte Winget-Pakete (kann dauern)..."
    $parentForm.Refresh() # GUI aktualisieren

    $global:installedPackageIds.Clear() # Bestehende Liste leeren
    $output = ""
    $errors = ""

    try {
        $statusDownloadLabel.Text = "Status: Lade installierte Winget-Pakete (kann dauern)..."
        $progressBar.Style = 'Marquee'
        $progressBar.Visible = $true
        $parentForm.Refresh()

        $wingetResult = Invoke-WingetCommand -arguments "list --source winget" -timeoutSeconds 60

        if ($wingetResult.TimedOut) {
            [System.Windows.Forms.MessageBox]::Show($wingetResult.Errors, "Winget-Zeitüberschreitung", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            $statusLabel.Text = "Status: Laden fehlgeschlagen (Timeout)."
            return
        }

        if ($wingetResult.ExitCode -ne 0) {
            $errorMessage = "Winget 'list' Befehl ist mit Fehlercode $($wingetResult.ExitCode) beendet. "
            if (![string]::IsNullOrEmpty($wingetResult.Errors)) {
                $errorMessage += "Fehler: $($wingetResult.Errors)."
            }
            $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
            [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget-Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            $statusLabel.Text = "Status: Laden fehlgeschlagen."
            return
        }
        
        if ([string]::IsNullOrEmpty($wingetResult.Output)) {
            [System.Windows.Forms.MessageBox]::Show("Winget 'list' Befehl lieferte keine Ausgabe. Möglicherweise ein Konfigurationsproblem.", "Winget-Warnung", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
            $statusLabel.Text = "Status: Laden fehlgeschlagen."
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
        $statusLabel.Text = "Status: Winget-Pakete geladen."
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("Ein unerwarteter Fehler beim Abrufen der Winget-Paketliste: $_", "Winget-Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        $statusLabel.Text = "Status: Laden fehlgeschlagen."
    }
    finally {
        $progressBar.Visible = $false
        $progressBar.Style = 'Blocks'
        $parentForm.Refresh()
    }
}

function Test-WingetPackageInstalled {
    param([string]$packageId)
    # Prüft direkt in der Hashtable, ob die Paket-ID vorhanden ist
    return $global:installedPackageIds.ContainsKey($packageId)
}

function Update-InstalledProgramsStatus {
    # Ruft die optimierte Funktion zum Aktualisieren der internen Winget-Liste auf
    Update-InstalledPackageIds -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel

    # Tree aktualisieren
    foreach ($node in $allProgramNodes) {
        $pkgId = $node.Tag
        if (Test-WingetPackageInstalled -packageId $pkgId) {
            $node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
            $node.ForeColor = [System.Drawing.Color]::Green
            # Wenn bereits ausgewählt, aber jetzt installiert, trotzdem grüne Farbe beibehalten
            if ($node.Checked) {
                # Keine Änderung, bleibt gecheckt und fett/grün
            }
        }
        else {
            $node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Regular)
            $node.ForeColor = $darkForeColor
            # Wenn nicht mehr installiert und gecheckt war, unchecken (Optional, aber logisch)
            # $node.Checked = $false
        }
    }
    # Da Update-InstalledPackageIds den Status bereits auf "Bereit" setzt, hier keine zusätzliche Statusmeldung
}

# TreeView mit Checkboxen und Kategorien
$downloadTreeView = New-Object System.Windows.Forms.TreeView
$downloadTreeView.Size = New-Object System.Drawing.Size(650, 600)
$downloadTreeView.Location = New-Object System.Drawing.Point(15, 50)
$downloadTreeView.BackColor = $darkBackColor
$downloadTreeView.ForeColor = $darkForeColor
$downloadTreeView.HideSelection = $false
$downloadTreeView.CheckBoxes = $true
$tabDownloads.Controls.Add($downloadTreeView)

# Liste aller Programm-Knoten für Statusprüfung
$allProgramNodes = @()

# Kategorien als Parent-Nodes hinzufügen
foreach ($category in $programCategories.Keys) {
    $parentNode = New-Object System.Windows.Forms.TreeNode $category
    #$parentNode.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold) # Beispiel: Größe 12, Fett
    $parentNode.ForeColor = $accentColor

    foreach ($prog in $programCategories[$category]) {
        $childNode = New-Object System.Windows.Forms.TreeNode $prog.Name
        $childNode.Tag = $prog.Id

        # Installierte Programme hervorheben (fett + grün)
        if (Test-WingetPackageInstalled -packageId $prog.Id) {
            $childNode.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
            $childNode.ForeColor = [System.Drawing.Color]::Green
        }

        $parentNode.Nodes.Add($childNode) | Out-Null
        $allProgramNodes += $childNode
    }

    $downloadTreeView.Nodes.Add($parentNode) | Out-Null
}

# --- Buttons ---
# Install Button
$installButton = New-Object System.Windows.Forms.Button
$installButton.Text = "Install"
$installButton.Size = New-Object System.Drawing.Size(100, 30)
$installButton.Location = New-Object System.Drawing.Point(15, 660)
$installButton.BackColor = $accentColor
$installButton.ForeColor = [System.Drawing.Color]::White
$installButton.Enabled = $false
$tabDownloads.Controls.Add($installButton)

# Update Button
$updateButton = New-Object System.Windows.Forms.Button
$updateButton.Text = "Update all"
$updateButton.Size = New-Object System.Drawing.Size(100, 30)
$updateButton.Location = New-Object System.Drawing.Point(130, 660)
$updateButton.BackColor = $accentColor
$updateButton.ForeColor = [System.Drawing.Color]::White
$updateButton.Enabled = $true
$tabDownloads.Controls.Add($updateButton)

# Uninstall Button
$uninstallButton = New-Object System.Windows.Forms.Button
$uninstallButton.Text = "Uninstall"
$uninstallButton.Size = New-Object System.Drawing.Size(100, 30)
$uninstallButton.Location = New-Object System.Drawing.Point(245, 660)
$uninstallButton.BackColor = $accentColor
$uninstallButton.ForeColor = [System.Drawing.Color]::White
$uninstallButton.Enabled = $false
$tabDownloads.Controls.Add($uninstallButton)

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

# Variable zum Verhindern von rekursiven Events
$global:IgnoreCheckEventDownloads = $false

# Funktion zum Status der Auswahl (installiert / nicht installiert)
function Get-SelectedInstallStatus {
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

# Eventhandler: wenn Parent-Node angeklickt wird, alle Kinder selektieren/deselektieren
$downloadTreeView.Add_AfterCheck({
    param($sender, $e)

    if ($global:IgnoreCheckEventDownloads) { return }
    $global:IgnoreCheckEventDownloads = $true

    if ($e.Node.Nodes.Count -gt 0) {
        foreach ($child in $e.Node.Nodes) {
            $child.Checked = $e.Node.Checked
        }
    }
    else {
        $parent = $e.Node.Parent
        if ($parent -ne $null) {
            $uncheckedCount = ($parent.Nodes | Where-Object { -not $_.Checked } | Measure-Object).Count
            $parent.Checked = ($uncheckedCount -eq 0)
        }
    }

    # Prüfe wie viele Programme ausgewählt sind und ob installiert oder nicht
    $status = Get-SelectedInstallStatus
    $countInstalled = $status.Installed.Count
    $countNotInstalled = $status.NotInstalled.Count
    $countTotal = $status.AllSelected.Count

    # Buttons immer sichtbar
    $installButton.Visible = $true
    $updateButton.Visible = $true
    $uninstallButton.Visible = $true

    # Hier die Logik zur Aktivierung/Deaktivierung
    if ($countTotal -eq 0) {
        # Nichts ausgewählt
        $installButton.Enabled = $false
        $updateButton.Enabled = $true # Update Button immer aktiv
        $uninstallButton.Enabled = $false
        $installButton.Text = "Install"
    }
    elseif ($countInstalled -eq $countTotal -and $countTotal -gt 0) {
        # Nur installierte Programme ausgewählt
        $installButton.Enabled = $false
        $updateButton.Enabled = $true # Update Button immer aktiv
        $uninstallButton.Enabled = $true
    }
    elseif ($countNotInstalled -eq $countTotal) {
        # Nur nicht installierte Programme ausgewählt
        $installButton.Enabled = $true
        $updateButton.Enabled = $true # Update Button immer aktiv
        $uninstallButton.Enabled = $false
        $installButton.Text = "Install"
    }
    else {
        # Mischung (installiert und nicht installiert) ausgewählt
        $installButton.Enabled = $true
        $installButton.Text = "Install/Update"
        $updateButton.Enabled = $true # Update Button immer aktiv
        $uninstallButton.Enabled = $false
    }

    $global:IgnoreCheckEventDownloads = $false
})

# Funktion zum Installieren per winget (installiert oder updated)
function Install-WingetProgram {
    param([string]$packageId)

    $statusDownloadLabel.Text = "Status: Installiere/Aktualisiere $($packageId)..."
    $downloadProgressBar.Visible = $true
    $downloadProgressBar.Style = 'Marquee'
    $form.Refresh()

    $timeoutSeconds = 180 # Standard-Timeout für Einzelinstallationen (3 Minuten)

    $wingetResult = Invoke-WingetCommand -arguments "install --id $($packageId) --source winget --accept-package-agreements --accept-source-agreements" -timeoutSeconds $timeoutSeconds

    $downloadProgressBar.Visible = $false

    if ($wingetResult.TimedOut) {
        [System.Windows.Forms.MessageBox]::Show("Die Installation von $($packageId) hat das Zeitlimit überschritten.", "Winget Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    } elseif ($wingetResult.ExitCode -ne 0) {
        $errorMessage = "Fehler bei der Installation/Aktualisierung von $($packageId). Exit Code: $($wingetResult.ExitCode). "
        if (![string]::IsNullOrEmpty($wingetResult.Errors)) {
            $errorMessage += "Fehler: $($wingetResult.Errors)."
        }
        $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
        [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget Installation/Update Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    } else {
        $statusDownloadLabel.Text = "$($packageId) installiert/aktualisiert."
        return $true
    }
}

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

function Uninstall-Programs {
    param([System.Windows.Forms.TreeNode[]]$nodes)

    $downloadProgressBar.Style = 'Continuous'
    $downloadProgressBar.Minimum = 0
    $downloadProgressBar.Maximum = $nodes.Count
    $downloadProgressBar.Value = 0
    $downloadProgressBar.Visible = $true

    $timeoutSeconds = 180 # Standard-Timeout für Deinstallation (3 Minuten)

    foreach ($node in $nodes) {
        $pkgId = $node.Tag
        $statusDownloadLabel.Text = "Status: Deinstalliere $($node.Text) (ID: $($pkgId))..."
        $form.Refresh()

        $wingetResult = Invoke-WingetCommand -arguments "uninstall --id $($pkgId) --accept-source-agreements" -timeoutSeconds $timeoutSeconds
        
        if ($wingetResult.TimedOut) {
            [System.Windows.Forms.MessageBox]::Show("Die Deinstallation von $($node.Text) hat das Zeitlimit überschritten.", "Winget Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            break # Breche ab, wenn ein Timeout auftritt
        } elseif ($wingetResult.ExitCode -ne 0) {
            $errorMessage = "Fehler bei der Deinstallation von $($node.Text). Exit Code: $($wingetResult.ExitCode). "
            if (![string]::IsNullOrEmpty($wingetResult.Errors)) {
                $errorMessage += "Fehler: $($wingetResult.Errors)."
            }
            $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
            [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget Deinstallation Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            break # Breche ab, wenn ein Fehler auftritt
        } else {
            $statusDownloadLabel.Text = "$($node.Text) deinstalliert."
        }
        $downloadProgressBar.Value++
    }
    $downloadProgressBar.Visible = $false
    $statusDownloadLabel.Text = "Deinstallationsvorgang abgeschlossen."
    Update-InstalledProgramsStatus
}

# Helper-Funktion zum Ausführen von Winget-Befehlen und Loggen der Ausgabe
function Invoke-WingetCommand {
    param(
        [string]$arguments,
        [int]$timeoutSeconds = 60 # Standard-Timeout
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

        # Asynchrones Lesen der Streams (PowerShell 5.1-kompatibel)
        $outputTask = $process.StandardOutput.ReadToEndAsync()
        $errorTask = $process.StandardError.ReadToEndAsync()

        if ($process.WaitForExit($timeoutSeconds * 1000)) {
            $output = $outputTask.Result
            $errors = $errorTask.Result

            # Schreibe Ausgaben in temporäre Dateien
            $output | Out-File -FilePath $outputFile -Encoding UTF8
            $errors | Out-File -FilePath $errorFile -Encoding UTF8

            # Rückgabe-Objekt mit allen relevanten Informationen
            [PSCustomObject]@{
                ExitCode = $process.ExitCode
                Output = $output
                Errors = $errors
                OutputFile = $outputFile
                ErrorFile = $errorFile
                TimedOut = $false
            }
        } else {
            $process.Kill()
            [PSCustomObject]@{
                ExitCode = $null # Kein ExitCode bei Timeout
                Output = ""
                Errors = "Winget-Befehl hat das Zeitlimit überschritten ($($timeoutSeconds)s)."
                OutputFile = $outputFile
                ErrorFile = $errorFile
                TimedOut = $true
            }
        }
    }
    catch {
        [PSCustomObject]@{
            ExitCode = $null
            Output = ""
            Errors = "Unerwarteter Fehler beim Ausführen von winget: $_"
            OutputFile = $outputFile
            ErrorFile = $errorFile
            TimedOut = $false
        }
    }
}

# Klick-Events der Buttons
$installButton.Add_Click({
        $status = Get-SelectedInstallStatus
        $toInstallOrUpdate = $status.AllSelected
        if ($toInstallOrUpdate.Count -eq 0) {
            $statusDownloadLabel.Text = "No program selected."
            return
        }
        Install-OrUpdate -nodes $toInstallOrUpdate
    })

    $updateButton.Add_Click({
        try {
            $selectedNodes = $downloadTreeView.Nodes.Find("Installed", $true) | Where-Object { $_.Checked }
    
            if ($selectedNodes.Count -eq 0) {
                # Keine spezifischen Programme ausgewählt, also "Alle aktualisieren"
                [System.Windows.Forms.MessageBox]::Show("Keine einzelnen Programme ausgewählt. Starte die Aktualisierung aller verfügbaren Winget-Updates.", "Alle aktualisieren", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                
                # Überprüfe, ob es überhaupt aktualisierbare Pakete gibt
                # Hinweis: Deine globale Variable $global:updatablePackageIds wird aktuell nicht gefüllt.
                # Um diese Prüfung sinnvoll zu nutzen, müsste Update-InstalledPackageIds auch die updatable Packages ermitteln.
                # Fürs Erste kommentiere ich diese Prüfung aus, bis wir sie implementieren oder entfernen.
                # if ($global:updatablePackageIds.Count -eq 0) {
                #     [System.Windows.Forms.MessageBox]::Show("Es sind keine Winget-Updates verfügbar.", "Keine Updates", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                #     return
                # }
    
                $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                    "Möchten Sie alle verfügbaren Winget-Paket-Updates installieren? Dies kann einige Zeit dauern.",
                    "Alle Updates installieren?",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
    
                if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    $statusDownloadLabel.Text = "Status: Aktualisiere alle Winget-Pakete..."
                    $downloadProgressBar.Style = 'Marquee'
                    $downloadProgressBar.Visible = $true
                    $form.Refresh()
    
                    $wingetResult = Invoke-WingetCommand -arguments "upgrade --all --accept-package-agreements --accept-source-agreements" -timeoutSeconds 300
                    
                    if ($wingetResult.TimedOut) {
                        [System.Windows.Forms.MessageBox]::Show("Die Aktualisierung aller Winget-Pakete hat das Zeitlimit überschritten.", "Winget Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    } elseif ($wingetResult.ExitCode -ne 0) {
                        $errorMessage = "Fehler beim Aktualisieren aller Pakete. Exit Code: $($wingetResult.ExitCode). "
                        if (![string]::IsNullOrEmpty($wingetResult.Errors)) {
                            $errorMessage += "Fehler: $($wingetResult.Errors)."
                        }
                        $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
                        [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget Upgrade Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                    } else {
                        [System.Windows.Forms.MessageBox]::Show("Alle Winget-Pakete wurden aktualisiert (falls Updates verfügbar waren).", "Updates Abgeschlossen", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                    }
                }
            } else {
                # Einzelne Programme ausgewählt, verarbeite diese wie gehabt
                $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                    "Möchten Sie die ausgewählten Programme aktualisieren?",
                    "Programme aktualisieren?",
                    [System.Windows.Forms.MessageBoxButtons]::YesNo,
                    [System.Windows.Forms.MessageBoxIcon]::Question
                )
    
                if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                    # Hier rufen wir Install-OrUpdate auf, nicht Install-SelectedPackages
                    Install-OrUpdate -nodes $selectedNodes
                }
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("Ein Fehler ist aufgetreten: $_", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        } finally {
            Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
        }
    })

$uninstallButton.Add_Click({
        $status = Get-SelectedInstallStatus
        $toUninstall = $status.Installed
        if ($toUninstall.Count -eq 0) {
            $statusDownloadLabel.Text = "No installed program selected for uninstall."
            return
        }
        Uninstall-Programs -nodes $toUninstall
    })

$uncheckAllButton.Add_Click({
        $global:IgnoreCheckEventDownloads = $true
    
        foreach ($parentNode in $downloadTreeView.Nodes) {
            # Alle Kinder unchecken
            foreach ($childNode in $parentNode.Nodes) {
                $childNode.Checked = $false
            }
            # Parent auch unchecken
            $parentNode.Checked = $false
        }
    
        # Buttons deaktivieren
        $installButton.Enabled = $false
        $updateButton.Enabled = $true
        $uninstallButton.Enabled = $false
    
        $statusDownloadLabel.Text = "All selections cleared."
    
        $global:IgnoreCheckEventDownloads = $false
    })

# Schriftgröße anpassen
Set-FontSizeRecursive -control $tabDownloads -fontSize 11

# Vor dem Initialisieren der Winget-Liste eine kurze Meldung anzeigen
$statusDownloadLabel.Text = "Status: Initialisiere Winget-Daten..."
$downloadProgressBar.Visible = $true
$downloadProgressBar.Style = 'Marquee' # Setzt den Stil auf "Marquee" für eine durchlaufende Animation
$form.Refresh() # Wichtig, damit die GUI sofort aktualisiert wird

# Initialen Status der installierten Programme laden und TreeView aktualisieren
Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel

# Tab 5: Untested

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

# Set font size in $tabUntested and all its controls
Set-FontSizeRecursive -control $tabUntested -fontSize 11

# (Optional) You can add controls like checkboxes, buttons here similarly

# Functions

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

function UpdateButtons {
    $applyButton.Enabled = $hasChanges
    $restartButton.Visible = $restartNeeded
}

# TreeView AfterCheck event - sync child nodes and update parent states
$treeView.Add_AfterCheck({
        param($sender, $e)

        if ($global:IgnoreCheckEvent) { return }
        $global:IgnoreCheckEvent = $true

        if ($e.Node.Tag -eq $null) {
            # Category checked/unchecked - check/uncheck all children accordingly
            foreach ($child in $e.Node.Nodes) {
                $child.Checked = $e.Node.Checked
            }
        }
        else {
            # Single tweak checked/unchecked - update parent category state
            $parent = $e.Node.Parent
            if ($parent -ne $null) {
                $allChecked = $true
                $allUnchecked = $true
                foreach ($child in $parent.Nodes) {
                    if ($child.Checked) { $allUnchecked = $false } else { $allChecked = $false }
                }
                if ($allChecked) {
                    $parent.Checked = $true
                    $parent.StateImageIndex = -1
                }
                elseif ($allUnchecked) {
                    $parent.Checked = $false
                    $parent.StateImageIndex = -1
                }
                else {
                    $parent.Checked = $false
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
        $global:hasChanges = $true
        UpdateButtons
    })

# Initial sync
Sync-TweakStates

Get-AndDisplayAllSystemInfo

Check-ForUpdates

# Show form
[void] $form.ShowDialog()
