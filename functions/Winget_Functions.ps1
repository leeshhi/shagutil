# Functions/Winget_Functions.ps1

# Helper-Funktion zum Ausführen von Winget-Befehlen und Loggen der Ausgabe
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

# Funktion zum Aktualisieren der Liste der installierten Winget-Pakete (für Windows PowerShell 5.1)
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
            $errorMessage = "Winget 'list' command failed with error code $($wingetResult.ExitCode) finished. "
            if (![string]::IsNullOrEmpty($wingetResult.Errors)) {
                $errorMessage += "Error: $($wingetResult.Errors)."
            }
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

            if ($cols.Length -ge 2) {
                $global:installedPackageIds[$cols[1].Trim()] = $true
            }
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
    param([string]$packageId)
    return $global:installedPackageIds.ContainsKey($packageId)
}

function Install-WingetProgram {
    param([string]$packageId, [System.Windows.Forms.Form]$parentForm, [System.Windows.Forms.ProgressBar]$progressBar, [System.Windows.Forms.Label]$statusLabel)

    $statusLabel.Text = "Status: Install/Update $($packageId)..."
    $progressBar.Visible = $true
    $progressBar.Style = 'Marquee'
    $parentForm.Refresh()

    $timeoutSeconds = 180

    $wingetResult = Invoke-WingetCommand -arguments "install --id $($packageId) --source winget --accept-package-agreements --accept-source-agreements" -timeoutSeconds $timeoutSeconds

    $progressBar.Visible = $false

    if ($wingetResult.TimedOut) {
        [System.Windows.Forms.MessageBox]::Show("The installation of $($packageId) has exceeded the time limit.", "Winget Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
    elseif ($wingetResult.ExitCode -ne 0) {
        $errorMessage = "Error installing/updating $($packageId). Exit Code: $($wingetResult.ExitCode). "
        if (![string]::IsNullOrEmpty($wingetResult.Errors)) {
            $errorMessage += "Fehler: $($wingetResult.Errors)."
        }
        $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
        [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget installation/update error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        return $false
    }
    else {
        $statusLabel.Text = "$($packageId) installed/updated."
        return $true
    }
}

function Install-OrUpdate-WingetPrograms {
    param([System.Windows.Forms.TreeNode[]]$nodes, [System.Windows.Forms.Form]$parentForm, [System.Windows.Forms.ProgressBar]$progressBar, [System.Windows.Forms.Label]$statusLabel)

    $progressBar.Style = 'Continuous'
    $progressBar.Minimum = 0
    $progressBar.Maximum = $nodes.Count
    $progressBar.Value = 0
    $progressBar.Visible = $true

    foreach ($node in $nodes) {
        $pkgId = $node.Tag
        $statusLabel.Text = "Installing/Updating $($node.Text)..."
        $parentForm.Refresh()
        $result = Install-WingetProgram -packageId $pkgId -parentForm $parentForm -progressBar $progressBar -statusLabel $statusLabel
        if (-not $result) {
            [System.Windows.Forms.MessageBox]::Show("Installation/Update of $($node.Text) failed. Aborting.", "Error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            break
        }
        $progressBar.Value++
    }
    $progressBar.Visible = $false
    $statusLabel.Text = "Install/Update process completed."
    Update-InstalledProgramsStatus -parentForm $parentForm -progressBar $progressBar -statusLabel $statusLabel
}

function Uninstall-WingetPrograms {
    param([System.Windows.Forms.TreeNode[]]$nodes, [System.Windows.Forms.Form]$parentForm, [System.Windows.Forms.ProgressBar]$progressBar, [System.Windows.Forms.Label]$statusLabel)

    $progressBar.Style = 'Continuous'
    $progressBar.Minimum = 0
    $progressBar.Maximum = $nodes.Count
    $progressBar.Value = 0
    $progressBar.Visible = $true

    $timeoutSeconds = 180

    foreach ($node in $nodes) {
        $pkgId = $node.Tag
        $statusLabel.Text = "Status: Uninstall $($node.Text) (ID: $($pkgId))..."
        $parentForm.Refresh()

        $wingetResult = Invoke-WingetCommand -arguments "uninstall --id $($pkgId) --accept-source-agreements" -timeoutSeconds $timeoutSeconds
        
        if ($wingetResult.TimedOut) {
            [System.Windows.Forms.MessageBox]::Show("Uninstalling $($node.Text) has exceeded the time limit.", "Winget Timeout", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            break
        }
        elseif ($wingetResult.ExitCode -ne 0) {
            $errorMessage = "Error uninstalling $($node.Text). Exit Code: $($wingetResult.ExitCode). "
            if (![string]::IsNullOrEmpty($wingetResult.Errors)) {
                $errorMessage += "Error: $($wingetResult.Errors)."
            }
            $errorMessage += "`n`nDetails in: $($wingetResult.ErrorFile)"
            [System.Windows.Forms.MessageBox]::Show($errorMessage, "Winget uninstallation error", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            break
        }
        else {
            $statusLabel.Text = "$($node.Text) uninstalled."
        }
        $progressBar.Value++
    }
    $progressBar.Visible = $false
    $statusLabel.Text = "Uninstallation process completed."
    Update-InstalledProgramsStatus -parentForm $parentForm -progressBar $progressBar -statusLabel $statusDownloadLabel
}

function Update-InstalledProgramsStatus {
    param(
        [System.Windows.Forms.Form]$parentForm,
        [System.Windows.Forms.ProgressBar]$progressBar,
        [System.Windows.Forms.Label]$statusLabel
    )
    # Ensure $allProgramNodes is available in the scope where this is called (e.g., from Tab_Downloads.ps1 or main script)
    # For now, it assumes $allProgramNodes is globally accessible after loading Tab_Downloads.ps1
    Update-InstalledPackageIds -parentForm $parentForm -progressBar $progressBar -statusLabel $statusLabel

    foreach ($node in $allProgramNodes) {
        # This depends on $allProgramNodes defined in Tab_Downloads
        $pkgId = $node.Tag
        if (Test-WingetPackageInstalled -packageId $pkgId) {
            $node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Bold)
            $node.ForeColor = [System.Drawing.Color]::Green
        }
        else {
            $node.NodeFont = New-Object System.Drawing.Font($downloadTreeView.Font.FontFamily, 11, [System.Drawing.FontStyle]::Regular)
            $node.ForeColor = $darkForeColor # Assuming $darkForeColor is globally accessible
        }
    }
}