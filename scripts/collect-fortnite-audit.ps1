[CmdletBinding()]
param(
    [string]$OutputDirectory,
    [string[]]$PingTargets = @(),
    [ValidateRange(1, 50)]
    [int]$PingCount = 8,
    [switch]$IncludeServicingHealth,
    [switch]$IncludeUpdateScan
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-Location) ('Fortnite-Audit-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Invoke-Safe {
    param(
        [Parameter(Mandatory = $true)][string]$Section,
        [Parameter(Mandatory = $true)][scriptblock]$Script
    )
    try {
        & $Script
    } catch {
        [pscustomobject]@{
            Section = $Section
            Error   = $_.Exception.Message
        }
    }
}

function Invoke-NativeText {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [string[]]$Arguments = @()
    )
    try {
        $text = (& $FilePath @Arguments 2>&1 | Out-String).Trim()
        $exitCode = $LASTEXITCODE
        [pscustomobject]@{
            ExitCode = $exitCode
            Output   = $text
        }
    } catch {
        [pscustomobject]@{
            ExitCode = $null
            Output   = $null
            Error    = $_.Exception.Message
        }
    }
}

function Get-RegistryValues {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $item = Get-ItemProperty -LiteralPath $Path
        $values = [ordered]@{}
        foreach ($property in $item.PSObject.Properties) {
            if ($property.Name -notmatch '^PS(Path|ParentPath|ChildName|Drive|Provider)$') {
                $values[$property.Name] = $property.Value
            }
        }
        [pscustomobject]$values
    } catch {
        [pscustomobject]@{ Path = $Path; Error = $_.Exception.Message }
    }
}

function Convert-ToGB {
    param($Bytes)
    if ($null -eq $Bytes) { return $null }
    try { return [math]::Round(([double]$Bytes / 1GB), 2) } catch { return $null }
}

function Convert-MonitorText {
    param($Values)
    if ($null -eq $Values) { return $null }
    try {
        return (-join @($Values | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ })).Trim()
    } catch {
        return $null
    }
}

function Protect-LocalText {
    param($Value)
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
        $text = $text.Replace($env:USERPROFILE, '%USERPROFILE%')
    }
    return $text
}

function Get-Percentile {
    param([double[]]$Values, [double]$Percentile)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $index = [math]::Ceiling(($Percentile / 100) * $sorted.Count) - 1
    $index = [math]::Max(0, [math]::Min($index, $sorted.Count - 1))
    return [math]::Round([double]$sorted[$index], 2)
}

function Get-PingSummary {
    param([string]$Target, [int]$Count)
    try {
        $replies = @(Test-Connection -ComputerName $Target -Count $Count -ErrorAction Stop)
        $latencies = @()
        foreach ($reply in $replies) {
            if ($reply.PSObject.Properties.Name -contains 'Latency') {
                $latencies += [double]$reply.Latency
            } elseif ($reply.PSObject.Properties.Name -contains 'ResponseTime') {
                $latencies += [double]$reply.ResponseTime
            }
        }
        $jitterSamples = @()
        for ($i = 1; $i -lt $latencies.Count; $i++) {
            $jitterSamples += [math]::Abs($latencies[$i] - $latencies[$i - 1])
        }
        [pscustomobject]@{
            Target       = $Target
            Sent         = $Count
            Received     = $latencies.Count
            LossPercent  = [math]::Round((($Count - $latencies.Count) * 100.0 / $Count), 2)
            AverageMs    = if ($latencies.Count) { [math]::Round(($latencies | Measure-Object -Average).Average, 2) } else { $null }
            MedianMs     = Get-Percentile -Values $latencies -Percentile 50
            P95Ms        = Get-Percentile -Values $latencies -Percentile 95
            MaximumMs    = if ($latencies.Count) { [math]::Round(($latencies | Measure-Object -Maximum).Maximum, 2) } else { $null }
            MeanJitterMs = if ($jitterSamples.Count) { [math]::Round(($jitterSamples | Measure-Object -Average).Average, 2) } else { $null }
        }
    } catch {
        [pscustomobject]@{ Target = $Target; Sent = $Count; Received = 0; Error = $_.Exception.Message }
    }
}

function Get-IniSelection {
    param([string]$Path)
    $wanted = @(
        'FrameRateLimit', 'bUseVSync', 'bMotionBlur', 'bShowGrass',
        'ResolutionSizeX', 'ResolutionSizeY', 'LastUserConfirmedResolutionSizeX',
        'LastUserConfirmedResolutionSizeY', 'FullscreenMode', 'PreferredFullscreenMode',
        'bUseDynamicResolution', 'bDisableMouseAcceleration', 'bRecordReplays',
        'bRecordHighQualityReplays', 'bRecordCreativeModeReplays',
        'bAllowMultithreadedRendering', 'PreferredRHI', 'PreferredFeatureLevel',
        'RenderingMode', 'bUseNanite', 'bRayTracing'
    )
    $selected = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction Stop) {
        if ($line -notmatch '^\s*([^;#][^=]+?)\s*=\s*(.*)$') { continue }
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        if (($wanted -contains $key) -or $key.StartsWith('sg.', [StringComparison]::OrdinalIgnoreCase)) {
            $selected[$key] = $value
        }
    }
    [pscustomobject]$selected
}

$isAdmin = Test-IsAdministrator
$fortniteProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -like 'FortniteClient*' })
$fortniteRunning = $fortniteProcesses.Count -gt 0

$osAndSystem = Invoke-Safe -Section 'System' -Script {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
    $os = $null
    $cs = $null
    $cimErrors = New-Object System.Collections.Generic.List[string]
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch { $cimErrors.Add($_.Exception.Message) }
    try { $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop } catch { $cimErrors.Add($_.Exception.Message) }
    [pscustomobject]@{
        Manufacturer      = if ($cs) { $cs.Manufacturer } else { $null }
        Model             = if ($cs) { $cs.Model } else { $null }
        SystemType        = if ($cs) { $cs.SystemType } else { $null }
        LogicalProcessors = if ($cs) { $cs.NumberOfLogicalProcessors } else { [Environment]::ProcessorCount }
        TotalMemoryGB     = if ($cs) { Convert-ToGB $cs.TotalPhysicalMemory } else { $null }
        Caption           = if ($os) { $os.Caption } else { $cv.ProductName }
        EditionID         = $cv.EditionID
        DisplayVersion    = $cv.DisplayVersion
        CurrentBuild      = $cv.CurrentBuild
        UBR               = $cv.UBR
        Build             = "$($cv.CurrentBuild).$($cv.UBR)"
        BuildLabEx        = $cv.BuildLabEx
        InstallationType  = $cv.InstallationType
        Architecture      = if ($os) { $os.OSArchitecture } else { $env:PROCESSOR_ARCHITECTURE }
        LastBootUpTime    = if ($os) { $os.LastBootUpTime } else { $null }
        CimWarnings       = @($cimErrors | Select-Object -Unique)
    }
}

$bios = Invoke-Safe -Section 'BIOS' -Script {
    Get-CimInstance Win32_BIOS -ErrorAction Stop | Select-Object Manufacturer,SMBIOSBIOSVersion,Version,ReleaseDate
}

$baseBoard = Invoke-Safe -Section 'BaseBoard' -Script {
    Get-CimInstance Win32_BaseBoard -ErrorAction Stop | Select-Object Manufacturer,Product,Version
}

$cpu = Invoke-Safe -Section 'CPU' -Script {
    Get-CimInstance Win32_Processor -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Name                    = ([string]$_.Name).Trim()
            Cores                   = $_.NumberOfCores
            LogicalProcessors       = $_.NumberOfLogicalProcessors
            MaxClockMHz             = $_.MaxClockSpeed
            CurrentClockMHz         = $_.CurrentClockSpeed
            VirtualizationFirmware  = $_.VirtualizationFirmwareEnabled
        }
    }
}

$memoryModules = @(Invoke-Safe -Section 'MemoryModules' -Script {
    Get-CimInstance Win32_PhysicalMemory -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            DeviceLocator       = $_.DeviceLocator
            BankLabel           = $_.BankLabel
            CapacityGB          = Convert-ToGB $_.Capacity
            SpeedMTs            = $_.Speed
            ConfiguredSpeedMTs  = $_.ConfiguredClockSpeed
            Manufacturer        = ([string]$_.Manufacturer).Trim()
            PartNumber          = ([string]$_.PartNumber).Trim()
            FormFactor          = $_.FormFactor
        }
    }
})

$memoryArrays = @(Invoke-Safe -Section 'MemoryArrays' -Script {
    Get-CimInstance Win32_PhysicalMemoryArray -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            MemoryDevices = $_.MemoryDevices
            MaxCapacityGB = if ($_.MaxCapacityEx) { [math]::Round($_.MaxCapacityEx / 1MB, 2) } else { [math]::Round($_.MaxCapacity / 1MB, 2) }
        }
    }
})

$validMemoryModules = @($memoryModules | Where-Object { $_.PSObject.Properties.Name -contains 'CapacityGB' })
$validMemoryArrays = @($memoryArrays | Where-Object { $_.PSObject.Properties.Name -contains 'MemoryDevices' })
$memoryCapacitySum = ($validMemoryModules | Measure-Object -Property CapacityGB -Sum).Sum
$reportedSlotSum = ($validMemoryArrays | Measure-Object -Property MemoryDevices -Sum).Sum
$memorySummary = [pscustomobject]@{
    PopulatedModules         = $validMemoryModules.Count
    ReportedSlots            = if ($validMemoryArrays.Count) { $reportedSlotSum } else { $null }
    TotalCapacityGB          = if ($validMemoryModules.Count) { [math]::Round($memoryCapacitySum, 2) } else { $null }
    ConfiguredSpeedsMTs      = @($validMemoryModules | Where-Object ConfiguredSpeedMTs | Select-Object -ExpandProperty ConfiguredSpeedMTs -Unique)
    ChannelModeAuthoritative = $false
    ChannelModeNote          = 'SMBIOS slot data is not authoritative for channel mode; verify with UEFI, HWiNFO, or CPU-Z and the exact board manual.'
}

$videoControllers = @(Invoke-Safe -Section 'VideoControllers' -Script {
    Get-CimInstance Win32_VideoController -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Name                        = $_.Name
            DriverVersion               = $_.DriverVersion
            DriverDate                  = $_.DriverDate
            VideoProcessor              = $_.VideoProcessor
            CurrentHorizontalResolution = $_.CurrentHorizontalResolution
            CurrentVerticalResolution   = $_.CurrentVerticalResolution
            CurrentRefreshRate          = $_.CurrentRefreshRate
            Status                      = $_.Status
        }
    }
})

$nvidia = [ordered]@{ Available = $false }
$nvidiaCommand = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
if ($nvidiaCommand) {
    $nvidia.Available = $true
    $nvidia.Path = $nvidiaCommand.Source
    $queryFields = 'name,driver_version,pci.bus_id,pcie.link.gen.current,pcie.link.gen.max,pcie.link.width.current,pcie.link.width.max,temperature.gpu,utilization.gpu,memory.total,memory.used,power.draw,power.limit,clocks.gr,clocks.mem'
    $query = Invoke-NativeText -FilePath $nvidiaCommand.Source -Arguments @("--query-gpu=$queryFields", '--format=csv,noheader,nounits')
    if ($query.ExitCode -ne 0) {
        $query = Invoke-NativeText -FilePath $nvidiaCommand.Source -Arguments @('--query-gpu=name,driver_version,pci.bus_id,temperature.gpu,utilization.gpu,memory.total,memory.used,power.draw,clocks.gr,clocks.mem', '--format=csv,noheader,nounits')
    }
    $pci = Invoke-NativeText -FilePath $nvidiaCommand.Source -Arguments @('-q', '-d', 'PCI')
    $full = Invoke-NativeText -FilePath $nvidiaCommand.Source -Arguments @('-q')
    $nvidia.Telemetry = $query
    $nvidia.Pci = $pci
    $nvidia.RebarAndLinkLines = if ($full.Output) {
        @(($full.Output -split "`r?`n") | Where-Object { $_ -match 'Resizable BAR|BAR1 Memory|Current Link|Max Link|Link Width|Link Gen' } | ForEach-Object Trim)
    } else { @() }
}

$monitors = @(Invoke-Safe -Section 'Monitors' -Script {
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Manufacturer = Convert-MonitorText $_.ManufacturerName
            ProductCode  = Convert-MonitorText $_.ProductCodeID
            FriendlyName = Convert-MonitorText $_.UserFriendlyName
            Active       = $_.Active
        }
    }
})

$physicalDisks = @(Invoke-Safe -Section 'PhysicalDisks' -Script {
    Get-PhysicalDisk -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            FriendlyName      = $_.FriendlyName
            MediaType         = $_.MediaType
            BusType           = $_.BusType
            HealthStatus      = $_.HealthStatus
            OperationalStatus = [string]$_.OperationalStatus
            SizeGB            = Convert-ToGB $_.Size
            FirmwareVersion   = $_.FirmwareVersion
        }
    }
})

$volumes = @(Invoke-Safe -Section 'Volumes' -Script {
    Get-Volume -ErrorAction Stop | Where-Object DriveLetter | ForEach-Object {
        [pscustomobject]@{
            DriveLetter  = $_.DriveLetter
            FileSystem   = $_.FileSystem
            HealthStatus = $_.HealthStatus
            SizeGB       = Convert-ToGB $_.Size
            FreeGB       = Convert-ToGB $_.SizeRemaining
            FreePercent  = if ($_.Size) { [math]::Round($_.SizeRemaining * 100.0 / $_.Size, 1) } else { $null }
        }
    }
})

$power = [ordered]@{
    ActiveScheme = (Invoke-NativeText -FilePath "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/getactivescheme'))
    FastStartup  = Get-RegistryValues 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power'
}

$gamingSettings = [ordered]@{
    GameConfigStore = Get-RegistryValues 'HKCU:\System\GameConfigStore'
    GameBar         = Get-RegistryValues 'HKCU:\Software\Microsoft\GameBar'
    GameDVR         = Get-RegistryValues 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'
    GameDVRPolicy   = Get-RegistryValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
    GraphicsDrivers = Get-RegistryValues 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
}

$deviceGuard = Invoke-Safe -Section 'DeviceGuard' -Script {
    Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop |
        Select-Object VirtualizationBasedSecurityStatus,SecurityServicesConfigured,SecurityServicesRunning,AvailableSecurityProperties,RequiredSecurityProperties
}

$defender = Invoke-Safe -Section 'Defender' -Script {
    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        return [pscustomobject]@{ Available = $false }
    }
    Get-MpComputerStatus | Select-Object AMServiceEnabled,AntivirusEnabled,AntispywareEnabled,BehaviorMonitorEnabled,IoavProtectionEnabled,IsTamperProtected,RealTimeProtectionEnabled,AntivirusSignatureVersion,AntivirusSignatureLastUpdated,QuickScanAge,FullScanAge
}

$secureBoot = Invoke-Safe -Section 'SecureBoot' -Script { Confirm-SecureBootUEFI -ErrorAction Stop }

$pageFile = [ordered]@{
    Management = Get-RegistryValues 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
    Usage = @(Invoke-Safe -Section 'PageFileUsage' -Script {
        Get-CimInstance Win32_PageFileUsage -ErrorAction Stop | Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage
    })
}

$wuServices = @(Invoke-Safe -Section 'WindowsUpdateServices' -Script {
    Get-CimInstance Win32_Service -ErrorAction Stop | Where-Object { $_.Name -in @('wuauserv','BITS','UsoSvc','WaaSMedicSvc','DoSvc') } |
        Select-Object Name,State,StartMode,PathName
})

$wuTasks = @(Invoke-Safe -Section 'WindowsUpdateTasks' -Script {
    Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -match 'WindowsUpdate|UpdateOrchestrator' } | ForEach-Object {
        [pscustomobject]@{
            TaskName = $_.TaskName
            TaskPath = $_.TaskPath
            State    = [string]$_.State
            Enabled  = $_.Settings.Enabled
        }
    }
})

$windowsUpdate = [ordered]@{
    Policy             = Get-RegistryValues 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    UXSettings         = Get-RegistryValues 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings'
    CBSRebootPending   = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
    WURebootRequired   = Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    Services           = $wuServices
    Tasks              = $wuTasks
    RecentHotFixes     = @(Invoke-Safe -Section 'HotFixes' -Script { Get-HotFix -ErrorAction Stop | Sort-Object InstalledOn -Descending | Select-Object -First 25 HotFixID,Description,InstalledOn })
}

if ($IncludeUpdateScan) {
    if ($fortniteRunning) {
        $windowsUpdate.AvailableUpdates = [pscustomobject]@{ Skipped = 'Fortnite is running; update scan skipped to avoid background load.' }
    } else {
        $windowsUpdate.AvailableUpdates = Invoke-Safe -Section 'UpdateScan' -Script {
            $session = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $search = $searcher.Search('IsInstalled=0 and IsHidden=0')
            $items = for ($i = 0; $i -lt $search.Updates.Count; $i++) {
                $update = $search.Updates.Item($i)
                [pscustomobject]@{
                    Title       = $update.Title
                    Type        = [string]$update.Type
                    AutoSelect  = $update.AutoSelectOnWebSites
                    Mandatory   = $update.IsMandatory
                }
            }
            [pscustomobject]@{ ResultCode = [string]$search.ResultCode; Count = $search.Updates.Count; Updates = @($items) }
        }
    }
}

$startupCommands = @(Invoke-Safe -Section 'StartupCommands' -Script {
    Get-CimInstance Win32_StartupCommand -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Name     = $_.Name
            Location = $_.Location
            User     = $_.User
            Command  = Protect-LocalText $_.Command
        }
    }
})

$nonMicrosoftTasks = @(Invoke-Safe -Section 'NonMicrosoftScheduledTasks' -Script {
    Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' } | Select-Object -First 200 | ForEach-Object {
        $actions = @($_.Actions | ForEach-Object { (Protect-LocalText (($_.Execute, $_.Arguments -join ' '))).Trim() })
        [pscustomobject]@{
            TaskName = $_.TaskName
            TaskPath = $_.TaskPath
            State    = [string]$_.State
            Enabled  = $_.Settings.Enabled
            Actions  = $actions
        }
    }
})

$processes = @(Invoke-Safe -Section 'Processes' -Script {
    Get-Process -ErrorAction Stop | Sort-Object CPU -Descending | Select-Object -First 60 | ForEach-Object {
        $path = $null
        try { $path = Protect-LocalText $_.Path } catch {}
        [pscustomobject]@{
            Name         = $_.ProcessName
            Id           = $_.Id
            CPUSeconds   = if ($null -ne $_.CPU) { [math]::Round($_.CPU, 2) } else { $null }
            WorkingSetMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
            Threads      = $_.Threads.Count
            Priority     = [string]$_.PriorityClass
            Path         = $path
        }
    }
})

$impactPattern = 'Fortnite|EpicGames|EasyAntiCheat|chrome|msedge|firefox|zen|obs|streamlabs|discord|steam|overwolf|NVIDIA Share|nvcontainer|GameBar|Xbox|BlueStacks|HD-Player|Nox|LDPlayer|MEmu|Android|Wallpaper|Armoury|iCUE|Razer|Logitech'
$impactProcesses = @($processes | Where-Object { $_.Name -match $impactPattern })
$autoBrowserEntries = @($startupCommands | Where-Object { ($_.Name + ' ' + $_.Command) -match 'chrome|msedge|waze|https?://' })

$networkAdapters = @(Invoke-Safe -Section 'NetworkAdapters' -Script {
    Get-NetAdapter -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Name                 = $_.Name
            InterfaceDescription = $_.InterfaceDescription
            Status               = [string]$_.Status
            LinkSpeed            = $_.LinkSpeed
            MediaType            = [string]$_.MediaType
            DriverInformation    = $_.DriverInformation
        }
    }
})

$networkConfiguration = @(Invoke-Safe -Section 'NetworkConfiguration' -Script {
    Get-NetIPConfiguration -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            InterfaceAlias = $_.InterfaceAlias
            IPv4Gateway    = @($_.IPv4DefaultGateway.NextHop)
            DnsServers     = @($_.DNSServer.ServerAddresses)
        }
    }
})

$nicAdvanced = @(Invoke-Safe -Section 'NicAdvancedProperties' -Script {
    Get-NetAdapterAdvancedProperty -ErrorAction Stop | Where-Object { $_.DisplayName } |
        Select-Object Name,DisplayName,DisplayValue,RegistryKeyword
})

$nicPower = @(Invoke-Safe -Section 'NicPowerManagement' -Script {
    Get-NetAdapterPowerManagement -ErrorAction Stop | Select-Object Name,AllowComputerToTurnOffDevice,WakeOnMagicPacket,WakeOnPattern
})

$hostsFlags = @(Invoke-Safe -Section 'HostsFile' -Script {
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    Get-Content -LiteralPath $hostsPath -ErrorAction Stop | Where-Object {
        $_ -notmatch '^\s*(#|$)' -and $_ -match 'epic|fortnite|microsoft|windowsupdate|nvidia'
    }
})

$gatewayTargets = @($networkConfiguration | ForEach-Object IPv4Gateway | Where-Object { $_ } | Select-Object -Unique)
$allPingTargets = @($gatewayTargets + $PingTargets | Where-Object { $_ } | Select-Object -Unique)
$pingResults = @($allPingTargets | ForEach-Object { Get-PingSummary -Target $_ -Count $PingCount })

$network = [ordered]@{
    Adapters          = $networkAdapters
    Configuration     = $networkConfiguration
    AdvancedProperties = $nicAdvanced
    PowerManagement   = $nicPower
    TcpGlobal         = Invoke-NativeText -FilePath "$env:SystemRoot\System32\netsh.exe" -Arguments @('interface','tcp','show','global')
    WinHttpProxy      = Invoke-NativeText -FilePath "$env:SystemRoot\System32\netsh.exe" -Arguments @('winhttp','show','proxy')
    HostsRelevantLines = $hostsFlags
    Ping              = $pingResults
}

$epicManifests = @(Invoke-Safe -Section 'EpicManifests' -Script {
    $manifestRoot = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (-not (Test-Path -LiteralPath $manifestRoot)) { return @() }
    foreach ($file in Get-ChildItem -LiteralPath $manifestRoot -Filter '*.item' -File -ErrorAction SilentlyContinue) {
        try {
            $manifest = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if (($manifest.DisplayName -match 'Fortnite') -or ($manifest.AppName -match 'Fortnite')) {
                [pscustomobject]@{
                    DisplayName    = $manifest.DisplayName
                    AppName        = $manifest.AppName
                    AppVersion     = $manifest.AppVersionString
                    InstallLocation = Protect-LocalText $manifest.InstallLocation
                    LaunchExecutable = $manifest.LaunchExecutable
                }
            }
        } catch {}
    }
})

$fortniteConfigRoot = Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Config'
$fortniteConfigs = @(Invoke-Safe -Section 'FortniteConfig' -Script {
    if (-not (Test-Path -LiteralPath $fortniteConfigRoot)) { return @() }
    Get-ChildItem -LiteralPath $fortniteConfigRoot -Recurse -Filter 'GameUserSettings.ini' -File -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            Path             = Protect-LocalText $_.FullName
            LastWriteTime    = $_.LastWriteTime
            SizeBytes        = $_.Length
            IsReadOnly       = [bool]($_.Attributes -band [IO.FileAttributes]::ReadOnly)
            SHA256           = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            SelectedSettings = Get-IniSelection -Path $_.FullName
        }
    }
})

$replayInfo = Invoke-Safe -Section 'Replays' -Script {
    $demoRoot = Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Demos'
    if (-not (Test-Path -LiteralPath $demoRoot)) { return [pscustomobject]@{ Exists = $false } }
    $files = @(Get-ChildItem -LiteralPath $demoRoot -File -Recurse -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        Exists        = $true
        FileCount     = $files.Count
        TotalSizeGB   = [math]::Round((($files | Measure-Object Length -Sum).Sum / 1GB), 3)
        NewestWrite   = ($files | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
    }
}

$latestFortniteLog = Invoke-Safe -Section 'FortniteLogs' -Script {
    $logRoot = Join-Path $env:LOCALAPPDATA 'FortniteGame\Saved\Logs'
    if (-not (Test-Path -LiteralPath $logRoot)) { return $null }
    Get-ChildItem -LiteralPath $logRoot -File -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1 |
        ForEach-Object { [pscustomobject]@{ Path = Protect-LocalText $_.FullName; LastWriteTime = $_.LastWriteTime; SizeMB = [math]::Round($_.Length / 1MB, 2) } }
}

$fortnite = [ordered]@{
    Running          = $fortniteRunning
    Processes        = @($fortniteProcesses | ForEach-Object { [pscustomobject]@{ Name = $_.ProcessName; Id = $_.Id; WorkingSetMB = [math]::Round($_.WorkingSet64 / 1MB, 1); StartTime = try { $_.StartTime } catch { $null } } })
    EpicManifests    = $epicManifests
    Configs          = $fortniteConfigs
    Replays          = $replayInfo
    LatestLog        = $latestFortniteLog
}

$since = (Get-Date).AddDays(-7)
$systemEvents = @(Invoke-Safe -Section 'SystemEvents' -Script {
    $interesting = 'WHEA-Logger|Disk|stornvme|storahci|Display|nvlddmkm|Kernel-Power|volmgr'
    Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $since; Level = @(1,2,3) } -MaxEvents 1500 -ErrorAction Stop |
        Where-Object ProviderName -match $interesting | Select-Object -First 100 | ForEach-Object {
            $message = ($_.Message -replace '\s+', ' ').Trim()
            if ($message.Length -gt 700) { $message = $message.Substring(0,700) + '…' }
            [pscustomobject]@{ TimeCreated = $_.TimeCreated; Provider = $_.ProviderName; Id = $_.Id; Level = $_.LevelDisplayName; Message = $message }
        }
})

$applicationEvents = @(Invoke-Safe -Section 'ApplicationEvents' -Script {
    Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since; Level = @(1,2,3) } -MaxEvents 1500 -ErrorAction Stop |
        Where-Object { $_.ProviderName -match 'Application Error|Windows Error Reporting' -and $_.Message -match 'Fortnite|EpicGames|EasyAntiCheat' } |
        Select-Object -First 100 | ForEach-Object {
            $message = ($_.Message -replace '\s+', ' ').Trim()
            if ($message.Length -gt 700) { $message = $message.Substring(0,700) + '…' }
            [pscustomobject]@{ TimeCreated = $_.TimeCreated; Provider = $_.ProviderName; Id = $_.Id; Level = $_.LevelDisplayName; Message = $message }
        }
})

$servicingHealth = $null
if ($IncludeServicingHealth) {
    if ($fortniteRunning) {
        $servicingHealth = [pscustomobject]@{ Skipped = 'Fortnite is running; DISM/SFC checks were skipped to avoid background load.' }
    } else {
        $servicingHealth = [ordered]@{
            DISMCheckHealth = Invoke-NativeText -FilePath "$env:SystemRoot\System32\dism.exe" -Arguments @('/Online','/Cleanup-Image','/CheckHealth')
            SFCVerifyOnly    = Invoke-NativeText -FilePath "$env:SystemRoot\System32\sfc.exe" -Arguments @('/VerifyOnly')
        }
    }
}

$report = [ordered]@{
    Meta = [ordered]@{
        GeneratedAt       = Get-Date
        ComputerName      = $env:COMPUTERNAME
        PowerShellVersion = $PSVersionTable.PSVersion.ToString()
        IsAdministrator   = $isAdmin
        ReadOnlyAudit     = $true
        OutputDirectory   = Protect-LocalText $OutputDirectory
        PrivacyNote       = 'No product keys, hardware serial numbers, MAC address, or public IP were intentionally collected. Report remains local unless the user chooses to share it.'
    }
    System              = $osAndSystem
    BIOS                = $bios
    BaseBoard           = $baseBoard
    CPU                 = $cpu
    Memory              = [ordered]@{ Summary = $memorySummary; Modules = $memoryModules; Arrays = $memoryArrays }
    VideoControllers    = $videoControllers
    Nvidia              = [pscustomobject]$nvidia
    Monitors            = $monitors
    Storage             = [ordered]@{ PhysicalDisks = $physicalDisks; Volumes = $volumes }
    Power               = [pscustomobject]$power
    GamingSettings      = [pscustomobject]$gamingSettings
    Security            = [ordered]@{ DeviceGuard = $deviceGuard; Defender = $defender; SecureBoot = $secureBoot }
    PageFile            = [pscustomobject]$pageFile
    WindowsUpdate       = [pscustomobject]$windowsUpdate
    Startup             = [ordered]@{ Commands = $startupCommands; NonMicrosoftTasks = $nonMicrosoftTasks; BrowserOrUrlEntries = $autoBrowserEntries }
    Processes           = [ordered]@{ Top = $processes; PotentialGamingImpact = $impactProcesses }
    Network             = [pscustomobject]$network
    Fortnite            = [pscustomobject]$fortnite
    Events              = [ordered]@{ System = $systemEvents; Application = $applicationEvents }
    ServicingHealth     = $servicingHealth
}

$jsonPath = Join-Path $OutputDirectory 'fortnite-audit.json'
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Fortnite PC audit')
$md.Add('')
$md.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')")
$md.Add('')
$md.Add('This audit is read-only except for writing this report directory.')
$md.Add('')
$md.Add('## Snapshot')
$md.Add('')
$md.Add("- Administrator: $isAdmin")
$md.Add("- Fortnite running: $fortniteRunning")
$md.Add("- Windows: $($osAndSystem.Caption) $($osAndSystem.DisplayVersion), build $($osAndSystem.Build), edition $($osAndSystem.EditionID)")
$md.Add("- CPU: $(@($cpu | ForEach-Object Name) -join '; ')")
$md.Add("- RAM: $($memorySummary.TotalCapacityGB) GB in $($memorySummary.PopulatedModules) module(s); reported slots: $($memorySummary.ReportedSlots); configured MT/s: $($memorySummary.ConfiguredSpeedsMTs -join ', ')")
$md.Add("- GPU: $(@($videoControllers | ForEach-Object Name) -join '; ')")
$displayModes = @($videoControllers | Where-Object CurrentHorizontalResolution | ForEach-Object { "$($_.CurrentHorizontalResolution)x$($_.CurrentVerticalResolution)@$($_.CurrentRefreshRate)Hz" })
$md.Add("- Active display mode(s): $($displayModes -join '; ')")
$md.Add("- Windows Update policy key present: $($null -ne $windowsUpdate.Policy)")
$md.Add("- Reboot pending (CBS/WU): $($windowsUpdate.CBSRebootPending)/$($windowsUpdate.WURebootRequired)")
$md.Add('')
$md.Add('## Files')
$md.Add('')
$md.Add("- Full machine-readable report: $jsonPath")
$md.Add('- Review JSON for DIMM locations, PCIe data, ReBAR lines, processes, startup entries, Fortnite settings, storage, network, events, and optional servicing checks.')
$md.Add('')
$md.Add('## Interpretation guardrails')
$md.Add('')
$md.Add('- SMBIOS does not prove dual-channel mode; verify with UEFI/HWiNFO/CPU-Z and the board manual.')
$md.Add('- PCIe generation may downshift at idle; confirm current width/generation under GPU load.')
$md.Add('- This report does not contain FPS/frametime. Pair it with Fortnite stats, PresentMon, or CapFrameX and the session-capture script.')

$markdownPath = Join-Path $OutputDirectory 'SUMMARY.md'
$md | Set-Content -LiteralPath $markdownPath -Encoding UTF8

[pscustomobject]@{
    OutputDirectory = $OutputDirectory
    JsonReport      = $jsonPath
    Summary         = $markdownPath
    FortniteRunning = $fortniteRunning
    IsAdministrator = $isAdmin
}
