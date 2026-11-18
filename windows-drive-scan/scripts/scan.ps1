<#
.SYNOPSIS
  Shows where the space on a Windows drive went. Read only.

.DESCRIPTION
  Measures each top-level folder of the drive (and of your user folder), lists the
  largest files and measures common caches. It never deletes, moves, renames or
  changes any file, needs no admin rights and makes no network connections.
  The only thing it writes is its own report, in a dated folder under -OutDir
  (default: your user folder\drive-scan-report). If an earlier report exists
  there, it prints how the used space has changed.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File scan.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File scan.ps1 -Drive D: -Top 20
#>
param(
    [ValidatePattern('^[A-Za-z]:\\?$')][string]$Drive = $env:SystemDrive,
    [ValidateRange(1, 200)][int]$Top = 15,
    [ValidateRange(1, 1000000)][long]$BigFileMB = 500,
    [string]$OutDir = (Join-Path $env:USERPROFILE 'drive-scan-report')
)

Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1TB) { return '{0:N1} TB' -f ($Bytes / 1TB) }
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N0} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N0} KB' -f ($Bytes / 1KB) }
    return "$Bytes bytes"
}

function Get-SumBytes {
    param($Items, [string]$Property = 'Bytes')
    $sum = 0L
    foreach ($i in @($Items)) { if ($null -ne $i) { $sum += [long]$i.$Property } }
    return $sum
}

# Walks a folder tree without following junctions or symbolic links, and skips
# folders it cannot read. Only reads file sizes and dates.
function Invoke-FileWalk {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][scriptblock]$OnFile,
        [string]$Skip = ''
    )
    $skipFull = if ($Skip) { [System.IO.Path]::GetFullPath($Skip).TrimEnd('\') } else { '' }
    $stack = New-Object System.Collections.Stack
    $stack.Push((New-Object System.IO.DirectoryInfo $Root))
    $skipped = 0
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            foreach ($f in $dir.GetFiles()) { $null = & $OnFile $f }
            foreach ($d in $dir.GetDirectories()) {
                if (($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                if ($skipFull -and $d.FullName.TrimEnd('\') -ieq $skipFull) { continue }
                $stack.Push($d)
            }
        } catch {
            $skipped++
        }
    }
    return $skipped
}

$Drive = $Drive.TrimEnd('\').ToUpper()
$driveRoot = "$Drive\"
if (-not (Test-Path -LiteralPath $driveRoot)) { throw "Drive $Drive not found." }

$stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
# The report must stay on this PC: refuse network paths and network drives.
$OutDir = [System.IO.Path]::GetFullPath($OutDir)
if ($OutDir.StartsWith('\\')) { throw "OutDir must be a folder on this PC, not a network path: $OutDir" }
$outDrive = New-Object System.IO.DriveInfo ([System.IO.Path]::GetPathRoot($OutDir))
if ($outDrive.DriveType -eq [System.IO.DriveType]::Network) { throw "OutDir must be a folder on this PC, not a network drive: $OutDir" }
$runDir = Join-Path $OutDir $stamp
$null = [System.IO.Directory]::CreateDirectory($runDir)

$di = New-Object System.IO.DriveInfo $Drive
$used = $di.TotalSize - $di.TotalFreeSpace
Write-Host ("Drive {0} {1} used of {2}, {3} free" -f $Drive, (Format-Size $used), (Format-Size $di.TotalSize), (Format-Size $di.TotalFreeSpace))
Write-Host 'Measuring folders (read only). A full drive can take several minutes...'

$bigFiles = New-Object System.Collections.Generic.List[object]
$bigLimit = $BigFileMB * 1MB

function Measure-Folder {
    param([string]$Path, [string]$Skip = '')
    $script:bytes = 0L
    $script:count = 0L
    $skipped = Invoke-FileWalk -Root $Path -Skip $Skip -OnFile {
        param($f)
        $script:bytes += $f.Length
        $script:count++
        if ($f.Length -ge $bigLimit) {
            $bigFiles.Add([pscustomobject]@{ Path = $f.FullName; Bytes = $f.Length; Size = (Format-Size $f.Length); Modified = $f.LastWriteTime })
        }
    }
    [pscustomobject]@{ Path = $Path; Bytes = $script:bytes; Size = (Format-Size $script:bytes); Files = $script:count; Unreadable = $skipped }
}

# The user folder is measured once, folder by folder. Its parent (usually
# C:\Users) is then measured without it, so no file is counted twice.
$userFolders = @()
$userBytes = 0L; $userFiles = 0L; $userSkipped = 0
$profileOnDrive = $env:USERPROFILE.StartsWith($driveRoot, [System.StringComparison]::OrdinalIgnoreCase)
if ($profileOnDrive) {
    $looseBytes = 0L; $looseFiles = 0L
    foreach ($f in (Get-ChildItem -LiteralPath $env:USERPROFILE -File -Force -ErrorAction SilentlyContinue)) { $looseBytes += $f.Length; $looseFiles++ }
    foreach ($d in (Get-ChildItem -LiteralPath $env:USERPROFILE -Directory -Force -ErrorAction SilentlyContinue)) {
        if (($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        $userFolders += Measure-Folder $d.FullName
    }
    $userBytes = $looseBytes + (Get-SumBytes $userFolders)
    $userFiles = $looseFiles + (Get-SumBytes $userFolders 'Files')
    $userSkipped = Get-SumBytes $userFolders 'Unreadable'
    $userFolders = @($userFolders | Sort-Object Bytes -Descending)
}
$profileParent = Split-Path $env:USERPROFILE -Parent

$folders = @()
foreach ($d in (Get-ChildItem -LiteralPath $driveRoot -Directory -Force -ErrorAction SilentlyContinue)) {
    if (($d.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
    if ($profileOnDrive -and ($d.FullName.TrimEnd('\') -ieq $profileParent.TrimEnd('\'))) {
        $m = Measure-Folder $d.FullName -Skip $env:USERPROFILE
        $total = $m.Bytes + $userBytes
        $folders += [pscustomobject]@{ Path = $m.Path; Bytes = $total; Size = (Format-Size $total); Files = $m.Files + $userFiles; Unreadable = $m.Unreadable + $userSkipped }
    } else {
        $folders += Measure-Folder $d.FullName
    }
}
$folders = @($folders | Sort-Object Bytes -Descending)

# Common caches. Measured only.
$cacheDefs = @(
    @{ Name = 'Your Temp folder'; Path = $env:TEMP },
    @{ Name = 'Windows Temp'; Path = (Join-Path $env:SystemRoot 'Temp') },
    @{ Name = 'Chrome cache'; Path = (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache') },
    @{ Name = 'Edge cache'; Path = (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache') },
    @{ Name = 'Firefox profiles'; Path = (Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles') },
    @{ Name = 'npm cache'; Path = (Join-Path $env:LOCALAPPDATA 'npm-cache') },
    @{ Name = 'pip cache'; Path = (Join-Path $env:LOCALAPPDATA 'pip\Cache') },
    @{ Name = 'Windows Update downloads'; Path = (Join-Path $env:SystemRoot 'SoftwareDistribution\Download') }
)
$caches = @()
foreach ($c in $cacheDefs) {
    if ($c.Path -and (Test-Path -LiteralPath $c.Path)) {
        $m = Measure-Folder $c.Path
        $caches += [pscustomobject]@{ Name = $c.Name; Path = $c.Path; Bytes = $m.Bytes; Size = $m.Size; Unreadable = $m.Unreadable }
    }
}

$bigSorted = @($bigFiles | Sort-Object Bytes -Descending | Select-Object -First $Top)

$result = [pscustomobject]@{
    Scanned = (Get-Date).ToString('s'); Drive = $Drive
    TotalBytes = $di.TotalSize; UsedBytes = $used; FreeBytes = $di.TotalFreeSpace
    Folders = $folders; UserFolders = $userFolders; LargestFiles = $bigSorted; Caches = $caches
}
$result | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $runDir 'scan.json')
$folders | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $runDir 'folders.csv')
$bigSorted | Export-Csv -NoTypeInformation -Encoding UTF8 -LiteralPath (Join-Path $runDir 'largest-files.csv')

Write-Host ''
Write-Host "Largest folders on $Drive"
$folders | Select-Object -First $Top | Format-Table Size, Path, Files -AutoSize | Out-Host
if ($userFolders) {
    Write-Host 'Largest folders in your user folder'
    $userFolders | Select-Object -First $Top | Format-Table Size, Path -AutoSize | Out-Host
}
Write-Host ("Files of {0} MB or more" -f $BigFileMB)
$bigSorted | Format-Table Size, Modified, Path -AutoSize | Out-Host
Write-Host 'Caches'
$caches | Sort-Object Bytes -Descending | Format-Table Name, Size, Path -AutoSize | Out-Host
$unreadable = Get-SumBytes $folders 'Unreadable'
if ($unreadable -gt 0) { Write-Host ("{0} folders could not be read and were skipped (normal without admin rights)." -f $unreadable) }

# Compare with the previous report of the same drive, if any.
$previous = Get-ChildItem -LiteralPath $OutDir -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -lt $stamp -and (Test-Path -LiteralPath (Join-Path $_.FullName 'scan.json')) } |
    Sort-Object Name -Descending
foreach ($p in $previous) {
    try { $old = Get-Content -Raw -LiteralPath (Join-Path $p.FullName 'scan.json') | ConvertFrom-Json } catch { continue }
    if ($old.Drive -eq $Drive -and $old.UsedBytes -is [ValueType]) {
        $delta = [long]$old.UsedBytes - $used
        $word = if ($delta -ge 0) { 'freed' } else { 'more used' }
        Write-Host ("Since the scan on {0}: {1} {2}." -f $p.Name, (Format-Size ([math]::Abs($delta))), $word)
        break
    }
}
Write-Host "Report saved in $runDir (nothing on your drive was changed)."
