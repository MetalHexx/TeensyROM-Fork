<#
.SYNOPSIS
    TeensyROM SD card builder - native Windows PowerShell port of the reference Makefile.

.DESCRIPTION
    Rebuilds the full card contents from their four upstream sources and writes a
    verified card. Ported from the project's `Makefile`, which on Windows required
    Git Bash/MSYS2 (curl, 7z, rsync, unzip) for content building and only delegated
    disk operations to PowerShell. This script needs only 7-Zip - downloads use
    Invoke-WebRequest, archive copying uses robocopy, and disk work uses the native
    Storage cmdlets.

    The card layout is NOT the same as the upstream OneLoad64 archive layout, and
    the card deliberately omits ~20,000 files from it (AlternativeFormats, Images,
    xml/tap/ocp dumps, OfficialCRTs *.bin). Invoke-Tree encodes that mapping.

    Run with no arguments (or -Target help) for the full command reference.

.PARAMETER Target
    The action to perform: help, deps, fetch, extract, tree, summary, identify,
    check, format, write, verify, eject, card, test, rescue, clean, distclean.

.EXAMPLE
    .\Build-TeensyromCard.ps1 fetch

.EXAMPLE
    .\Build-TeensyromCard.ps1 tree

.EXAMPLE
    .\Build-TeensyromCard.ps1 card -Disk 1 -Confirm -Size 32GB
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help', 'deps', 'fetch', 'extract', 'tree', 'summary',
        'identify', 'check', 'format', 'write', 'verify', 'eject', 'card',
        'test', 'rescue', 'clean', 'distclean')]
    [string]$Target = 'help',

    [string]$Build = (Join-Path $env:LOCALAPPDATA 'teensyrom'),
    [string]$CardSrc,
    [string]$Label = 'TEENSYROM',
    [Nullable[int]]$Disk,
    [string]$Drive,
    [string]$Size,
    [Nullable[int]]$TestGB,
    [int]$HvscVer = 81,
    [string]$OneloadGDriveId = '1Ef6J-yyzE14stEaqjK7XlYuutDDBOCyr',
    [switch]$Confirm,
    [switch]$AllowUnknownCard,
    [string]$Img = (Join-Path $env:USERPROFILE 'sd.img')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# ------------------------------------------------------------- configuration

if (-not $CardSrc) { $CardSrc = Join-Path $Build 'card' }
$DL = Join-Path $Build 'downloads'
$EX = Join-Path $Build 'extract'

$HvscUrl = "https://hvsc.etv.cx/HVSC_$HvscVer-all-of-them.7z"
$OneloadUrl = "https://drive.usercontent.google.com/download?id=$OneloadGDriveId&export=download&confirm=t"
$DemosUrl = 'https://sensoriumembedded.com/tinyweb64/Demos/'
$TrplusUrl = 'https://sensoriumembedded.com/tinyweb64/TeensyROM+/TR+%20Demos-Support.zip'
$AutolaunchUrl = 'https://raw.githubusercontent.com/SensoriumEmbedded/TeensyROM/main/docs/autolaunch.txt'

$Hvsc7z = Join-Path $DL "HVSC_$HvscVer-all-of-them.7z"
$Oneload7z = Join-Path $DL 'OneLoad64-Games-Collection-v5.7z'
$Trplus7z = Join-Path $DL 'TR-Demos-Support.zip'

# Junk Windows/macOS sprinkle on a FAT volume; never counted or written as ours.
$ExcludeDirs = @('.git', '.fseventsd', '.Spotlight-V100', 'System Volume Information', '$RECYCLE.BIN')
$ExcludeFiles = @('.DS_Store', '._*', 'Thumbs.db', 'desktop.ini', 'Makefile', '*.ps1')

# ------------------------------------------------------------------ helpers

function Write-Step($Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Sub($Message) { Write-Host "    $Message" }
function Fail($Message) { Write-Host $Message -ForegroundColor Red; exit 1 }

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Bytes([long]$n) {
    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $i = 0
    $v = [double]$n
    while ($v -ge 1024 -and $i -lt $units.Count - 1) { $v /= 1024; $i++ }
    '{0:N1}{1}' -f $v, $units[$i]
}

function ConvertTo-Bytes([string]$s) {
    if ($s -match '^(?<num>[\d.]+)\s*(?<unit>[KMGT]?B?)$') {
        $num = [double]$Matches.num
        $mult = switch ($Matches.unit.ToUpper()) {
            'K' { 1KB }; 'KB' { 1KB }
            'M' { 1MB }; 'MB' { 1MB }
            'G' { 1GB }; 'GB' { 1GB }
            'T' { 1TB }; 'TB' { 1TB }
            default { 1 }
        }
        return [int64]($num * $mult)
    }
    Fail "cannot parse size '$s' (try e.g. 32GB)"
}

# ------------------------------------------------------------------ prereqs

function Get-7ZipPath {
    $cmd = Get-Command -Name '7z.exe', '7z' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    foreach ($p in @("$env:ProgramFiles\7-Zip\7z.exe", "${env:ProgramFiles(x86)}\7-Zip\7z.exe")) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Test-Deps {
    $sevenZip = Get-7ZipPath
    if (-not $sevenZip) {
        Write-Host 'missing tool: 7z (7-Zip command-line)' -ForegroundColor Red
        Write-Host 'install with: winget install -e --id 7zip.7zip'
        Write-Host '  (or download from https://www.7-zip.org/ and ensure 7z.exe is on PATH)'
        exit 1
    }
    Write-Host "all required tools present (7-Zip: $sevenZip)"
}

# ----------------------------------------------------------------- fetching

function Get-UrlWithRetry([string]$Url, [string]$Dest, [int]$Retries = 3) {
    $part = "$Dest.part"
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        for ($i = 1; $i -le $Retries; $i++) {
            try {
                Invoke-WebRequest -Uri $Url -OutFile $part -UseBasicParsing
                Move-Item -Force $part $Dest
                return
            } catch {
                Write-Host "  download attempt $i failed: $($_.Exception.Message)"
                Start-Sleep -Seconds 2
            }
        }
        Fail "failed to download $Url after $Retries attempts"
    } finally {
        $ProgressPreference = $prevProgress
    }
}

function Test-ArchiveIntegrity([string]$Path) {
    $sevenZip = Get-7ZipPath
    & $sevenZip t $Path | Out-Null
    return $LASTEXITCODE -eq 0
}

function Get-Demos {
    $demosDir = Join-Path $DL 'demos'
    $stamp = Join-Path $DL 'demos.stamp'
    if (Test-Path $stamp) { return }
    Write-Step 'Single Load Demos'
    New-Item -ItemType Directory -Force -Path $demosDir | Out-Null
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try {
        $resp = Invoke-WebRequest -Uri $DemosUrl -UseBasicParsing
        $hrefs = [regex]::Matches($resp.Content, 'href="([^"?/][^"]*)"') |
            ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -notmatch '^index\.html' -and $_ -notmatch '/$' } |
            Select-Object -Unique
        $failed = 0
        foreach ($href in $hrefs) {
            $name = [System.Uri]::UnescapeDataString($href)
            $dest = Join-Path $demosDir $name
            try { Get-UrlWithRetry ($DemosUrl + $href) $dest } catch { $failed++ }
        }
        if ($failed -gt 0) { Fail "$failed demo file(s) failed to download" }
    } finally {
        $ProgressPreference = $prevProgress
    }
    New-Item -ItemType File -Force -Path $stamp | Out-Null
}

function Invoke-Fetch {
    New-Item -ItemType Directory -Force -Path $DL | Out-Null

    if (-not (Test-Path $Hvsc7z)) {
        Write-Step "HVSC #$HvscVer"
        Get-UrlWithRetry $HvscUrl $Hvsc7z
        if (-not (Test-ArchiveIntegrity $Hvsc7z)) { Remove-Item $Hvsc7z; Fail 'HVSC archive failed integrity check' }
    }

    if (-not (Test-Path $Oneload7z)) {
        Write-Step 'OneLoad64 v5 (554 MB)'
        Get-UrlWithRetry $OneloadUrl $Oneload7z
        if (-not (Test-ArchiveIntegrity $Oneload7z)) { Remove-Item $Oneload7z; Fail 'OneLoad archive failed integrity check' }
    }

    if (-not (Test-Path $Trplus7z)) {
        Write-Step 'TeensyROM+ Demos-Support'
        Get-UrlWithRetry $TrplusUrl $Trplus7z
    }

    $autolaunch = Join-Path $DL 'autolaunch.txt'
    Write-Step 'autolaunch.txt'
    Get-UrlWithRetry $AutolaunchUrl $autolaunch

    Get-Demos
}

# ---------------------------------------------------------------- extraction

function Invoke-Extract {
    New-Item -ItemType Directory -Force -Path $EX | Out-Null
    $sevenZip = Get-7ZipPath
    if (-not $sevenZip) { Fail "7-Zip not found; run '.\$(Split-Path -Leaf $PSCommandPath) deps'" }

    $hvscStamp = Join-Path $EX 'hvsc.stamp'
    if (-not (Test-Path $hvscStamp)) {
        Write-Step 'extracting HVSC'
        $dest = Join-Path $EX 'hvsc'
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        & $sevenZip x -y "-o$dest" $Hvsc7z | Out-Null
        New-Item -ItemType File -Force -Path $hvscStamp | Out-Null
    }

    $oneloadStamp = Join-Path $EX 'oneload.stamp'
    if (-not (Test-Path $oneloadStamp)) {
        Write-Step 'extracting OneLoad64 (27k files, takes a minute)'
        $dest = Join-Path $EX 'oneload'
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        & $sevenZip x -y "-o$dest" $Oneload7z | Out-Null
        New-Item -ItemType File -Force -Path $oneloadStamp | Out-Null
    }

    $trplusStamp = Join-Path $EX 'trplus.stamp'
    if (-not (Test-Path $trplusStamp)) {
        Write-Step 'extracting TR+ Demos-Support'
        $dest = Join-Path $EX 'trplus'
        if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        Expand-Archive -Path $Trplus7z -DestinationPath $dest -Force
        New-Item -ItemType File -Force -Path $trplusStamp | Out-Null
    }
}

# -------------------------------------------------------------- tree assembly

function Invoke-Robocopy {
    param([string]$Src, [string]$Dst, [string[]]$FilePatterns = @(), [string[]]$RoboArgs = @())
    New-Item -ItemType Directory -Force -Path $Dst | Out-Null
    $argList = @($Src, $Dst) + $FilePatterns + $RoboArgs + @('/NFL', '/NDL', '/NJH', '/NJS', '/R:2', '/W:2')
    robocopy @argList | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "robocopy failed copying '$Src' -> '$Dst' (exit $LASTEXITCODE)" }
}

# Reproduces the card's curation. Counts in comments are for OneLoad64 v5 / HVSC #81.
function Invoke-Tree {
    Invoke-Fetch
    Invoke-Extract

    Write-Step "assembling card tree at $CardSrc"
    if (Test-Path $CardSrc) { Remove-Item -Recurse -Force $CardSrc }

    $O = Join-Path $EX 'oneload'
    $C = Join-Path $CardSrc 'OneLoad v5'
    New-Item -ItemType Directory -Force -Path $C | Out-Null

    Write-Sub 'Main- MagicDesk CRTs  <- archive root *.crt'
    Invoke-Robocopy $O (Join-Path $C 'Main- MagicDesk CRTs') @('*.crt')

    Write-Sub 'MultiLoad64           <- MultiLoad64/'
    Invoke-Robocopy (Join-Path $O 'MultiLoad64') (Join-Path $C 'MultiLoad64') @() @('/E')

    Write-Sub 'Dumps                 <- Dumps/*.koa + *.sid  (no xml/tap/ocp)'
    Invoke-Robocopy (Join-Path $O 'Dumps') (Join-Path $C 'Dumps') @('*.koa', '*.sid')

    Write-Sub 'SplashPics            <- Dumps/*.koa'
    Invoke-Robocopy (Join-Path $O 'Dumps') (Join-Path $C 'SplashPics') @('*.koa')

    Write-Sub 'Extras                <- OfficialCRTs (no *.bin) + OtherCRTs  (no Images/)'
    Invoke-Robocopy (Join-Path $O 'Extras\OfficialCRTs') (Join-Path $C 'Extras\OfficialCRTs') @() @('/E', '/XF', '*.bin')
    Invoke-Robocopy (Join-Path $O 'Extras\OtherCRTs') (Join-Path $C 'Extras\OtherCRTs') @() @('/E')

    Write-Sub 'Docs                  <- Docs/'
    Invoke-Robocopy (Join-Path $O 'Docs') (Join-Path $C 'Docs') @() @('/E')

    Write-Step "C64Music              <- HVSC #$HvscVer"
    Invoke-Robocopy (Join-Path $EX 'hvsc\C64Music') (Join-Path $CardSrc 'C64Music') @() @('/E')
    # zero-byte version marker the original card carried; not part of HVSC itself
    New-Item -ItemType File -Force -Path (Join-Path $CardSrc "C64Music\HVSC #$HvscVer") | Out-Null

    Write-Step 'Demos'
    Invoke-Robocopy (Join-Path $DL 'demos') (Join-Path $CardSrc 'Demos') @() @('/E')

    Write-Step 'TR+ Demos-Support'
    Invoke-Robocopy (Join-Path $EX 'trplus\TR+ Demos-Support') (Join-Path $CardSrc 'TR+ Demos-Support') @() @('/E')

    Copy-Item (Join-Path $DL 'autolaunch.txt') (Join-Path $CardSrc 'autolaunch.txt') -Force

    New-Item -ItemType File -Force -Path (Join-Path $Build 'card.stamp') | Out-Null
    Show-Summary
}

function Show-Summary {
    if (-not (Test-Path $CardSrc)) { Fail "no tree yet - run '.\$(Split-Path -Leaf $PSCommandPath) tree'" }
    Write-Host
    Write-Host "card tree: $CardSrc"
    $allFiles = Get-ChildItem -Path $CardSrc -Recurse -File
    Write-Host ('  {0,-24} {1}' -f 'total files', $allFiles.Count)
    foreach ($d in @('OneLoad v5', 'C64Music', 'Demos', 'TR+ Demos-Support')) {
        $p = Join-Path $CardSrc $d
        $count = if (Test-Path $p) { (Get-ChildItem -Path $p -Recurse -File).Count } else { 0 }
        Write-Host ('  {0,-24} {1}' -f $d, $count)
    }
    $crt = ($allFiles | Where-Object Extension -eq '.crt').Count
    $sid = ($allFiles | Where-Object Extension -eq '.sid').Count
    Write-Host ('  {0,-24} {1}' -f '.crt', $crt)
    Write-Host ('  {0,-24} {1}' -f '.sid', $sid)
    $bytes = ($allFiles | Measure-Object -Property Length -Sum).Sum
    Write-Host ('  {0,-24} {1}' -f 'size', (Format-Bytes $bytes))
}

# ===========================================================================
#  Everything below this line touches physical disks.
# ===========================================================================

function Get-Identify {
    Write-Host '--- disks ---'
    Get-Disk | Format-Table Number, FriendlyName,
    @{Name = 'Size(GB)'; Expression = { [math]::Round($_.Size / 1GB, 1) } },
    BusType, PartitionStyle -AutoSize
    Write-Host '--- volumes ---'
    Get-Volume | Where-Object DriveLetter | Format-Table DriveLetter, FileSystemLabel, FileSystem,
    @{Name = 'Size(GB)'; Expression = { [math]::Round($_.Size / 1GB, 1) } } -AutoSize
    Write-Host 'Windows does not expose the SD CID register; `check` cannot authenticate a card here.'
    Write-Host '`test` is not packaged for native Windows either - see its message.'
}

# Refuses anything that is not SD/USB/MMC media, which is the guard against
# typing the internal drive.
function Test-RequireDisk {
    if ($null -eq $Disk) { Fail "set -Disk <number>  (see 'identify')" }
    $d = Get-Disk -Number $Disk -ErrorAction SilentlyContinue
    if (-not $d) { Fail "disk $Disk`: no such disk" }
    if ($d.BusType -notin @('SD', 'USB', 'MMC')) {
        Write-Host "REFUSING: disk $Disk has BusType '$($d.BusType)', not SD/USB/MMC." -ForegroundColor Red
        $d | Format-List Number, FriendlyName, Size, BusType
        exit 1
    }
    return $d
}

function Test-RequireConfirm {
    if (-not $Confirm) { Fail 'This ERASES the target disk. Re-run with -Confirm to proceed.' }
}

function Test-RequireDrive {
    if (-not $Drive) { Fail "set -Drive E  (the card's drive letter)" }
    $letter = $Drive.TrimEnd(':').ToUpper()
    $script:Mnt = "$letter`:\"
    if (-not (Test-Path $Mnt)) { Fail "$Mnt not present - is ${letter}: mounted?" }
}

function Test-Check {
    Test-RequireDisk | Out-Null
    Write-Host 'Windows does not expose the SD CID register - cannot authenticate.'
    Write-Host "Run '.\$(Split-Path -Leaf $PSCommandPath) test -Disk $Disk -Confirm' instead (not packaged for Windows; see its message)."
    if (-not $AllowUnknownCard) { exit 1 }
}

# Windows' Format-Volume refuses FAT32 on volumes larger than 32 GB. -Size 32GB
# sidesteps that and is what the TeensyROM docs recommend anyway.
function Invoke-Format {
    if (-not (Test-IsAdmin)) { Fail 'This must be run from an Administrator PowerShell.' }
    Test-RequireDisk | Out-Null
    Test-RequireConfirm

    Write-Step "clearing disk $Disk (requires an Administrator shell)"
    Clear-Disk -Number $Disk -RemoveData -RemoveOEM -Confirm:$false
    Initialize-Disk -Number $Disk -PartitionStyle MBR -ErrorAction SilentlyContinue

    if ([string]::IsNullOrWhiteSpace($Size)) {
        $part = New-Partition -DiskNumber $Disk -UseMaximumSize -AssignDriveLetter
    } else {
        $bytes = ConvertTo-Bytes $Size
        $part = New-Partition -DiskNumber $Disk -Size $bytes -AssignDriveLetter
    }
    Format-Volume -Partition $part -FileSystem FAT32 -NewFileSystemLabel $Label -Confirm:$false | Out-Null
    Write-Host "Note the assigned drive letter, then: write -Drive $($part.DriveLetter)"
    return $part.DriveLetter
}

function Invoke-Write {
    if (-not (Test-Path $CardSrc)) { Fail "no tree yet - run '.\$(Split-Path -Leaf $PSCommandPath) tree'" }
    Test-RequireDrive
    Write-Step "writing to $Mnt"
    New-Item -ItemType Directory -Force -Path $Build | Out-Null
    $log = Join-Path $Build 'write.log'
    robocopy $CardSrc $Mnt /E /XD $ExcludeDirs /XF $ExcludeFiles /R:2 /W:2 /NFL /NDL /NP /LOG:$log | Out-Null
    if ($LASTEXITCODE -ge 8) { Fail "robocopy failed writing to $Mnt (exit $LASTEXITCODE); see $log" }
    Get-Content $log | Select-String 'Files :|Bytes :' | ForEach-Object { Write-Host "  $_" }
}

function Test-IsExcluded([string]$Rel) {
    foreach ($d in $ExcludeDirs) { if ($Rel -like "$d\*" -or $Rel -eq $d) { return $true } }
    $leaf = Split-Path $Rel -Leaf
    foreach ($f in $ExcludeFiles) { if ($leaf -like $f) { return $true } }
    return $false
}

# Checksums every file, which is the real point of `verify`: it reads the card
# back byte-for-byte to catch counterfeit capacity or write errors, not just
# compare size/timestamp the way a plain copy check would.
function Invoke-Verify {
    Test-RequireDrive
    Write-Step "checksumming every file against $CardSrc"
    New-Item -ItemType Directory -Force -Path $Build | Out-Null
    $diffsPath = Join-Path $Build 'diffs.txt'
    if (Test-Path $diffsPath) { Remove-Item $diffsPath }

    $srcFiles = Get-ChildItem -Path $CardSrc -Recurse -File
    $total = 0
    $mismatches = New-Object System.Collections.Generic.List[string]
    $i = 0
    foreach ($f in $srcFiles) {
        $i++
        $rel = $f.FullName.Substring($CardSrc.Length).TrimStart('\')
        if (Test-IsExcluded $rel) { continue }
        $total++
        Write-Progress -Activity 'Verifying card' -Status $rel -PercentComplete (100 * $i / $srcFiles.Count)
        $dstPath = Join-Path $Mnt $rel
        if (-not (Test-Path $dstPath)) {
            $mismatches.Add("$rel  (missing on card)")
            continue
        }
        $h1 = (Get-FileHash -Path $f.FullName -Algorithm MD5).Hash
        $h2 = (Get-FileHash -Path $dstPath -Algorithm MD5).Hash
        if ($h1 -ne $h2) { $mismatches.Add($rel) }
    }
    Write-Progress -Activity 'Verifying card' -Completed

    if ($mismatches.Count -eq 0) {
        Write-Host "VERIFIED: 0 mismatches across $total files"
    } else {
        $mismatches | Set-Content $diffsPath
        Write-Host "FAILED: $($mismatches.Count) files differ (see $diffsPath)" -ForegroundColor Red
        $mismatches | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
}

function Invoke-Eject {
    Test-RequireDrive
    $letter = $Drive.TrimEnd(':').ToUpper()
    try {
        $shell = New-Object -ComObject Shell.Application
        $shell.Namespace(17).ParseName("$letter`:").InvokeVerb('Eject')
        Write-Host "ejected $letter`:"
    } catch {
        Write-Host 'eject failed - unmount from Explorer instead'
    }
}

function Invoke-Card {
    if ($null -eq $Disk) { Fail "set -Disk <number>  (see 'identify')" }
    Invoke-Tree
    Test-Check
    $assignedDrive = Invoke-Format
    $script:Drive = $assignedDrive
    Invoke-Write
    Invoke-Verify
    Invoke-Eject
    Write-Host
    Write-Host 'card complete and ejected.'
}

# f3 (counterfeit-capacity test) and ddrescue (failing-card imaging) are not
# packaged for native Windows. The reference Makefile punts here too - it
# points macOS/Linux users at f3/ddrescue and leaves Windows unimplemented.
function Invoke-Test {
    Test-RequireDisk | Out-Null
    Test-RequireConfirm
    Write-Host 'f3 is not packaged for native Windows; use h2testw instead.' -ForegroundColor Yellow
    Write-Host 'https://www.heise.de/download/product/h2testw-50539'
    exit 1
}

function Invoke-Rescue {
    Test-RequireDisk | Out-Null
    Write-Host 'ddrescue is not available on native Windows.' -ForegroundColor Yellow
    Write-Host 'Use WSL (apt install gddrescue) or a dedicated imaging tool such as'
    Write-Host 'Win32 Disk Imager to image the card before attempting any repair.'
    exit 1
}

# ---------------------------------------------------------------------- cleanup

function Invoke-Clean {
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $CardSrc, $EX, (Join-Path $Build 'card.stamp')
}

function Invoke-Distclean {
    Invoke-Clean
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $Build
}

# ------------------------------------------------------------------------ help

function Show-Help {
    $script = Split-Path -Leaf $PSCommandPath
    Write-Host "TeensyROM SD card builder (Windows)"
    Write-Host
    Write-Host 'Build the contents (no card needed, safe):'
    Write-Host "  .\$script deps                        check required tools are installed"
    Write-Host "  .\$script fetch                        download all four upstream sources"
    Write-Host "  .\$script tree                         assemble the curated card tree"
    Write-Host "  .\$script summary                      show what the assembled tree contains"
    Write-Host
    Write-Host 'Write a card (needs an Administrator PowerShell):'
    Write-Host "  .\$script identify                            list disks and volumes"
    Write-Host "  .\$script format -Disk 1 -Confirm             ERASES disk 1, assigns a drive letter"
    Write-Host "  .\$script write  -Drive E                     copy the tree"
    Write-Host "  .\$script verify -Drive E                     checksum every file"
    Write-Host "  .\$script eject  -Drive E"
    Write-Host "  .\$script card   -Disk 1 -Confirm             full pipeline, format through eject"
    Write-Host
    Write-Host '  NOTE: Windows Format-Volume refuses FAT32 above 32 GB, so -Size 32GB'
    Write-Host '        is effectively required on larger cards.'
    Write-Host
    Write-Host 'Limit the card to a smaller partition (the TeensyROM docs say 32 GB'
    Write-Host 'gives the fastest directory reads; the rest is left unallocated):'
    Write-Host "  .\$script card -Disk 1 -Confirm -Size 32GB"
    Write-Host
    Write-Host 'Other:'
    Write-Host "  .\$script check  -Disk 1                       no CID on Windows; needs -AllowUnknownCard"
    Write-Host "  .\$script test   -Disk 1 -Confirm              not packaged for native Windows (see message)"
    Write-Host "  .\$script rescue -Disk 1 -Img C:\sd.img        not available on native Windows (see message)"
    Write-Host
    Write-Host "  .\$script clean / distclean                   remove the tree / also the downloads"
    Write-Host
    Write-Host "Variables: -Build $Build"
    Write-Host "           -CardSrc $CardSrc"
    Write-Host "           -Label $Label  -HvscVer $HvscVer"
}

# ------------------------------------------------------------------- dispatch

switch ($Target) {
    'help' { Show-Help }
    'deps' { Test-Deps }
    'fetch' { Invoke-Fetch }
    'extract' { Invoke-Extract }
    'tree' { Invoke-Tree }
    'summary' { Show-Summary }
    'identify' { Get-Identify }
    'check' { Test-Check }
    'format' { Invoke-Format | Out-Null }
    'write' { Invoke-Write }
    'verify' { Invoke-Verify }
    'eject' { Invoke-Eject }
    'card' { Invoke-Card }
    'test' { Invoke-Test }
    'rescue' { Invoke-Rescue }
    'clean' { Invoke-Clean }
    'distclean' { Invoke-Distclean }
}
