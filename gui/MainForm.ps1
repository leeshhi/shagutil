# GUI/MainForm.ps1

function Initialize-MainForm {
    # Colors (can be moved to a separate config file if needed)
    $global:darkBackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $global:darkForeColor = [System.Drawing.Color]::White
    $global:footerBackColor = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $global:accentColor = [System.Drawing.Color]::FromArgb(0, 122, 204)

    # Form
    $global:form = New-Object System.Windows.Forms.Form
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
    $global:tabControl = New-Object System.Windows.Forms.TabControl
    $tabControl.Dock = 'Fill'
    $tabControl.Font = New-Object System.Drawing.Font("Segoe UI", 14)

    # Enable OwnerDraw for individual tab text color
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
            if ($rect -is [System.Array]) { $rect = $rect[0] }

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

    $form.Add_Load({
            $updateInfo = Check-ForUpdates -currentVersion $scriptVersion # Pass $scriptVersion
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

    # Call functions to initialize individual tabs
    Initialize-TabHome
    Initialize-TabGeneral
    Initialize-TabAdvanced
    Initialize-TabDownloads
    Initialize-TabUntested
}