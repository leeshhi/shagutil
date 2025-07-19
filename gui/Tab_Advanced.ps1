# GUI/Tab_Advanced.ps1

function Initialize-TabAdvanced {
    $global:tabAdvanced = New-Object System.Windows.Forms.TabPage "Advanced"
    $tabAdvanced.BackColor = $darkBackColor
    $tabAdvanced.ForeColor = $darkForeColor
    $tabControl.TabPages.Add($tabAdvanced)

    $advancedLabel = New-Object System.Windows.Forms.Label
    $advancedLabel.Text = "Advanced tweaks use only if you know what your doing."
    $advancedLabel.AutoSize = $true
    $advancedLabel.Location = New-Object System.Drawing.Point(15, 15)
    $advancedLabel.ForeColor = $darkForeColor
    $tabAdvanced.Controls.Add($advancedLabel)

    Set-FontSizeRecursive -control $tabAdvanced -fontSize 11
}