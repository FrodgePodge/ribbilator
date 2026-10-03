# ribbilator: keeps the github contribution graph spelling RIBBIT as a slow ticker.
# one column of the word per week; today's cell is lit (a cluster of empty commits dated today)
# when the font says so. safe to run as often as you like: it does nothing unless a lit day is missing.
#
#   ribbilator.ps1             do today's push (and catch up any missed lit days)
#   ribbilator.ps1 -Preview    print the pattern, change nothing
#   ribbilator.ps1 -DryRun     say what would be committed, change nothing
param(
    [switch]$Preview,
    [switch]$DryRun,
    [string]$Today          # yyyy-MM-dd, for testing only
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$logFile = Join-Path $root 'ribbilator.log'
function Log($m) { $line = "$(Get-Date -Format 's') $m"; Add-Content $logFile $line; Write-Host $line }
function Repo { & git.exe -C $root @args }

$cfg = Get-Content (Join-Path $root 'config.json') -Raw | ConvertFrom-Json
$start = [datetime]::ParseExact($cfg.start, 'yyyy-MM-dd', $null)   # must be a sunday
if ($start.DayOfWeek -ne 'Sunday') { throw "start in config.json must be a sunday" }

# 5x7 font, rows top to bottom = sunday to saturday
$font = @{
    R = '####.', '#...#', '#...#', '####.', '#.#..', '#..#.', '#...#'
    I = '#####', '..#..', '..#..', '..#..', '..#..', '..#..', '#####'
    B = '####.', '#...#', '#...#', '####.', '#...#', '#...#', '####.'
    T = '#####', '..#..', '..#..', '..#..', '..#..', '..#..', '..#..'
}
# build the ticker: one entry per week-column, each a 7-character string of '#' and '.'
$cols = @()
$letters = $cfg.word.ToCharArray()
for ($l = 0; $l -lt $letters.Count; $l++) {
    $glyph = $font[[string]$letters[$l]]
    for ($c = 0; $c -lt 5; $c++) { $cols += (-join (0..6 | ForEach-Object { $glyph[$_][$c] })) }
    if ($l -lt $letters.Count - 1) { $cols += '.......' }
}
for ($g = 0; $g -lt $cfg.gapColumns; $g++) { $cols += '.......' }
$period = $cols.Count

if ($Preview) {
    Write-Host "period: $period weeks (word $($cfg.word.Length * 5 + $cfg.word.Length - 1) + gap $($cfg.gapColumns))"
    0..6 | ForEach-Object { $r = $_; Write-Host (($cols | ForEach-Object { if ($_[$r] -eq '#') { '#' } else { '.' } }) -join '') }
    return
}

function IsLit([datetime]$d) {
    $week = [math]::Floor(($d - $start).Days / 7)
    $col = $cols[$week % $period]
    return $col[[int]$d.DayOfWeek] -eq '#'
}

$todayDate = if ($Today) { [datetime]::ParseExact($Today, 'yyyy-MM-dd', $null) } else { [datetime]::Today }
if ($todayDate -lt $start) { Log "before start date $($cfg.start); nothing to do"; return }

function DoneDates {
    $set = @{}
    $subjects = Repo log --format=%s --grep='^rib ' 2>$null
    foreach ($s in $subjects) { if ($s -match '^rib (\d{4}-\d{2}-\d{2}) \d+/(\d+)$') { $set[$Matches[1]] = [int]$Matches[2] } }
    return $set    # date -> how many commits that day's cluster has
}

# the busiest day on the profile that is NOT ribbilator's own work, read from the public contributions page.
# github shades the graph relative to the busiest day, so the lit pixels must beat this to stay the darkest green.
function RealMax($ribByDate) {
    try {
        $h = (Invoke-WebRequest "https://github.com/users/$($cfg.login)/contributions" -UseBasicParsing -TimeoutSec 20 -Headers @{ 'User-Agent' = 'ribbilator' }).Content
    } catch { return $null }
    $dates = @{}
    foreach ($m in [regex]::Matches($h, 'data-date="(\d{4}-\d{2}-\d{2})" id="(contribution-day-component-\d+-\d+)"')) { $dates[$m.Groups[2].Value] = $m.Groups[1].Value }
    if ($dates.Count -eq 0) { return $null }
    $max = 0
    foreach ($m in [regex]::Matches($h, 'for="(contribution-day-component-\d+-\d+)"[^>]*>\s*(No|\d+) contribution')) {
        if (-not $dates.ContainsKey($m.Groups[1].Value)) { continue }
        $total = if ($m.Groups[2].Value -eq 'No') { 0 } else { [int]$m.Groups[2].Value }
        $date = $dates[$m.Groups[1].Value]
        $rib = if ($ribByDate.ContainsKey($date)) { $ribByDate[$date] } else { 0 }
        $real = $total - $rib
        if ($real -gt $max) { $max = $real }
    }
    return $max
}
function PendingDays {
    $done = DoneDates
    $out = @()
    for ($d = $start; $d -le $todayDate; $d = $d.AddDays(1)) {
        $key = $d.ToString('yyyy-MM-dd')
        if ((IsLit $d) -and -not $done.ContainsKey($key)) { $out += $d }
    }
    return $out
}

$pending = PendingDays
if (-not $pending) { Log 'nothing to do (today is dark, or already done)'; return }

if ($DryRun) { Log "dry run: would commit for $($pending.Count) day(s): $(($pending | ForEach-Object { $_.ToString('yyyy-MM-dd') }) -join ', ')"; return }

# something is pending: sync with the remote first, so a push from the other machine is seen
$null = Repo fetch origin -q 2>$null
if ($LASTEXITCODE -ne 0) { Log 'offline or remote unreachable; will retry next run'; return }
$remoteHasMain = [bool](Repo ls-remote --heads origin main)
if ($remoteHasMain) {
    $null = Repo pull --rebase --autostash -q origin main 2>$null
    if ($LASTEXITCODE -ne 0) { Log 'pull failed; will retry next run'; return }
    $pending = PendingDays
    if (-not $pending) { Log 'the other machine already did it'; return }
}

# auto-tune the cluster size: beat the busiest real day by `headroom`, never below commitsMin or above commitsCap
$tuneFile = Join-Path $root 'tuning.json'
$realMax = RealMax (DoneDates)
if ($null -ne $realMax) {
    @{ realMax = $realMax; checked = (Get-Date -Format 's') } | ConvertTo-Json | Set-Content $tuneFile
} elseif (Test-Path $tuneFile) {
    $realMax = (Get-Content $tuneFile -Raw | ConvertFrom-Json).realMax
    Log "could not read the profile; using the last known busiest real day ($realMax)"
} else { $realMax = 0 }
$target = [int][math]::Min($cfg.commitsCap, [math]::Max($cfg.commitsMin, [math]::Ceiling($realMax * $cfg.headroom)))
$spread = [int][math]::Ceiling($target * $cfg.jitter)
Log "tuning: busiest real day $realMax -> $target to $($target + $spread) commits per lit day"

foreach ($d in $pending) {
    $key = $d.ToString('yyyy-MM-dd')
    $n = [int](Get-Random -Minimum $target -Maximum ($target + $spread + 1))
    for ($i = 1; $i -le $n; $i++) {
        # noon utc on the day itself, so every timezone reading agrees on which day this is
        $stamp = ([datetime]::SpecifyKind($d.AddHours(12).AddSeconds($i), 'Utc')).ToString("yyyy-MM-dd'T'HH:mm:ss'Z'")
        $env:GIT_AUTHOR_DATE = $stamp; $env:GIT_COMMITTER_DATE = $stamp
        Repo -c "user.name=$($cfg.name)" -c "user.email=$($cfg.email)" commit --allow-empty -q -m "rib $key $i/$n"
    }
    Remove-Item Env:GIT_AUTHOR_DATE, Env:GIT_COMMITTER_DATE -ErrorAction SilentlyContinue
    Log "committed $n for $key"
}

$null = Repo push -q origin main 2>$null
if ($LASTEXITCODE -ne 0) {
    $null = Repo pull --rebase -q origin main 2>$null
    $null = Repo push -q origin main 2>$null
}
if ($LASTEXITCODE -ne 0) { Log 'push failed; commits are kept locally and will go out next run' } else { Log 'pushed' }
