# Functions/UI_Functions.ps1

function Set-FontSizeRecursive {
    param([System.Windows.Forms.Control]$control, [float]$fontSize)

    $newFont = New-Object System.Drawing.Font($control.Font.FontFamily, $fontSize, $control.Font.Style)
    $control.Font = $newFont

    foreach ($child in $control.Controls) {
        Set-FontSizeRecursive -control $child -fontSize $fontSize
    }
}