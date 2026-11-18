<#
  A simple automated guard, not a sandbox: fails if a script in the skill uses a
  known command that could change, delete or download files, if another script file
  appears, or if scan.ps1 or SKILL.md no longer match SHA256SUMS.txt. Run before every release, and in GitHub Actions
  on every change:
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\check-readonly.ps1
#>
Set-StrictMode -Version 2
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$scripts = Get-ChildItem -LiteralPath (Join-Path $root 'windows-drive-scan') -Recurse -File | Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1', '.bat', '.cmd', '.vbs', '.js', '.py', '.exe', '.dll' }
$failed = @()

# Only scan.ps1 may exist; any other script file is a failure.
foreach ($s in $scripts) {
    if ($s.Name -ne 'scan.ps1') { $failed += "Unexpected script file: $($s.FullName)" }
}

# Commands that change, delete or download things. scan.ps1 may only create its
# own report folder and files (New-Item -ItemType Directory, Set-Content, Export-Csv).
$banned = @(
    'Remove-Item', 'Move-Item', 'Rename-Item', 'Copy-Item', 'Clear-Content', 'Clear-Item',
    'Clear-RecycleBin', 'FileSystem\]::Delete', 'DeleteFile', 'DeleteDirectory', '\.Delete\(', '\.MoveTo\(',
    'Microsoft\.VisualBasic', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer', 'Net\.WebClient',
    'HttpClient', 'DownloadString', 'DownloadFile', 'Invoke-Expression', '\biex\b', 'Start-Process',
    'Set-ItemProperty', 'New-ItemProperty', 'Set-ExecutionPolicy', 'Add-MpPreference', 'reg\s+add', 'schtasks',
    'FromBase64String', '-EncodedCommand', '\bdel\b', '\brmdir\b', '\brd\b', '\berase\b', 'format\.com', 'cipher'
)
foreach ($s in $scripts) {
    $text = Get-Content -Raw -LiteralPath $s.FullName
    foreach ($b in $banned) {
        if ($text -match $b) { $failed += "$($s.Name) contains '$b'" }
    }
    # Writes are allowed only for the report.
    foreach ($line in ($text -split "`n")) {
        if ($line -match '(Set-Content|Export-Csv|Out-File|Add-Content|New-Item|CreateDirectory|WriteAll|AppendAll|StreamWriter|FileStream|\[IO\.File\]|System\.IO\.File\])' -and $line -notmatch '\$runDir') {
            $failed += "$($s.Name) writes outside the report folder: $($line.Trim())"
        }
    }
}

# Hashes must match SHA256SUMS.txt.
$sums = Join-Path $root 'SHA256SUMS.txt'
if (-not (Test-Path -LiteralPath $sums)) { $failed += 'SHA256SUMS.txt is missing' }
else {
    foreach ($line in Get-Content -LiteralPath $sums) {
        if ($line -notmatch '^([0-9a-f]{64})\s+(.+)$') { continue }
        $file = Join-Path $root $Matches[2]
        if (-not (Test-Path -LiteralPath $file)) { $failed += "Listed file missing: $($Matches[2])"; continue }
        $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $file).Hash.ToLower()
        if ($actual -ne $Matches[1]) { $failed += "Hash mismatch: $($Matches[2])" }
    }
}

if ($failed) {
    $failed | ForEach-Object { Write-Host "FAIL: $_" }
    exit 1
}
Write-Host "PASS: $(@($scripts).Count) script(s) checked, read only, hashes match."
exit 0
