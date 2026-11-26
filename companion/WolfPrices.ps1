# The Wolf of Booty Bay - prices companion.
# A small tray app: every 15 minutes it asks the price robot (GitHub) when its newest prices are from - a note of a
# few hundred bytes - and when they're newer than the ones in your addon folder, it downloads the price file and
# swaps it in, then tells you. The game reads it at your next /reload (an addon can't load files on its own).
# It also reads which prices the game loaded last (the addon writes that at every reload), for the tray's hover.
# Nothing to install: run "Start Wolf prices.cmd". Settings and a log: %APPDATA%\WolfPrices.
# Windows PowerShell 5.1 (built into Windows 10 and 11).

param([switch]$Once) # -Once: one check, no tray (for testing)

$ErrorActionPreference = 'Stop'
$Repo = 'sain221b-sketch/ForeverTrading'
$InfoUrl = "https://github.com/$Repo/releases/latest/download/latest.json"
$FeedUrl = "https://github.com/$Repo/releases/latest/download/Feed.lua"
$EveryMinutes = 15
$AppDir = Join-Path $env:APPDATA 'WolfPrices'
$ConfigFile = Join-Path $AppDir 'config.json'
$LogFile = Join-Path $AppDir 'log.txt'
$Flavors = @('_forever_', '_classic_beta_', '_classic_era_', '_classic_', '_retail_')

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

# ---------------------------------------------------------------------------------------------------------------
# Log and settings
# ---------------------------------------------------------------------------------------------------------------
function Write-Log([string]$msg) {
    try {
        Add-Content -Path $LogFile -Value ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8
        $lines = Get-Content -Path $LogFile -Encoding UTF8
        if ($lines.Count -gt 400) { $lines | Select-Object -Last 300 | Set-Content -Path $LogFile -Encoding UTF8 }
    } catch { }
}

function Get-Config {
    $c = @{ wowRoot = $null; flavor = $null; askedStartup = $false }
    if (Test-Path $ConfigFile) {
        try {
            $j = Get-Content -Path $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in @('wowRoot', 'flavor', 'askedStartup')) { if ($null -ne $j.$k) { $c[$k] = $j.$k } }
        } catch { Write-Log "settings unreadable, starting fresh: $($_.Exception.Message)" }
    }
    return $c
}

function Save-Config($c) {
    ([pscustomobject]$c) | ConvertTo-Json | Set-Content -Path $ConfigFile -Encoding UTF8
}

# ---------------------------------------------------------------------------------------------------------------
# Where the addon is: World of Warcraft's folder from the Battle.net install (registry), the usual places, or asked
# ---------------------------------------------------------------------------------------------------------------
function Get-WowRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('HKLM:\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
                       'HKLM:\SOFTWARE\Blizzard Entertainment\World of Warcraft')) {
        try {
            $p = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallPath
            if ($p) {
                $p = $p.TrimEnd('\')
                # InstallPath points at one game version's folder (...\World of Warcraft\_retail_): its parent
                if ((Split-Path $p -Leaf) -like '_*_') { $p = Split-Path $p -Parent }
                $roots.Add($p)
            }
        } catch { }
    }
    foreach ($p in @("${env:ProgramFiles(x86)}\World of Warcraft", "$env:ProgramFiles\World of Warcraft",
                     'C:\World of Warcraft', 'D:\World of Warcraft', 'D:\Games\World of Warcraft', 'E:\World of Warcraft',
                     'C:\Games\World of Warcraft')) {
        if ($p -and -not $roots.Contains($p)) { $roots.Add($p) }
    }
    return $roots
}

# the game version's folder that has the addon: @{ root; flavor; dir; addon } or $null
function Find-Addon([string]$root, [string]$prefer) {
    if (-not $root -or -not (Test-Path $root)) { return $null }
    $order = @($Flavors)
    if ($prefer) { $order = @($prefer) + ($Flavors | Where-Object { $_ -ne $prefer }) }
    foreach ($f in $order) {
        $dir = Join-Path $root $f
        $addon = Join-Path $dir 'Interface\AddOns\WolfOfBootyBay'
        if (Test-Path (Join-Path $addon 'WolfOfBootyBay.toc')) {
            return @{ root = $root; flavor = $f; dir = $dir; addon = $addon }
        }
    }
    return $null
}

function Ask-WowRoot {
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Where is World of Warcraft? Pick the "World of Warcraft" folder (the one with _forever_ in it).'
    $dlg.ShowNewFolderButton = $false
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.SelectedPath }
    return $null
}

function Resolve-Addon($cfg, [bool]$mayAsk) {
    $found = Find-Addon $cfg.wowRoot $cfg.flavor
    if (-not $found) {
        foreach ($r in (Get-WowRoots)) { $found = Find-Addon $r $null; if ($found) { break } }
    }
    if (-not $found -and $mayAsk) {
        $picked = Ask-WowRoot
        if ($picked) {
            # they may pick the game version's folder itself, or the AddOns folder: walk up to World of Warcraft
            $p = $picked
            for ($i = 0; $i -lt 4 -and $p; $i++) {
                $found = Find-Addon $p $null
                if ($found) { break }
                $p = Split-Path $p -Parent
            }
        }
    }
    if ($found) {
        $cfg.wowRoot = $found.root
        $cfg.flavor = $found.flavor
        Save-Config $cfg
    }
    return $found
}

# ---------------------------------------------------------------------------------------------------------------
# The prices: when each is from (Blizzard's snapshot time, unix seconds)
# ---------------------------------------------------------------------------------------------------------------
# the newest house time in a price file (its lines "[110] = { t = 1795562778, ..."), and when it was built
function Read-FeedTimes([string]$file) {
    $r = @{ t = [int64]0; built = [int64]0 }
    if (-not (Test-Path $file)) { return $r }
    $head = Get-Content -Path $file -TotalCount 8 -Encoding UTF8
    foreach ($l in $head) { if ($l -match 'built = (\d+)') { $r.built = [int64]$Matches[1] } }
    foreach ($m in (Select-String -Path $file -Pattern '\[\d+\] = \{ t = (\d+),' -AllMatches)) {
        foreach ($g in $m.Matches) { $v = [int64]$g.Groups[1].Value; if ($v -gt $r.t) { $r.t = $v } }
    }
    return $r
}

# which prices the game loaded last: the addon keeps them in its saved data, written at every /reload and logout
# (the newest file of every account); 0 when not seen yet
function Read-InGame($found) {
    $best = [int64]0
    $files = Get-ChildItem -Path (Join-Path $found.dir 'WTF\Account\*\SavedVariables\WolfOfBootyBay.lua') -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending
    foreach ($f in $files) {
        $text = Get-Content -Path $f.FullName -Raw -Encoding UTF8
        $m = [regex]::Match($text, '\["feedLoaded"\]\s*=\s*\{([^}]*)\}', 'Singleline')
        if ($m.Success) {
            foreach ($n in [regex]::Matches($m.Groups[1].Value, '=\s*(\d+)')) {
                $v = [int64]$n.Groups[1].Value
                if ($v -gt $best) { $best = $v }
            }
            break
        }
    }
    return $best
}

function Format-Time([int64]$t) {
    if ($t -le 0) { return '?' }
    $dt = [DateTimeOffset]::FromUnixTimeSeconds($t).LocalDateTime
    $s = $dt.ToString('h:mm tt', [Globalization.CultureInfo]::InvariantCulture).ToLower()
    if ($dt.Date -ne (Get-Date).Date) { $s = $dt.ToString('ddd', [Globalization.CultureInfo]::InvariantCulture) + ' ' + $s }
    return $s
}

# One check: the note, and the price file when it's newer than the one on disk.
# Returns @{ ok; ready (t on disk); inGame (t loaded); downloaded (bool); error }
function Update-Prices($found) {
    $res = @{ ok = $false; ready = [int64]0; inGame = [int64]0; downloaded = $false; error = $null }
    $feed = Join-Path $found.addon 'Data\Feed.lua'
    try {
        # GitHub serves it as a plain download: its bytes, read as text, then as JSON
        $raw = (Invoke-WebRequest -Uri $InfoUrl -TimeoutSec 30 -UseBasicParsing -Headers @{ 'Cache-Control' = 'no-cache' }).Content
        if ($raw -is [byte[]]) { $raw = [Text.Encoding]::UTF8.GetString($raw) }
        $info = $raw | ConvertFrom-Json
        if (-not $info.built) { throw "the price note had no time in it" }
        $disk = Read-FeedTimes $feed
        if ([int64]$info.built -gt $disk.built) {
            $tmp = "$feed.download"
            Invoke-WebRequest -Uri $FeedUrl -OutFile $tmp -TimeoutSec 180 -UseBasicParsing
            # only a whole, real price file replaces the one there
            $first = Get-Content -Path $tmp -TotalCount 1 -Encoding UTF8
            $got = Read-FeedTimes $tmp
            if ((Get-Item $tmp).Length -lt 10000 -or $first -notlike '-- Generated by tools/feed/build.mjs*' -or $got.built -lt [int64]$info.built) {
                Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
                throw "the downloaded price file didn't look right (kept the old one)"
            }
            Move-Item -Path $tmp -Destination $feed -Force
            $res.downloaded = $true
            Write-Log ("new prices: Blizzard {0}, built {1}" -f (Format-Time $got.t), (Format-Time $got.built))
            $disk = $got
        }
        $res.ready = $disk.t
        $res.ok = $true
    } catch {
        $res.error = $_.Exception.Message
        $res.ready = (Read-FeedTimes $feed).t
        Write-Log "check failed: $($res.error)"
    }
    try { $res.inGame = Read-InGame $found } catch { }
    return $res
}

# ---------------------------------------------------------------------------------------------------------------
# Start with Windows: a shortcut in the Startup folder
# ---------------------------------------------------------------------------------------------------------------
$StartupLink = Join-Path ([Environment]::GetFolderPath('Startup')) 'Wolf prices.lnk'
function Set-Startup([bool]$on) {
    if ($on) {
        $sh = New-Object -ComObject WScript.Shell
        $lnk = $sh.CreateShortcut($StartupLink)
        $lnk.TargetPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
        $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
        $lnk.WorkingDirectory = $PSScriptRoot
        $lnk.IconLocation = (Join-Path $PSScriptRoot 'wolf.ico')
        $lnk.Description = 'The Wolf of Booty Bay: fresh prices'
        $lnk.Save()
    } elseif (Test-Path $StartupLink) {
        Remove-Item -Path $StartupLink -Force
    }
}

# ---------------------------------------------------------------------------------------------------------------
# -Once: a check in the console
# ---------------------------------------------------------------------------------------------------------------
$cfg = Get-Config
if ($Once) {
    $found = Resolve-Addon $cfg $false
    if (-not $found) { Write-Output 'Wolf of Booty Bay not found.'; exit 1 }
    $r = Update-Prices $found
    Write-Output ("addon: {0}" -f $found.addon)
    Write-Output ("on disk: {0}   in game: {1}   downloaded: {2}   error: {3}" -f (Format-Time $r.ready), (Format-Time $r.inGame), $r.downloaded, $r.error)
    exit 0
}

# ---------------------------------------------------------------------------------------------------------------
# The tray
# ---------------------------------------------------------------------------------------------------------------
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# one at a time
$created = $false
$mutex = New-Object System.Threading.Mutex($true, 'Local\WolfPricesCompanion', [ref]$created)
if (-not $created) {
    [System.Windows.Forms.MessageBox]::Show('Wolf prices is already running (the wolf by the clock).', 'Wolf of Booty Bay') | Out-Null
    exit 0
}

$found = Resolve-Addon $cfg $true
if (-not $found) {
    [System.Windows.Forms.MessageBox]::Show("Couldn't find The Wolf of Booty Bay in World of Warcraft's folder. Install the addon first, then start this again.", 'Wolf of Booty Bay') | Out-Null
    exit 1
}
Write-Log "started: $($found.addon)"

if (-not $cfg.askedStartup) {
    $a = [System.Windows.Forms.MessageBox]::Show("Start Wolf prices with Windows?`n`nIt checks for new prices every 15 minutes and sits by the clock. You can change this from its menu.",
        'Wolf of Booty Bay', [System.Windows.Forms.MessageBoxButtons]::YesNo)
    Set-Startup ($a -eq [System.Windows.Forms.DialogResult]::Yes)
    $cfg.askedStartup = $true
    Save-Config $cfg
}

$tray = New-Object System.Windows.Forms.NotifyIcon
$iconFile = Join-Path $PSScriptRoot 'wolf.ico'
if (Test-Path $iconFile) { $tray.Icon = New-Object System.Drawing.Icon $iconFile } else { $tray.Icon = [System.Drawing.SystemIcons]::Information }
$tray.Text = 'Wolf prices: checking...'
$tray.Visible = $true

$menu = New-Object System.Windows.Forms.ContextMenuStrip
$status = $menu.Items.Add('Checking...')
$status.Enabled = $false
$checkNow = $menu.Items.Add('Check now')
$openFolder = $menu.Items.Add('Open the addon folder')
$startup = New-Object System.Windows.Forms.ToolStripMenuItem 'Start with Windows'
$startup.CheckOnClick = $true
$startup.Checked = (Test-Path $StartupLink)
$menu.Items.Add($startup) | Out-Null
$menu.Items.Add('-') | Out-Null
$quit = $menu.Items.Add('Quit')
$tray.ContextMenuStrip = $menu

$script:lastNotified = [int64]0
function Invoke-Check([bool]$byHand) {
    $r = Update-Prices $found
    $ready = Format-Time $r.ready
    if ($r.inGame -gt 0 -and $r.inGame -ge $r.ready) {
        $line = "Up to date: $ready"
    } elseif ($r.inGame -gt 0) {
        $line = "In game: $(Format-Time $r.inGame) - ready: $ready, /reload"
    } else {
        $line = "Ready: $ready"
    }
    if (-not $r.ok) { $line = "Couldn't check (offline?) - $ready" }
    $status.Text = $line
    # the tray's hover is limited to 63 letters
    $tip = "Wolf prices - $line"
    if ($tip.Length -gt 63) { $tip = $tip.Substring(0, 63) }
    $tray.Text = $tip
    if ($r.downloaded -and $r.ready -gt $script:lastNotified) {
        $script:lastNotified = $r.ready
        $tray.ShowBalloonTip(8000, 'New prices ready', "Blizzard's prices of $ready are in your addon. Type /reload in game to load them.", [System.Windows.Forms.ToolTipIcon]::Info)
    } elseif ($byHand) {
        $tray.ShowBalloonTip(4000, 'Wolf prices', $line, [System.Windows.Forms.ToolTipIcon]::Info)
    }
}

$checkNow.add_Click({ Invoke-Check $true })
$openFolder.add_Click({ Start-Process explorer.exe $found.addon })
$startup.add_Click({ Set-Startup $startup.Checked })
$quit.add_Click({
    $tray.Visible = $false
    $tray.Dispose()
    [System.Windows.Forms.Application]::Exit()
})
$tray.add_MouseDoubleClick({ Invoke-Check $true })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $EveryMinutes * 60 * 1000
$timer.add_Tick({ Invoke-Check $false })
$timer.Start()

# the first check a moment after starting (the tray is up first)
$first = New-Object System.Windows.Forms.Timer
$first.Interval = 2000
$first.add_Tick({ $first.Stop(); Invoke-Check $false })
$first.Start()

$ctx = New-Object System.Windows.Forms.ApplicationContext
[System.Windows.Forms.Application]::Run($ctx)
$mutex.ReleaseMutex()
