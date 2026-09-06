#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code user config sync between ~/.claude and this repo.

.DESCRIPTION
    .\sync.ps1 push     ~/.claude -> repo (API token sanitized out), then git commit + push
    .\sync.ps1 pull     repo -> ~/.claude (API token restored; prompts on first run)
    .\sync.ps1 status   show which synced items differ between ~/.claude and repo

    The real API token never enters this repo: on push it is replaced with the
    placeholder below; on pull it is read back from %USERPROFILE%\.claude\.sync-token
    (git-ignored, lives outside this repo). Absolute paths to ~/.claude inside
    settings.json and the hook/statusline scripts are likewise replaced with
    __CLAUDE_DIR__ on push and restored to the local machine's path on pull, so
    hooks and the statusline work on any username/drive. Sync is
    last-write-wins, no merging.
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet('push', 'pull', 'status')]
    [string]$Action = 'status'
)

$ErrorActionPreference = 'Stop'

$Repo        = $PSScriptRoot
$ClaudeDir   = Join-Path $HOME '.claude'
$ClaudeDirFwd = $ClaudeDir -replace '\\', '/'
$TokenFile   = Join-Path $ClaudeDir '.sync-token'
$Placeholder = '__CLAUDE_API_TOKEN__'
$PathPlaceholder = '__CLAUDE_DIR__'
$Utf8NoBom   = New-Object System.Text.UTF8Encoding($false)

# Files synced verbatim (repo-relative, also relative to ~/.claude)
$Files = @(
    'settings.json',
    '.claude.json',
    'cc-statusline.ps1',
    'cc-token-scan.ps1',
    'claude-toast.ps1',
    'claude-token-usage.ps1',
    'plugins\installed_plugins.json',
    'plugins\known_marketplaces.json'
)
# Files that may embed absolute paths to ~/.claude (rewritten to/from
# $PathPlaceholder on push/pull so the repo stays device-independent)
$PathFiles = @(
    'settings.json',
    'cc-statusline.ps1',
    'cc-token-scan.ps1',
    'claude-toast.ps1',
    'claude-token-usage.ps1'
)
# Distributions synced wholesale
$Dirs = @('skills')

# Repo-relative files whose source lives outside ~/.claude
$Overrides = @{
    '.claude.json' = Join-Path $HOME '.claude.json'
}

function Get-LocalPath([string]$Rel) {
    if ($Overrides.ContainsKey($Rel)) { return $Overrides[$Rel] }
    return Join-Path $ClaudeDir $Rel
}

function Read-AllText([string]$Path) {
    [System.IO.File]::ReadAllText($Path)
}

function Write-AllText([string]$Path, [string]$Text) {
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Text, $Utf8NoBom)
}

function Get-LocalToken {
    if (Test-Path $TokenFile) {
        $t = (Read-AllText $TokenFile).Trim()
        if ($t) { return $t }
    }
    return $null
}

function ConvertTo-RepoSettings([string]$Text) {
    # real token -> placeholder (the repo copy must stay clean)
    return [regex]::Replace($Text, '("ANTHROPIC_AUTH_TOKEN"\s*:\s*")[^"]*(")', "`${1}$Placeholder`${2}")
}

function ConvertTo-LocalSettings([string]$Text, [string]$Token) {
    return [regex]::Replace($Text, '("ANTHROPIC_AUTH_TOKEN"\s*:\s*")[^"]*(")', "`${1}$Token`${2}")
}

function ConvertTo-RepoPaths([string]$Text) {
    # this machine's ~/.claude (either separator style) -> placeholder
    $pat = '(?i)' + [regex]::Escape($ClaudeDirFwd) + '|' + [regex]::Escape($ClaudeDir)
    return [regex]::Replace($Text, $pat, $PathPlaceholder)
}

function ConvertTo-LocalPaths([string]$Text) {
    return $Text.Replace($PathPlaceholder, $ClaudeDirFwd)
}

function Test-HasBom([string]$Path) {
    $b = New-Object byte[] 3
    $fs = [System.IO.File]::OpenRead($Path)
    try { $n = $fs.Read($b, 0, 3) } finally { $fs.Close() }
    return ($n -eq 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
}

function Write-TextLike([string]$Path, [string]$Text) {
    # rewrite text preserving the file's existing BOM state (PS 5.1 needs a BOM
    # to read UTF-8 .ps1 as UTF-8; without it non-ASCII scripts misparse as GBK)
    $enc = $Utf8NoBom
    if (Test-Path $Path) { $enc = New-Object System.Text.UTF8Encoding((Test-HasBom $Path)) }
    [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

function Copy-FileTo([string]$Src, [string]$Dst) {
    $dir = Split-Path $Dst -Parent
    if (-not (Test-Path $dir)) { New-Item $dir -ItemType Directory -Force | Out-Null }
    Copy-Item $Src $Dst -Force
}

function Copy-Tree([string]$Src, [string]$Dst) {
    if (Test-Path $Dst) { Remove-Item $Dst -Recurse -Force }
    Copy-Item $Src $Dst -Recurse
}

# ---- memory: ~/.claude/projects/<slug>/memory -> repo/memory/<slug>/ ----
function Get-MemorySlugs {
    $root = Join-Path $ClaudeDir 'projects'
    if (-not (Test-Path $root)) { return @() }
    return @(Get-ChildItem $root -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'memory') })
}

function Push-Memory {
    $repoMem = Join-Path $Repo 'memory'
    if (Test-Path $repoMem) { Remove-Item $repoMem -Recurse -Force }
    New-Item $repoMem -ItemType Directory -Force | Out-Null
    foreach ($p in Get-MemorySlugs) {
        Copy-Tree (Join-Path $p.FullName 'memory') (Join-Path $repoMem $p.Name)
    }
    if (-not (Get-ChildItem $repoMem -Force | Where-Object Name -ne '.gitkeep')) {
        Write-AllText (Join-Path $repoMem '.gitkeep') ''
    }
}

function Pull-Memory {
    $repoMem = Join-Path $Repo 'memory'
    if (-not (Test-Path $repoMem)) { return }
    foreach ($d in (Get-ChildItem $repoMem -Directory)) {
        Copy-Tree $d.FullName (Join-Path (Join-Path (Join-Path $ClaudeDir 'projects') $d.Name) 'memory')
    }
}

# ---- actions ----
function Invoke-Push {
    foreach ($f in $Files) {
        $src = Get-LocalPath $f
        $dst = Join-Path $Repo $f
        if (-not (Test-Path $src)) { Write-Host "  skip (not found): $f" -ForegroundColor Yellow; continue }
        Copy-FileTo $src $dst
    }
    foreach ($d in $Dirs) {
        $src = Join-Path $ClaudeDir $d
        if (-not (Test-Path $src)) { Write-Host "  skip (not found): $d" -ForegroundColor Yellow; continue }
        Copy-Tree $src (Join-Path $Repo $d)
    }
    Push-Memory

    # device-specific content must not enter the repo:
    # token -> $Placeholder, absolute ~/.claude paths -> $PathPlaceholder
    foreach ($f in $PathFiles) {
        $rp = Join-Path $Repo $f
        if (-not (Test-Path $rp)) { continue }
        $raw = Read-AllText $rp
        $clean = $raw
        if ($f -eq 'settings.json') { $clean = ConvertTo-RepoSettings $clean }
        $clean = ConvertTo-RepoPaths $clean
        if ($clean -ne $raw) {
            Write-TextLike $rp $clean
            Write-Host "  sanitized: $f (token/path -> placeholders)"
        }
    }

    git -C $Repo add -A
    if (git -C $Repo status --porcelain) {
        git -C $Repo commit -m "sync: update claude config $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        $branch = git -C $Repo rev-parse --abbrev-ref HEAD
        if (git -C $Repo config "branch.$branch.remote") { git -C $Repo push }
        else { git -C $Repo push -u origin $branch }
        Write-Host 'pushed to origin.' -ForegroundColor Green
    }
    else {
        Write-Host 'no changes to push.'
    }
}

function Invoke-Pull {
    # token: needed to restore settings.json; cache on first run
    $token = Get-LocalToken
    if (-not $token) {
        Write-Host "本地未缓存 API Token（$TokenFile）" -ForegroundColor Yellow
        $secure = Read-Host '请粘贴 ANTHROPIC_AUTH_TOKEN（输入不回显）' -AsSecureString
        $token = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
        if (-not $token) { throw '未输入 token，中止 pull。' }
        Write-AllText $TokenFile $token
        Write-Host "token 已缓存到 $TokenFile" -ForegroundColor Green
    }

    # back up local settings/state that is about to be overwritten
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($f in @('settings.json', '.claude.json')) {
        $local = Get-LocalPath $f
        $incoming = Join-Path $Repo $f
        if ((Test-Path $local) -and (Test-Path $incoming) -and
            (Get-FileHash $local).Hash -ne (Get-FileHash $incoming).Hash) {
            $bak = Join-Path (Join-Path $ClaudeDir "backups\sync-$stamp") $f
            Copy-FileTo $local $bak
            Write-Host "  backed up: $f -> backups\sync-$stamp\"
        }
    }

    foreach ($f in $Files) {
        $src = Join-Path $Repo $f
        if (-not (Test-Path $src)) { Write-Host "  skip (not in repo): $f" -ForegroundColor Yellow; continue }
        Copy-FileTo $src (Get-LocalPath $f)
    }
    foreach ($d in $Dirs) {
        $src = Join-Path $Repo $d
        if (Test-Path $src) { Copy-Tree $src (Join-Path $ClaudeDir $d) }
    }
    Pull-Memory

    # restore device-local paths inside settings/scripts (placeholder -> this
    # machine's ~/.claude), so hooks/statusline work regardless of username
    foreach ($f in $PathFiles) {
        $p = Get-LocalPath $f
        if (-not (Test-Path $p)) { continue }
        $t = Read-AllText $p
        $t2 = ConvertTo-LocalPaths $t
        if ($t2 -ne $t) { Write-TextLike $p $t2; Write-Host "  localized: $f" }
    }

    # restore real token into local settings.json
    $lp = Get-LocalPath 'settings.json'
    if (Test-Path $lp) {
        $t = Read-AllText $lp
        Write-TextLike $lp (ConvertTo-LocalSettings $t $token)
    }
    Write-Host 'pulled to ~/.claude.' -ForegroundColor Green
}

function Get-TreeSig([string]$Path) {
    if (-not (Test-Path $Path)) { return @() }
    Get-ChildItem $Path -Recurse -File -Force | Where-Object Name -ne '.gitkeep' | ForEach-Object {
        $rel = $_.FullName.Substring($Path.Length).TrimStart('\')
        "$rel=" + (Get-FileHash $_.FullName -Algorithm SHA256).Hash
    }
}

function Test-SigDiff($A, $B) {
    $A = @($A); $B = @($B)
    if ($A.Count -ne $B.Count) { return $true }
    $set = [System.Collections.Generic.HashSet[string]]::new([string[]]$A)
    foreach ($x in $B) { if (-not $set.Contains($x)) { return $true } }
    return $false
}

function Invoke-Status {
    $diffs = @()
    foreach ($f in $Files) {
        $local = Get-LocalPath $f
        $repoF = Join-Path $Repo $f
        if (-not (Test-Path $local) -and -not (Test-Path $repoF)) { continue }
        if (-not (Test-Path $local)) { $diffs += "only in repo:   $f"; continue }
        if (-not (Test-Path $repoF)) { $diffs += "only local:    $f"; continue }
        if ((Get-FileHash $local).Hash -ne (Get-FileHash $repoF).Hash) {
            if ($f -eq 'settings.json') {
                # repo copy holds a placeholder, compare against sanitized local
                if ((Read-AllText $repoF) -ne (ConvertTo-RepoSettings (Read-AllText $local))) { $diffs += "differ:        $f" }
            }
            else { $diffs += "differ:        $f" }
        }
    }
    foreach ($d in $Dirs) {
        $a = Get-TreeSig (Join-Path $ClaudeDir $d)
        $b = Get-TreeSig (Join-Path $Repo $d)
        if (Test-SigDiff $a $b) { $diffs += "differ:        $d" }
    }
    $localMem = @(Get-MemorySlugs | ForEach-Object {
        $slug = $_.Name
        Get-TreeSig (Join-Path $_.FullName 'memory') | ForEach-Object { "$slug\$_" }
    })
    $repoMemRoot = Join-Path $Repo 'memory'
    $repoMem = @()
    if (Test-Path $repoMemRoot) {
        $repoMem = @(Get-ChildItem $repoMemRoot -Directory | ForEach-Object {
            $slug = $_.Name
            Get-TreeSig $_.FullName | ForEach-Object { "$slug\$_" }
        })
    }
    if (Test-SigDiff $localMem $repoMem) { $diffs += 'differ:        memory/' }

    if ($diffs) { $diffs | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow } }
    else { Write-Host '~/.claude and repo are in sync.' -ForegroundColor Green }
}

switch ($Action) {
    'push'   { Invoke-Push }
    'pull'   { Invoke-Pull }
    'status' { Invoke-Status }
}
