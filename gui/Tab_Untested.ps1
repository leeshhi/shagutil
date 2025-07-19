# GUI/Tab_Untested.ps1

function Initialize-TabUntested {
    $global:tabUntested = New-Object System.Windows.Forms.TabPage "Untested"
    $tabUntested.BackColor = $darkBackColor
    $tabUntested.ForeColor = $darkForeColor
    $tabControl.TabPages.Add($tabUntested)

    $untestedLabel = New-Object System.Windows.Forms.Label
    $untestedLabel.Text = "These tweaks are untested and experimental."
    $untestedLabel.AutoSize = $true
    $untestedLabel.Location = New-Object System.Drawing.Point(15, 15)
    $untestedLabel.ForeColor = $darkForeColor
    $tabUntested.Controls.Add($untestedLabel)

    Set-FontSizeRecursive -control $tabUntested -fontSize 11
}