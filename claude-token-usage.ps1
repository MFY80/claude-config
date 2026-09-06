# Stop hook - report token usage after each turn.
# Scans the session transcript incrementally via cc-token-scan.ps1 (shared cache
# with the statusline), keeps a per-session baseline in %TEMP% so it can show
# both this turn's delta and the session cumulative total.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'SilentlyContinue'

$raw = $null
try {
    # read raw bytes and decode UTF-8 explicitly; [Console]::In would decode
    # piped stdin with the system GBK codepage and mangle non-ASCII payloads
    $ms = New-Object System.IO.MemoryStream
    [Console]::OpenStandardInput().CopyTo($ms)
    $raw = [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
} catch { $raw = [Console]::In.ReadToEnd() }
$Log = Join-Path $env:TEMP 'cc_hook_debug.log'
trap { try { [System.IO.File]::AppendAllText($Log, ("ERR " + (Get-Date -Format 'HH:mm:ss.fff') + " " + $_) + "`n") } catch {}; continue }
try { [System.IO.File]::AppendAllText($Log, ("IN  " + (Get-Date -Format 'HH:mm:ss.fff') + " [stop] len=" + $raw.Length) + "`n") } catch {}
try { $hook = $raw | ConvertFrom-Json } catch { exit 0 }
$tp  = $hook.transcript_path
$sid = $hook.session_id
if (-not $tp -or -not (Test-Path -LiteralPath $tp)) { exit 0 }

. '__CLAUDE_DIR__/cc-token-scan.ps1'
$stats = Get-TokenStats -TranscriptPath $tp -Sid $sid -IncludeSubagents
$iTok = [long]$stats.i; $oTok = [long]$stats.o; $cTok = [long]$stats.c; $wTok = [long]$stats.w
$total = $iTok + $oTok + $cTok + $wTok
if ($total -le 0) { exit 0 }

# Per-session baseline for the per-turn delta; reset if any counter shrank
# (compact/rewind rewrites the transcript from scratch).
$dI = $iTok; $dO = $oTok; $dC = $cTok; $dW = $wTok
try {
    if ($sid) {
        $dir = Join-Path $env:TEMP 'cc_token_state'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $sf = Join-Path $dir ($sid + '.json')
        if (Test-Path -LiteralPath $sf) {
            $p = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
            if ($iTok -ge [long]$p.i) { $dI = $iTok - [long]$p.i } else { $dI = $iTok }
            if ($oTok -ge [long]$p.o) { $dO = $oTok - [long]$p.o } else { $dO = $oTok }
            if ($cTok -ge [long]$p.c) { $dC = $cTok - [long]$p.c } else { $dC = $cTok }
            if ($wTok -ge [long]$p.w) { $dW = $wTok - [long]$p.w } else { $dW = $wTok }
        }
        Set-Content -LiteralPath $sf -Value (@{ i = $iTok; o = $oTok; c = $cTok; w = $wTok; li = $dI; lo = $dO; lc = $dC; lw = $dW; lt = ($dI + $dO + $dC + $dW) } | ConvertTo-Json -Compress) -Encoding UTF8
    }
} catch {}

function F([long]$n) {
    if ($n -ge 1000000) { '{0:N2}M' -f ($n / 1MB) }
    elseif ($n -ge 1000) { '{0:N1}k' -f ($n / 1KB) }
    else { $n.ToString() }
}
$msg = "Token 用量 - 本轮 {0} (输入 {1} / 输出 {2} / 缓存写 {3} / 缓存读 {4}) · 会话累计 {5}" -f `
    (F ($dI + $dO + $dC + $dW)), (F $dI), (F $dO), (F $dW), (F $dC), (F $total)
@{ systemMessage = $msg } | ConvertTo-Json -Compress
exit 0
