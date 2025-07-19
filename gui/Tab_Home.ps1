# GUI/Tab_Home.ps1

function Initialize-TabHome {
    $global:tabHome = New-Object System.Windows.Forms.TabPage "Home"
    $tabHome.BackColor = $darkBackColor
    $tabHome.ForeColor = $darkForeColor
    $tabControl.TabPages.Add($tabHome)

    $global:systemInfoPanel = New-Object System.Windows.Forms.Panel
    $systemInfoPanel.Size = New-Object System.Drawing.Size(550, 400)
    $systemInfoPanel.Location = New-Object System.Drawing.Point(10, 10)
    $systemInfoPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tabHome.Controls.Add($systemInfoPanel)

    $systemInfoTitle = New-Object System.Windows.Forms.Label
    $systemInfoTitle.Text = "System Information"
    $systemInfoTitle.Font = New-Object System.Drawing.Font($systemInfoTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
    $systemInfoTitle.AutoSize = $true
    $systemInfoTitle.Location = New-Object System.Drawing.Point(10, 10)
    $systemInfoPanel.Controls.Add($systemInfoTitle)

    # Panel for Quick Links
    $quickLinksPanel = New-Object System.Windows.Forms.Panel
    $quickLinksPanel.Size = New-Object System.Drawing.Size(200, 200)
    $quickLinksPanel.Location = New-Object System.Drawing.Point(10, ($systemInfoPanel.Location.Y + $systemInfoPanel.Size.Height + 20))
    $quickLinksPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tabHome.Controls.Add($quickLinksPanel)

    $quickLinksTitle = New-Object System.Windows.Forms.Label
    $quickLinksTitle.Text = "Quick Links"
    $quickLinksTitle.Font = New-Object System.Drawing.Font($quickLinksTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
    $quickLinksTitle.AutoSize = $true
    $quickLinksTitle.Location = New-Object System.Drawing.Point(10, 10)
    $quickLinksPanel.Controls.Add($quickLinksTitle)

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

    # Panel for Contact Information
    $contactPanel = New-Object System.Windows.Forms.Panel
    $contactPanel.Size = New-Object System.Drawing.Size(200, 200)
    $contactPanel.Location = New-Object System.Drawing.Point(($quickLinksPanel.Location.X + $quickLinksPanel.Size.Width + 20), $quickLinksPanel.Location.Y)
    $contactPanel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
    $tabHome.Controls.Add($contactPanel)

    $contactTitle = New-Object System.Windows.Forms.Label
    $contactTitle.Text = "Connect with me"
    $contactTitle.Font = New-Object System.Drawing.Font($contactTitle.Font.FontFamily, 12, [System.Drawing.FontStyle]::Bold)
    $contactTitle.AutoSize = $true
    $contactTitle.Location = New-Object System.Drawing.Point(10, 10)
    $contactPanel.Controls.Add($contactTitle)

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

    Set-FontSizeRecursive -control $tabHome -fontSize 11
}

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