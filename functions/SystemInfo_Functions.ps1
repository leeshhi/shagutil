# Functions/SystemInfo_Functions.ps1

function Get-OsInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    "OS: $($os.Caption) Version $($os.Version) (Build $($os.BuildNumber))"
}

function Get-CpuInfo {
    $cpu = Get-CimInstance Win32_Processor
    "CPU: $($cpu.Name) ($($cpu.NumberOfCores) Cores, $($cpu.NumberOfLogicalProcessors) Threads)"
}

function Get-RamInfo {
    $os = Get-CimInstance Win32_OperatingSystem # FreePhysicalMemory is in KB
    $ram = Get-CimInstance Win32_ComputerSystem # TotalPhysicalMemory is in Bytes

    $totalMemoryGB = [Math]::Round(($ram.TotalPhysicalMemory / 1GB), 2)
    $freeMemoryGB = [Math]::Round(($os.FreePhysicalMemory / (1024 * 1024)), 2)
    
    "RAM: ${totalMemoryGB}GB Total / ${freeMemoryGB}GB Available"
}

function Get-GpuInfo {
    $gpus = Get-CimInstance Win32_VideoController | Select-Object Name
    $gpuStrings = @()
    foreach ($gpu in $gpus) {
        $gpuStrings += "$($gpu.Name)"
    }
    if ($gpuStrings.Count -gt 0) {
        "GPU: " + ($gpuStrings -join ", ")
    }
    else {
        "GPU: Not found"
    }
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

function Restart-Explorer {
    Get-Process explorer | Stop-Process -Force
    Start-Sleep -Seconds 1
    Start-Process explorer.exe
}