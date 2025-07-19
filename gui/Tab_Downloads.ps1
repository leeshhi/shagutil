# GUI/Tab_Downloads.ps1

function Initialize-TabDownloads {
    $global:tabDownloads = New-Object System.Windows.Forms.TabPage "Downloads"
    $tabDownloads.BackColor = $darkBackColor
    $tabDownloads.ForeColor = $darkForeColor
    $tabControl.TabPages.Add($tabDownloads)

    $downloadsLabel = New-Object System.Windows.Forms.Label
    $downloadsLabel.Text = "Select the programs to install via winget:"
    $downloadsLabel.AutoSize = $true
    $downloadsLabel.Location = New-Object System.Drawing.Point(15, 15)
    $downloadsLabel.ForeColor = $darkForeColor
    $tabDownloads.Controls.Add($downloadsLabel)

    $global:downloadTreeView = New-Object System.Windows.Forms.TreeView
    $downloadTreeView.Size = New-Object System.Drawing.Size(650, 600)
    $downloadTreeView.Location = New-Object System.Drawing.Point(15, 50)
    $downloadTreeView.BackColor = $darkBackColor
    $downloadTreeView.ForeColor = $darkForeColor
    $downloadTreeView.HideSelection = $false
    $downloadTreeView.CheckBoxes = $true
    $tabDownloads.Controls.Add($downloadTreeView)

    $global:allProgramNodes = [System.Collections.ArrayList]::new()

    # --- Start: ProgramDefinitions direkt hier eingefügt ---
    # Dieser Block ersetzt den Inhalt von Data/ProgramDefinitions.psd1
    $programDefinitions = @{
        ProgramCategories = @{
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
    }
    # --- Ende: ProgramDefinitions direkt hier eingefügt ---

    $loadedProgramCategories = $programDefinitions.ProgramCategories

    # Initial Winget check and install prompt
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        [System.Windows.Forms.MessageBox]::Show("winget was not found. Attempting to install the app installer (using winget) from the Microsoft Store.", "winget not found", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)

        try {
            Start-Process -FilePath "ms-windows-store://pdp/?ProductId=9NBLGGH4NNS1" -PassThru -NoNewWindow -ErrorAction Stop
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


    foreach ($category in $loadedProgramCategories.Keys) {
        $parentNode = New-Object System.Windows.Forms.TreeNode $category
        $parentNode.ForeColor = $accentColor

        foreach ($prog in $loadedProgramCategories[$category]) {
            $childNode = New-Object System.Windows.Forms.TreeNode $prog.Name
            $childNode.Tag = $prog.Id

            # Initial check for installed programs (will be updated again by Update-InstalledProgramsStatus later)
            if (Test-WingetPackageInstalled -packageId $prog.Id) {
                $childNode.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
                $childNode.ForeColor = [System.Drawing.Color]::Green
            }

            $parentNode.Nodes.Add($childNode) | Out-Null
            $allProgramNodes.Add($childNode) | Out-Null
        }
        $downloadTreeView.Nodes.Add($parentNode) | Out-Null
    }

    $global:installButton = New-Object System.Windows.Forms.Button
    $installButton.Text = "Install"
    $installButton.Size = New-Object System.Drawing.Size(100, 30)
    $installButton.Location = New-Object System.Drawing.Point(15, 660)
    $installButton.BackColor = $accentColor
    $installButton.ForeColor = [System.Drawing.Color]::Lime
    $installButton.Enabled = $false
    $tabDownloads.Controls.Add($installButton)

    $global:uninstallButton = New-Object System.Windows.Forms.Button
    $uninstallButton.Text = "Uninstall"
    $uninstallButton.Size = New-Object System.Drawing.Size(100, 30)
    $uninstallButton.Location = New-Object System.Drawing.Point(245, 660)
    $uninstallButton.BackColor = $accentColor
    $uninstallButton.ForeColor = [System.Drawing.Color]::Red
    $uninstallButton.Enabled = $false
    $tabDownloads.Controls.Add($uninstallButton)

    $global:updateButton = New-Object System.Windows.Forms.Button
    $updateButton.Text = "Update all"
    $updateButton.Size = New-Object System.Drawing.Size(100, 30)
    $updateButton.Location = New-Object System.Drawing.Point(130, 660)
    $updateButton.BackColor = $accentColor
    $updateButton.ForeColor = [System.Drawing.Color]::Lime
    $updateButton.Enabled = $true
    $tabDownloads.Controls.Add($updateButton)

    $global:uncheckAllButton = New-Object System.Windows.Forms.Button
    $uncheckAllButton.Text = "Uncheck all"
    $uncheckAllButton.Size = New-Object System.Drawing.Size(100, 30)
    $uncheckAllButton.Location = New-Object System.Drawing.Point(360, 660)
    $uncheckAllButton.BackColor = $accentColor
    $uncheckAllButton.ForeColor = [System.Drawing.Color]::White
    $tabDownloads.Controls.Add($uncheckAllButton)

    $global:statusDownloadLabel = New-Object System.Windows.Forms.Label
    $statusDownloadLabel.Size = New-Object System.Drawing.Size(600, 30)
    $statusDownloadLabel.Location = New-Object System.Drawing.Point(15, 700)
    $statusDownloadLabel.ForeColor = $darkForeColor
    $tabDownloads.Controls.Add($statusDownloadLabel)

    $global:downloadProgressBar = New-Object System.Windows.Forms.ProgressBar
    $downloadProgressBar.Size = New-Object System.Drawing.Size(600, 20)
    $downloadProgressBar.Location = New-Object System.Drawing.Point(15, 730)
    $downloadProgressBar.Visible = $false
    $tabDownloads.Controls.Add($downloadProgressBar)

    # Event handlers
    $downloadTreeView.Add_AfterCheck({
            param($sender, $e)

            if ($global:IgnoreCheckEventDownloads) { return }
            $global:IgnoreCheckEventDownloads = $true

            if ($e.Node.Nodes.Count -gt 0) {
                # Dies ist ein Kategorie-Knoten
                foreach ($child in $e.Node.Nodes) {
                    $child.Checked = $e.Node.Checked
                }
            }
            else {
                # Dies ist ein Programm-Knoten
                $parent = $e.Node.Parent
                if ($parent -ne $null) {
                    $uncheckedCount = ($parent.Nodes | Where-Object { -not $_.Checked } | Measure-Object).Count
                    $parent.Checked = ($uncheckedCount -eq 0) # Parent ist gecheckt, wenn alle Kinder gecheckt sind
                }
            }

            # Button-Zustände aktualisieren
            $status = Get-SelectedInstallStatus
            $countInstalled = $status.Installed.Count
            $countNotInstalled = $status.NotInstalled.Count
            $countTotal = $status.AllSelected.Count

            # Logik für Button-Sichtbarkeit/Enabled-Status
            $installButton.Visible = $true
            $updateButton.Visible = $true
            $uninstallButton.Visible = $true

            if ($countTotal -eq 0) {
                $installButton.Enabled = $false
                $updateButton.Enabled = $true # Update all sollte immer möglich sein
                $uninstallButton.Enabled = $false
                $installButton.Text = "Install"
            }
            elseif ($countInstalled -eq $countTotal -and $countTotal -gt 0) {
                # Alle ausgewählten Programme sind bereits installiert
                $installButton.Enabled = $false # Nichts zu installieren
                $updateButton.Enabled = $true # Update all oder update ausgewählter (bereits installierter)
                $uninstallButton.Enabled = $true # Möglichkeit zum Deinstallieren
            }
            elseif ($countNotInstalled -eq $countTotal) {
                # Alle ausgewählten Programme sind nicht installiert
                $installButton.Enabled = $true # Nur Installation nötig
                $updateButton.Enabled = $true # Update all
                $uninstallButton.Enabled = $false # Nichts zu deinstallieren
                $installButton.Text = "Install"
            }
            else {
                # Mischzustand (einige installiert, einige nicht)
                $installButton.Enabled = $true # Install/Update ist der richtige Button
                $installButton.Text = "Install/Update"
                $updateButton.Enabled = $true # Update all oder update ausgewählter
                $uninstallButton.Enabled = $false # Hier müsste man genauer prüfen, ob installierte zum deinstallieren ausgewählt sind
            }
            $global:IgnoreCheckEventDownloads = $false
        })

    $uninstallButton.Add_Click({
            $status = Get-SelectedInstallStatus
            $toUninstall = $status.Installed # Nur die installieren, die als installiert erkannt wurden
            if ($toUninstall.Count -eq 0) {
                $statusDownloadLabel.Text = "No installed program selected for uninstall."
                return
            }
            Uninstall-WingetPrograms -nodes $toUninstall -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
        })

    $installButton.Add_Click({
            $status = Get-SelectedInstallStatus
            $toInstallOrUpdate = $status.AllSelected # Alle ausgewählten sollen installiert/aktualisiert werden
            if ($toInstallOrUpdate.Count -eq 0) {
                $statusDownloadLabel.Text = "No program selected."
                return
            }
            Install-OrUpdate-WingetPrograms -nodes $toInstallOrUpdate -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
        })

    $updateButton.Add_Click({
            try {
                # Überprüfen, ob spezifische Programme ausgewählt sind (und installiert sind)
                $selectedAndInstalledNodes = ($allProgramNodes | Where-Object { $_.Checked -and (Test-WingetPackageInstalled -packageId $_.Tag) })

                if ($selectedAndInstalledNodes.Count -eq 0) {
                    # Wenn keine spezifischen Programme ausgewählt ODER keine der ausgewählten installiert sind
                    $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                        "No individual programs selected or no selected program is installed. Do you want to install all available Winget package updates? This may take some time.",
                        "Update all?",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Question
                    )

                    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                        $statusDownloadLabel.Text = "Status: Updating all Winget packages..."
                        $downloadProgressBar.Style = 'Marquee' # Marquee-Stil für unbestimmten Fortschritt
                        $downloadProgressBar.Visible = $true
                        $form.Refresh()

                        # Führt 'winget upgrade --all' aus
                        $wingetResult = Invoke-WingetCommand -arguments "upgrade --all --accept-package-agreements --accept-source-agreements" -timeoutSeconds 300
                    
                        $downloadProgressBar.Style = 'Blocks' # Zurück auf normalen Stil
                        $downloadProgressBar.Visible = $false
                        $statusDownloadLabel.Text = "Status: Finished checking for updates."

                        if ($wingetResult.TimedOut) {
                            [System.Windows.Forms.MessageBox]::Show("The update of all Winget packages has timed out.", "Winget Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        }
                        elseif ($wingetResult.ExitCode -ne 0) {
                            $errorMessage = "Error updating all packages. Exit Code: $($wingetResult.ExitCode). "
                            if (![string]::IsNullOrEmpty($wingetResult.Errors)) {
                                $errorMessage += "Error: $($wingetResult.Errors)."
                            }
                            $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
                            [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget upgrade error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                        }
                        else {
                            [System.Windows.Forms.MessageBox]::Show("All Winget packages have been updated (if updates were available).", "Updates Abgeschlossen", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                        }
                    }
                }
                else {
                    # Wenn spezifische, installierte Programme ausgewählt sind, nur diese aktualisieren
                    $dialogResult = [System.Windows.Forms.MessageBox]::Show(
                        "Do you want to update the selected installed programs?",
                        "Update programs?",
                        [System.Windows.Forms.MessageBoxButtons]::YesNo,
                        [System.Windows.Forms.MessageBoxIcon]::Question
                    )

                    if ($dialogResult -eq [System.Windows.Forms.DialogResult]::Yes) {
                        # Hier rufen wir Install-OrUpdate-WingetPrograms auf, aber nur mit den installierten und ausgewählten Nodes
                        Install-OrUpdate-WingetPrograms -nodes $selectedAndInstalledNodes -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
                    }
                }
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("An error has occurred: $_", "Fehler", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
            finally {
                # Nach jeder Update-Aktion den Status der installierten Programme in der GUI aktualisieren
                Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
                # Anschließend die Buttons aktualisieren (dies wird durch den AfterCheck-Handler nach dem Update-Status aufgerufen)
                # ODER hier direkt Get-SelectedInstallStatus aufrufen und die Buttons setzen
                $status = Get-SelectedInstallStatus # Ruft den Status der gecheckten Elemente erneut ab
                $countInstalled = $status.Installed.Count
                $countNotInstalled = $status.NotInstalled.Count
                $countTotal = $status.AllSelected.Count
                # Logik zur Aktualisierung der Buttons wie im AfterCheck-Handler
                # (Hier nur ein Platzhalter, da die Logik oben in AfterCheck komplex ist)
                $installButton.Enabled = ($countNotInstalled -gt 0)
                $uninstallButton.Enabled = ($countInstalled -gt 0)
                $updateButton.Enabled = $true # Update all ist immer möglich
                # Text anpassen
                if ($countNotInstalled -gt 0 -and $countInstalled -gt 0) { $installButton.Text = "Install/Update" }
                elseif ($countNotInstalled -gt 0) { $installButton.Text = "Install" }
                else { $installButton.Text = "Install" } # Kein spezifischer Text, wenn nichts ausgewählt ist oder nur Installiertes
            }
        })

    $uncheckAllButton.Add_Click({
            $global:IgnoreCheckEventDownloads = $true
            foreach ($parentNode in $downloadTreeView.Nodes) {
                foreach ($childNode in $parentNode.Nodes) {
                    $childNode.Checked = $false
                }
                # Optional: Parent-Checkboxen auch auf False setzen, wenn alle Kinder unchecked sind
                $parentNode.Checked = $false
            }
            # Buttons direkt aktualisieren, da jetzt nichts ausgewählt ist
            $installButton.Enabled = $false
            $updateButton.Enabled = $true # Update all bleibt aktiv
            $uninstallButton.Enabled = $false
            $statusDownloadLabel.Text = "All selections cleared."
            $global:IgnoreCheckEventDownloads = $false
        })

    Set-FontSizeRecursive -control $tabDownloads -fontSize 11

    # Führt eine initiale Überprüfung des Installationsstatus durch
    Update-InstalledProgramsStatus -parentForm $form -progressBar $downloadProgressBar -statusLabel $statusDownloadLabel
}

function Get-SelectedInstallStatus {
    $selected = $allProgramNodes | Where-Object { $_.Checked }
    $installed = [System.Collections.ArrayList]::new()
    $notInstalled = [System.Collections.ArrayList]::new()

    foreach ($node in $selected) {
        if (Test-WingetPackageInstalled -packageId $node.Tag) {
            $installed.Add($node) | Out-Null
        }
        else {
            $notInstalled.Add($node) | Out-Null
        }
    }
    return [PSCustomObject]@{
        Installed    = $installed
        NotInstalled = $notInstalled
        AllSelected  = $selected
    }
}