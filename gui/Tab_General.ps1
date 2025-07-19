# GUI/Tab_General.ps1

function Initialize-TabGeneral {
    $global:tabTree = New-Object System.Windows.Forms.TabPage "General"
    $tabTree.BackColor = $darkBackColor
    $tabTree.ForeColor = $darkForeColor
    $tabControl.TabPages.Add($tabTree)

    $global:treeView = New-Object System.Windows.Forms.TreeView
    $treeView.Size = New-Object System.Drawing.Size(650, 600)
    $treeView.Location = New-Object System.Drawing.Point(15, 15)
    $treeView.BackColor = $darkBackColor
    $treeView.ForeColor = $darkForeColor
    $treeView.HideSelection = $false
    $treeView.CheckBoxes = $true
    $tabTree.Controls.Add($treeView)

    $global:statusLabel = New-Object System.Windows.Forms.Label
    $statusLabel.Size = New-Object System.Drawing.Size(650, 30)
    $statusLabel.Location = New-Object System.Drawing.Point(15, 620)
    $statusLabel.TextAlign = 'MiddleLeft'
    $statusLabel.Text = "Status: Ready"
    $statusLabel.ForeColor = $darkForeColor
    $statusLabel.BackColor = $footerBackColor
    $tabTree.Controls.Add($statusLabel)

    $global:progressBar = New-Object System.Windows.Forms.ProgressBar
    $progressBar.Size = New-Object System.Drawing.Size(650, 20)
    $progressBar.Location = New-Object System.Drawing.Point(15, 655)
    $progressBar.Visible = $false
    $tabTree.Controls.Add($progressBar)

    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Size = New-Object System.Drawing.Size(650, 50)
    $buttonPanel.Location = New-Object System.Drawing.Point(15, 685)
    $buttonPanel.BackColor = $darkBackColor
    $tabTree.Controls.Add($buttonPanel)

    $global:applyButton = New-Object System.Windows.Forms.Button
    $applyButton.Text = "Apply"
    $applyButton.Size = New-Object System.Drawing.Size(120, 30)
    $applyButton.Location = New-Object System.Drawing.Point(510, 10)
    $applyButton.Enabled = $false
    $applyButton.BackColor = $accentColor
    $applyButton.ForeColor = [System.Drawing.Color]::White
    $buttonPanel.Controls.Add($applyButton)

    $global:restartButton = New-Object System.Windows.Forms.Button
    $restartButton.Text = "Restart Explorer"
    $restartButton.Size = New-Object System.Drawing.Size(150, 30)
    $restartButton.Location = New-Object System.Drawing.Point(340, 10)
    $restartButton.Visible = $false
    $restartButton.BackColor = $accentColor
    $restartButton.ForeColor = [System.Drawing.Color]::White
    $buttonPanel.Controls.Add($restartButton)

    $global:resetButton = New-Object System.Windows.Forms.Button
    $resetButton.Text = "Reset to Default"
    $resetButton.Size = New-Object System.Drawing.Size(180, 30)
    $resetButton.Location = New-Object System.Drawing.Point(10, 10)
    $resetButton.BackColor = $accentColor
    $resetButton.ForeColor = [System.Drawing.Color]::White
    $buttonPanel.Controls.Add($resetButton)

    $global:checkboxes = [System.Collections.ArrayList]::new()
    
    # --- Start: TweakDefinitions direkt hier eingefügt ---
    $tweakDefinitions = @{
        TweakCategories = @(
            @{
                Category = "Explorer Settings"
                Tweaks   = @(
                    @{ Label = "Dateierweiterungen anzeigen"; RestartNeeded = $false;
                        Description = "Zeigt die Dateierweiterungen (z.B. .txt, .exe) im Windows Explorer an. (Standard: Ausgeblendet)"
                        Enable = {
                            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0 -Force
                        }
                        Disable = {
                            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 1 -Force
                        }
                        GetState = {
                            # Logik: TRUE wenn Wert 0 (ANZEIGEN), FALSE wenn Wert 1 (AUSBLENDEN)
                            # Nutzt direkten Registry-Zugriff für Robustheit
                            try {
                                $regKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey("Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced")
                                if ($regKey) {
                                    $value = $regKey.GetValue("HideFileExt", 1, "DWord") # Standardwert 1 (ausgeblendet)
                                    $regKey.Close()
                                    return ($value -eq 0)
                                }
                            }
                            catch {
                                Write-Error "Fehler beim Lesen von HideFileExt: $_"
                            }
                            return $false # Standardmäßig ausgeblendet oder Fehler
                        }
                        Default = $false # Windows-Standard: Dateierweiterungen sind AUSGEBLENDET
                    },
                    @{ Label = "Versteckte Dateien anzeigen"; RestartNeeded = $false;
                        Description = "Macht versteckte Dateien, Ordner und Laufwerke im Windows Explorer sichtbar."
                        Enable = {
                            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1 -Force
                        }
                        Disable = {
                            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 2 -Force
                        }
                        GetState = {
                            $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
                            $name = "Hidden"
                            if (Test-Path $path) {
                                $value = (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue).$name
                                return ($value -eq 1) # Ist 1, wenn versteckte Dateien angezeigt werden
                            }
                            return $false # Wenn Pfad nicht existiert, sind sie nicht sichtbar
                        }
                        Default = $false # Windows-Standard: Versteckte Dateien sind AUSGEBLENDET
                    }
                )
            },
            @{
                Category = "Suchfunktion"
                Tweaks   = @(
                    @{ Label = "Explorer-Suchfeld deaktivieren"; RestartNeeded = $true;
                        Description = "Deaktiviert das Suchfeld in der Windows Explorer-Taskleiste."
                        Enable = {
                            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 0 -Force
                        }
                        Disable = {
                            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1 -Force
                        }
                        GetState = {
                            $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
                            $name = "SearchboxTaskbarMode"
                            if (Test-Path $path) {
                                $value = (Get-ItemProperty -LiteralPath $path -Name $name -ErrorAction SilentlyContinue).$name
                                return ($value -eq 0) # Ist 0, wenn Suchfeld DEAKTIVIERT ist
                            }
                            return $false # Standardmäßig ist die Suchleiste aktiviert, also GetState sollte false sein, wenn sie nicht deaktiviert ist
                        }
                        Default = $false # Windows-Standard: Suchfeld ist AKTIVIERT
                    }
                )
            }
        )
    }
    # --- Ende: TweakDefinitions direkt hier eingefügt ---

    $loadedTweakCategories = $tweakDefinitions.TweakCategories # Jetzt direkt aus der Variable

    foreach ($category in $loadedTweakCategories) {
        $nodeCat = New-Object System.Windows.Forms.TreeNode $category.Category
        $nodeCat.ForeColor = $accentColor
        foreach ($tweak in $category.Tweaks) {
            $nodeTweak = New-Object System.Windows.Forms.TreeNode $tweak.Label
            $nodeTweak.Checked = $false
            $nodeTweak.Tag = $tweak
            $nodeCat.Nodes.Add($nodeTweak) | Out-Null
            $checkboxes.Add($nodeTweak) | Out-Null
        }
        $treeView.Nodes.Add($nodeCat) | Out-Null
    }

    Set-FontSizeRecursive -control $tabTree -fontSize 11

    # Event handlers
    $treeView.Add_AfterCheck({
            param($sender, $e)

            if ($global:IgnoreCheckEvent) { return }
            $global:IgnoreCheckEvent = $true

            if ($e.Node.Tag -eq $null) {
                # Dies ist eine Kategorie, also alle Kinder setzen
                foreach ($child in $e.Node.Nodes) {
                    $child.Checked = $e.Node.Checked
                }
            }
            else {
                # Dies ist ein Tweak, also Elternknoten aktualisieren
                $parent = $e.Node.Parent
                if ($parent -ne $null) {
                    $allChecked = $true
                    $allUnchecked = $true
                    foreach ($child in $parent.Nodes) {
                        if ($child.Checked) { $allUnchecked = $false } else { $allChecked = $false }
                    }
                    if ($allChecked) {
                        $parent.Checked = $true
                        $parent.StateImageIndex = -1 # Kein Teiler-Haken
                    }
                    elseif ($allUnchecked) {
                        $parent.Checked = $false
                        $parent.StateImageIndex = -1 # Kein Teiler-Haken
                    }
                    else {
                        $parent.Checked = $false
                        $parent.StateImageIndex = 2 # Teiler-Haken
                    }
                }
            }

            $global:hasChanges = $true # Es gibt Änderungen, die angewendet werden müssen

            # Prüfen, ob ein Neustart des Explorers notwendig ist
            $restartNeededLocal = $false
            foreach ($node in $checkboxes) {
                # Überprüfen, ob die Checkbox aktiviert/deaktiviert ist und vom Standard abweicht UND einen Neustart erfordert
                if (($node.Checked -ne $node.Tag.Default) -and $node.Tag.RestartNeeded) {
                    $restartNeededLocal = $true
                    break
                }
            }
            $global:restartNeeded = $restartNeededLocal

            $statusLabel.Text = "Status: Changes not applied yet."
            UpdateButtons # Button-Zustände aktualisieren
            $global:IgnoreCheckEvent = $false # Event-Handler wieder aktivieren
        })

    $applyButton.Add_Click({
            try {
                $statusLabel.Text = "Status: Applying tweaks..."
                $progressBar.Visible = $true
                $progressBar.Minimum = 0
                $progressBar.Maximum = $checkboxes.Count
                $progressBar.Value = 0
                $form.Refresh() # GUI aktualisieren

                for ($i = 0; $i -lt $checkboxes.Count; $i++) {
                    $node = $checkboxes[$i]
                    $tweak = $node.Tag
                    if ($node.Checked) {
                        & $tweak.Enable # Enable-ScriptBlock ausführen
                    }
                    else {
                        & $tweak.Disable # Disable-ScriptBlock ausführen
                    }
                    $progressBar.Value = $i + 1 # Fortschritt aktualisieren
                    $form.Refresh()
                }

                $progressBar.Visible = $false
                Sync-TweakStates # GUI-Zustand nach dem Anwenden erneut synchronisieren
                $statusLabel.Text = "Status: Tweaks applied."
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show("An error occurred while applying tweaks: $_", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                $progressBar.Visible = $false
            }
        })

    $restartButton.Add_Click({
            Restart-Explorer # Funktion zum Neustart des Explorers aufrufen
            $restartButton.Visible = $false
            $statusLabel.Text = "Status: Explorer restarted."
        })

    $resetButton.Add_Click({
            foreach ($node in $checkboxes) {
                $global:IgnoreCheckEvent = $true # Event-Handler während des Zurücksetzens ignorieren
                $node.Checked = $node.Tag.Default # Checkbox auf den Standardwert setzen
                $global:IgnoreCheckEvent = $false
            }
            $statusLabel.Text = "Status: Reset to default."
            Sync-TweakStates # Nach dem Reset den Zustand neu synchronisieren
        })
    
    Sync-TweakStates # Initialer Sync beim Start des Tabs, um den aktuellen Systemzustand anzuzeigen.
}

function Sync-TweakStates {
    $hasChangesLocal = $false
    $restartNeededLocal = $false
    
    # Write-Host "--- Start Sync-TweakStates (Final Integration Attempt) ---" -ForegroundColor Yellow

    foreach ($node in $checkboxes) {
        $tweak = $node.Tag
        $currentState = $false # Standardwert, falls GetState fehlschlägt oder nicht aufgerufen werden kann

        # Robuste Prüfung, ob $tweak und $tweak.GetState gültig sind
        if ($tweak -and ($tweak.GetState -is [ScriptBlock])) {
            try {
                # Den GetState-Skriptblock ausführen und den booleschen Rückgabewert erfassen
                # & {} ist eine Kurzform für Invoke-Command -ScriptBlock
                $currentState = & {
                    try {
                        $result = $tweak.GetState.Invoke()
                        return [bool]$result # Sicherstellen, dass der Rückgabewert ein boolescher Typ ist
                    }
                    catch {
                        # Write-Host "Inner GetState Invoke Error for $($tweak.Label): $_" -ForegroundColor Red
                        return $false # Im Fehlerfall false zurückgeben
                    }
                }

                # Write-Host "Tweak: $($tweak.Label), GetState returned: $currentState (Type: $($currentState.GetType().Name))" -ForegroundColor Cyan
            }
            catch {
                # Write-Host "Outer GetState Invoke Error for $($tweak.Label): $_" -ForegroundColor Red
                $currentState = $false # Sicherstellen, dass der Haken entfernt wird, wenn Fehler auftritt
            }
        }
        else {
            # Write-Host "Error: Tweak or GetState is null/not ScriptBlock for $($tweak.Label)." -ForegroundColor Red
            $currentState = $false
        }
        
        # Den Checked-Status der Checkbox in der GUI setzen
        $node.Checked = $currentState

        # Write-Host "  -> Node Checked status set to: $($node.Checked)" -ForegroundColor Green

        # Prüfen, ob der aktuelle Zustand der Checkbox vom Standard abweicht
        if ($node.Checked -ne $tweak.Default) {
            $hasChangesLocal = $true
            # Wenn ein Neustart erforderlich ist, merken wir uns das
            if ($tweak.RestartNeeded) { $restartNeededLocal = $true }
        }
    }
    # Globale Variablen aktualisieren
    $global:hasChanges = $hasChangesLocal
    $global:restartNeeded = $restartNeededLocal
    
    # Buttons basierend auf den Änderungen aktualisieren
    UpdateButtons
    
    # Status-Label aktualisieren
    if (-not $hasChangesLocal) {
        $statusLabel.Text = "Status: All settings are at default."
    }
    else {
        $statusLabel.Text = "Status: Changes detected, please apply."
    }
    
    # Write-Host "--- End Sync-TweakStates (Final Integration Attempt) ---" -ForegroundColor Yellow
}

function UpdateButtons {
    # 'Apply'-Button nur aktivieren, wenn Änderungen vorhanden sind
    $applyButton.Enabled = $hasChanges
    # 'Restart Explorer'-Button nur sichtbar machen, wenn ein Neustart erforderlich ist
    $restartButton.Visible = $restartNeeded
}