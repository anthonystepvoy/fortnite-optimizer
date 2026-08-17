[CmdletBinding()]
param(
    [ValidateRange(10, 3600)]
    [int]$DurationSeconds = 180,
    [ValidateRange(1, 10)]
    [int]$IntervalSeconds = 1,
    [string]$OutputDirectory,
    [string]$PingTarget,
    [string]$ProcessNamePattern = 'FortniteClient*'
)

$ErrorActionPreference = 'Continue'

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Get-Location) ('Fortnite-Session-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
$OutputDirectory = [System.IO.Path]::GetFullPath($OutputDirectory)

function Convert-InvariantNumber {
    param($Text)
    if ($null -eq $Text) { return $null }
    $value = 0.0
    $ok = [double]::TryParse(
        ([string]$Text).Trim(),
        [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture,
        [ref]$value
    )
    if ($ok) { return $value }
    return $null
}

function Get-Percentile {
    param([double[]]$Values, [double]$Percentile)
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $index = [math]::Ceiling(($Percentile / 100) * $sorted.Count) - 1
    $index = [math]::Max(0, [math]::Min($index, $sorted.Count - 1))
    [math]::Round([double]$sorted[$index], 2)
}

function Get-Stats {
    param([object[]]$Samples, [string]$Property)
    $values = @($Samples | ForEach-Object { $_.$Property } | Where-Object { $null -ne $_ } | ForEach-Object { [double]$_ })
    if ($values.Count -eq 0) { return $null }
    $measure = $values | Measure-Object -Average -Minimum -Maximum
    [pscustomobject]@{
        Count   = $values.Count
        Average = [math]::Round($measure.Average, 2)
        Minimum = [math]::Round($measure.Minimum, 2)
        Maximum = [math]::Round($measure.Maximum, 2)
        P95     = Get-Percentile -Values $values -Percentile 95
        P99     = Get-Percentile -Values $values -Percentile 99
    }
}

function Get-NvidiaSample {
    param([string]$NvidiaSmiPath)
    if ([string]::IsNullOrWhiteSpace($NvidiaSmiPath)) { return $null }
    try {
        $fields = 'utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw,clocks.gr,clocks.mem,pcie.link.gen.current,pcie.link.width.current'
        $line = (& $NvidiaSmiPath "--query-gpu=$fields" '--format=csv,noheader,nounits' 2>$null | Select-Object -First 1)
        if (-not $line) { return $null }
        $parts = @($line -split ',' | ForEach-Object Trim)
        if ($parts.Count -lt 9) { return $null }
        [pscustomobject]@{
            GpuUtilizationPct = Convert-InvariantNumber $parts[0]
            GpuMemoryUsedMB   = Convert-InvariantNumber $parts[1]
            GpuMemoryTotalMB  = Convert-InvariantNumber $parts[2]
            GpuTemperatureC   = Convert-InvariantNumber $parts[3]
            GpuPowerW         = Convert-InvariantNumber $parts[4]
            GpuClockMHz       = Convert-InvariantNumber $parts[5]
            GpuMemoryClockMHz = Convert-InvariantNumber $parts[6]
            PcieGeneration    = Convert-InvariantNumber $parts[7]
            PcieWidth         = Convert-InvariantNumber $parts[8]
        }
    } catch {
        return $null
    }
}

function Get-OnePing {
    param([string]$Target)
    if ([string]::IsNullOrWhiteSpace($Target)) { return $null }
    try {
        $reply = Test-Connection -ComputerName $Target -Count 1 -ErrorAction Stop | Select-Object -First 1
        if ($reply.PSObject.Properties.Name -contains 'Latency') { return [double]$reply.Latency }
        if ($reply.PSObject.Properties.Name -contains 'ResponseTime') { return [double]$reply.ResponseTime }
        return $null
    } catch {
        return $null
    }
}

$game = Get-Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ProcessName -like $ProcessNamePattern } |
    Sort-Object WorkingSet64 -Descending |
    Select-Object -First 1

if (-not $game) {
    Write-Error "No process matched '$ProcessNamePattern'. Start Fortnite and rerun with the default pattern; no process was changed."
    exit 2
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

$logicalProcessors = [Environment]::ProcessorCount
try {
    $computerSystem = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
    if ($computerSystem.NumberOfLogicalProcessors) { $logicalProcessors = [int]$computerSystem.NumberOfLogicalProcessors }
} catch {}

$nvidiaCommand = Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
$nvidiaPath = if ($nvidiaCommand) { $nvidiaCommand.Source } else { $null }

$startTime = Get-Date
$endTime = $startTime.AddSeconds($DurationSeconds)
$previousCpuSeconds = [double]$game.CPU
$previousSampleTime = $startTime
$samples = New-Object System.Collections.Generic.List[object]
$gameExitedEarly = $false

Write-Host "Capturing Fortnite PID $($game.Id) for $DurationSeconds seconds. No priority, affinity, or game setting will be changed."

while ((Get-Date) -lt $endTime) {
    Start-Sleep -Seconds $IntervalSeconds
    $now = Get-Date
    $current = Get-Process -Id $game.Id -ErrorAction SilentlyContinue
    if (-not $current) {
        $gameExitedEarly = $true
        break
    }

    $elapsed = [math]::Max(0.001, ($now - $previousSampleTime).TotalSeconds)
    $currentCpuSeconds = [double]$current.CPU
    $cpuDelta = [math]::Max(0, $currentCpuSeconds - $previousCpuSeconds)
    $equivalentCores = $cpuDelta / $elapsed
    $processCpuPctTotalCapacity = ($equivalentCores / $logicalProcessors) * 100.0

    $cpuTotal = $null
    $maxLogicalProcessor = $null
    try {
        $cpuRows = @(Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -ErrorAction Stop)
        $totalRow = $cpuRows | Where-Object Name -eq '_Total' | Select-Object -First 1
        $coreRows = @($cpuRows | Where-Object Name -ne '_Total')
        if ($totalRow) { $cpuTotal = [double]$totalRow.PercentProcessorTime }
        if ($coreRows.Count) { $maxLogicalProcessor = [double](($coreRows | Measure-Object PercentProcessorTime -Maximum).Maximum) }
    } catch {}

    $availableMemoryMB = $null
    try {
        $memoryPerf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction Stop
        $availableMemoryMB = [double]$memoryPerf.AvailableMBytes
    } catch {}

    $diskActivePct = $null
    $diskQueue = $null
    $diskBytesPerSec = $null
    try {
        $diskPerf = Get-CimInstance Win32_PerfFormattedData_PerfDisk_PhysicalDisk -ErrorAction Stop | Where-Object Name -eq '_Total' | Select-Object -First 1
        if ($diskPerf) {
            $diskActivePct = [double]$diskPerf.PercentDiskTime
            $diskQueue = [double]$diskPerf.AvgDiskQueueLength
            $diskBytesPerSec = [double]($diskPerf.DiskBytesPersec)
        }
    } catch {}

    $networkBytesPerSec = $null
    try {
        $networkPerf = @(Get-CimInstance Win32_PerfFormattedData_Tcpip_NetworkInterface -ErrorAction Stop)
        if ($networkPerf.Count) { $networkBytesPerSec = [double](($networkPerf | Measure-Object BytesTotalPersec -Sum).Sum) }
    } catch {}

    $gpu = Get-NvidiaSample -NvidiaSmiPath $nvidiaPath
    $pingMs = Get-OnePing -Target $PingTarget

    $sample = [pscustomobject]@{
        Timestamp                  = $now.ToString('o')
        ElapsedSeconds             = [math]::Round(($now - $startTime).TotalSeconds, 2)
        ProcessId                  = $current.Id
        ProcessCpuPctTotalCapacity = [math]::Round($processCpuPctTotalCapacity, 2)
        ProcessEquivalentCores     = [math]::Round($equivalentCores, 2)
        SystemCpuPct               = if ($null -ne $cpuTotal) { [math]::Round($cpuTotal, 2) } else { $null }
        MaxLogicalProcessorPct     = if ($null -ne $maxLogicalProcessor) { [math]::Round($maxLogicalProcessor, 2) } else { $null }
        WorkingSetMB               = [math]::Round($current.WorkingSet64 / 1MB, 2)
        PrivateMemoryMB            = [math]::Round($current.PrivateMemorySize64 / 1MB, 2)
        ThreadCount                = $current.Threads.Count
        HandleCount                = $current.HandleCount
        AvailableMemoryMB          = $availableMemoryMB
        DiskActivePct              = $diskActivePct
        DiskQueueLength            = $diskQueue
        DiskMBPerSec               = if ($null -ne $diskBytesPerSec) { [math]::Round($diskBytesPerSec / 1MB, 2) } else { $null }
        NetworkMbps                = if ($null -ne $networkBytesPerSec) { [math]::Round(($networkBytesPerSec * 8) / 1MB, 3) } else { $null }
        PingMs                     = $pingMs
        GpuUtilizationPct          = if ($gpu) { $gpu.GpuUtilizationPct } else { $null }
        GpuMemoryUsedMB            = if ($gpu) { $gpu.GpuMemoryUsedMB } else { $null }
        GpuMemoryTotalMB           = if ($gpu) { $gpu.GpuMemoryTotalMB } else { $null }
        GpuTemperatureC            = if ($gpu) { $gpu.GpuTemperatureC } else { $null }
        GpuPowerW                  = if ($gpu) { $gpu.GpuPowerW } else { $null }
        GpuClockMHz                = if ($gpu) { $gpu.GpuClockMHz } else { $null }
        GpuMemoryClockMHz          = if ($gpu) { $gpu.GpuMemoryClockMHz } else { $null }
        PcieGeneration             = if ($gpu) { $gpu.PcieGeneration } else { $null }
        PcieWidth                  = if ($gpu) { $gpu.PcieWidth } else { $null }
    }
    $samples.Add($sample)

    $previousCpuSeconds = $currentCpuSeconds
    $previousSampleTime = $now
}

$actualEndTime = Get-Date
$csvPath = Join-Path $OutputDirectory 'fortnite-session-samples.csv'
$samples | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

$properties = @(
    'ProcessCpuPctTotalCapacity','ProcessEquivalentCores','SystemCpuPct','MaxLogicalProcessorPct',
    'WorkingSetMB','PrivateMemoryMB','AvailableMemoryMB','DiskActivePct','DiskQueueLength',
    'DiskMBPerSec','NetworkMbps','PingMs','GpuUtilizationPct','GpuMemoryUsedMB',
    'GpuTemperatureC','GpuPowerW','GpuClockMHz','GpuMemoryClockMHz','PcieGeneration','PcieWidth'
)
$statistics = [ordered]@{}
foreach ($property in $properties) {
    $statistics[$property] = Get-Stats -Samples $samples -Property $property
}

$eventProviders = 'WHEA-Logger|Disk|stornvme|storahci|Display|nvlddmkm|Kernel-Power|volmgr'
$systemEvents = @()
try {
    $systemEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $startTime; Level = @(1,2,3) } -MaxEvents 500 -ErrorAction Stop |
        Where-Object ProviderName -match $eventProviders | ForEach-Object {
            $message = ($_.Message -replace '\s+', ' ').Trim()
            if ($message.Length -gt 600) { $message = $message.Substring(0,600) + '…' }
            [pscustomobject]@{ TimeCreated = $_.TimeCreated; Provider = $_.ProviderName; Id = $_.Id; Level = $_.LevelDisplayName; Message = $message }
        })
} catch {}

$applicationEvents = @()
try {
    $applicationEvents = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $startTime; Level = @(1,2,3) } -MaxEvents 500 -ErrorAction Stop |
        Where-Object { $_.ProviderName -match 'Application Error|Windows Error Reporting' -and $_.Message -match 'Fortnite|EpicGames|EasyAntiCheat' } | ForEach-Object {
            $message = ($_.Message -replace '\s+', ' ').Trim()
            if ($message.Length -gt 600) { $message = $message.Substring(0,600) + '…' }
            [pscustomobject]@{ TimeCreated = $_.TimeCreated; Provider = $_.ProviderName; Id = $_.Id; Level = $_.LevelDisplayName; Message = $message }
        })
} catch {}

$summary = [ordered]@{
    Meta = [ordered]@{
        StartedAt          = $startTime
        EndedAt            = $actualEndTime
        RequestedSeconds   = $DurationSeconds
        ActualSeconds      = [math]::Round(($actualEndTime - $startTime).TotalSeconds, 2)
        IntervalSeconds    = $IntervalSeconds
        SampleCount        = $samples.Count
        FortniteProcess    = $game.ProcessName
        FortniteProcessId  = $game.Id
        LogicalProcessors  = $logicalProcessors
        NvidiaSmiAvailable = [bool]$nvidiaPath
        PingTarget         = $PingTarget
        GameExitedEarly    = $gameExitedEarly
        ReadOnlyCapture    = $true
    }
    Statistics = [pscustomobject]$statistics
    Events = [ordered]@{
        System      = $systemEvents
        Application = $applicationEvents
    }
    Limitations = @(
        'This capture does not measure FPS or frame time.',
        'Correlate timestamps with Fortnite statistics, PresentMon, or CapFrameX.',
        'Process CPU percentage is normalized to total logical-processor capacity; equivalent cores is often easier to interpret.',
        'A max logical processor near 100% with low GPU use is consistent with a game-thread/CPU bottleneck but still requires frame-time correlation.'
    )
}

$jsonPath = Join-Path $OutputDirectory 'fortnite-session-summary.json'
$summary | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Fortnite session capture')
$md.Add('')
$md.Add("- Process: $($game.ProcessName) (PID $($game.Id))")
$md.Add("- Window: $startTime to $actualEndTime")
$md.Add("- Samples: $($samples.Count), interval: $IntervalSeconds s")
$md.Add("- Game exited early: $gameExitedEarly")
$md.Add("- NVIDIA telemetry: $([bool]$nvidiaPath)")
$md.Add("- Ping target: $PingTarget")
$md.Add('')
$md.Add('## Key statistics')
$md.Add('')
$md.Add('| Metric | Average | P95 | Maximum |')
$md.Add('|---|---:|---:|---:|')
foreach ($property in @('MaxLogicalProcessorPct','GpuUtilizationPct','GpuTemperatureC','GpuPowerW','AvailableMemoryMB','DiskActivePct','DiskQueueLength','PingMs')) {
    $stat = $statistics[$property]
    if ($stat) { $md.Add("| $property | $($stat.Average) | $($stat.P95) | $($stat.Maximum) |") }
}
$md.Add('')
$md.Add('This script did not change process priority, affinity, game settings, drivers, or Windows settings.')
$md.Add('Pair timestamps in the CSV with an FPS/frametime capture before concluding the bottleneck.')

$markdownPath = Join-Path $OutputDirectory 'SUMMARY.md'
$md | Set-Content -LiteralPath $markdownPath -Encoding UTF8

[pscustomobject]@{
    OutputDirectory = $OutputDirectory
    SamplesCsv      = $csvPath
    SummaryJson     = $jsonPath
    SummaryMarkdown = $markdownPath
    SampleCount     = $samples.Count
    GameExitedEarly = $gameExitedEarly
}
