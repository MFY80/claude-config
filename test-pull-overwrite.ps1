# End-to-end pull simulation against a fake HOME that already has config.
# Answers: does pull overwrite or merge? What gets backed up / untouched / deleted?
$ErrorActionPreference = 'Stop'
$repo = Join-Path $HOME 'claude-config'
$fake = Join-Path $env:TEMP 'cc_fakehome'
$fclaude = Join-Path $fake '.claude'
$fwd = ($fclaude -replace '\\', '/')

# --- 1. fake device state: pre-existing config that pull must overwrite ---
Remove-Item $fake -Recurse -Force -ErrorAction SilentlyContinue
New-Item (Join-Path $fclaude 'skills\local-extra') -ItemType Directory -Force | Out-Null
New-Item (Join-Path $fclaude 'plugins') -ItemType Directory -Force | Out-Null
Set-Content (Join-Path $fclaude 'settings.json') '{ "_local": "new-device-only-setting", "model": "opus" }' -Encoding UTF8
Set-Content (Join-Path $fake '.claude.json') '{ "numStartups": 1, "note": "new-device-state" }' -Encoding UTF8
Set-Content (Join-Path $fclaude 'skills\local-extra\SKILL.md') '# extra skill only on new device' -Encoding UTF8
Set-Content (Join-Path $fclaude 'plugins\installed_plugins.json') '{ "version": 2, "plugins": {} }' -Encoding UTF8
Set-Content (Join-Path $fclaude 'untracked.txt') 'not part of the sync manifest' -Encoding UTF8
Set-Content (Join-Path $fclaude '.sync-token') 'DUMMYTOKEN' -Encoding UTF8   # skip interactive prompt

# --- 2. run the REAL pull logic against the fake home ---
$src = [IO.File]::ReadAllText((Join-Path $repo 'sync.ps1'))
$src = $src.Replace('$HOME', '$env:CC_FAKE_HOME').Replace('$PSScriptRoot', "'$repo'")
$fakeSync = Join-Path $env:TEMP 'cc_sync_fake.ps1'
[IO.File]::WriteAllText($fakeSync, $src, [Text.UTF8Encoding]::new($true))
$env:CC_FAKE_HOME = $fake
& $fakeSync pull | Out-Host

# --- 3. assertions ---
$pass = 0; $fail = 0
function Check([string]$Name, [bool]$Ok) {
    if ($Ok) { $script:pass++; Write-Host ("  PASS  " + $Name) }
    else { $script:fail++; Write-Host ("  FAIL  " + $Name) }
}
$s = Get-Content -Raw (Join-Path $fclaude 'settings.json')
Check 'settings.json overwritten by repo version (local "_local" gone)' ($s -notmatch '_local' -and $s -match '"model": "haiku"')
Check 'settings.json token restored from .sync-token' ($s -match '"ANTHROPIC_AUTH_TOKEN": "DUMMYTOKEN"')
Check 'settings.json paths localized to fake device' ($s -match [regex]::Escape($fwd) -and $s -notmatch '__CLAUDE_DIR__')

$bset = Get-ChildItem (Join-Path $fclaude 'backups\*\settings.json') -ErrorAction SilentlyContinue
Check 'old settings.json backed up before overwrite' ($bset -and (Get-Content -Raw $bset[0].FullName) -match '_local')
$bcj = Get-ChildItem (Join-Path $fclaude 'backups\*\.claude.json') -ErrorAction SilentlyContinue
Check 'old .claude.json backed up before overwrite' ($bcj -and (Get-Content -Raw $bcj[0].FullName) -match 'new-device-state')

$fcj = (Get-FileHash (Join-Path $fake '.claude.json')).Hash
$rcj = (Get-FileHash (Join-Path $repo '.claude.json')).Hash
Check '.claude.json overwritten (byte-identical to repo)' ($fcj -eq $rcj)

Check 'repo skill installed (skills\docx\SKILL.md)' (Test-Path (Join-Path $fclaude 'skills\docx\SKILL.md'))
Check 'extra local skill REMOVED (skills\local-extra)' (-not (Test-Path (Join-Path $fclaude 'skills\local-extra')))

$p = Get-Content -Raw (Join-Path $fclaude 'plugins\installed_plugins.json')
Check 'plugin manifest paths localized' ($p -match [regex]::Escape($fwd) -and $p -notmatch '__CLAUDE_DIR__' -and $p -notmatch 'Administrator')

Check 'file outside manifest untouched (untracked.txt)' ((Get-Content -Raw (Join-Path $fclaude 'untracked.txt')) -match 'not part')
Check 'memory pulled into projects\<slug>\memory' (Test-Path (Join-Path $fclaude 'projects\D--cc-workspace\memory\MEMORY.md'))

Write-Host ("`nresult: $pass passed, $fail failed")
Remove-Item $fake -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $fakeSync -Force -ErrorAction SilentlyContinue
if ($fail -gt 0) { exit 1 }
