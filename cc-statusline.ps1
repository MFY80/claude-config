# Statusline - last completed turn's token usage + context window percentage.
# Scans the session transcript incrementally via cc-token-scan.ps1 (cached byte
# offsets, so long-task transcripts stay fast). The last-turn value is written
# by the Stop hook (claude-token-usage.ps1).
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
try { [System.IO.File]::AppendAllText($Log, ("IN  " + (Get-Date -Format 'HH:mm:ss.fff') + " len=" + $raw.Length) + "`n") } catch {}
try { $s = $raw | ConvertFrom-Json } catch { exit 0 }
$tp  = $s.transcript_path
$sid = $s.session_id
$model = $s.model.display_name

. 'C:/Users/Administrator/.claude/cc-token-scan.ps1'
$stats = Get-TokenStats -TranscriptPath $tp -Sid $sid -IncludeSubagents

# last completed turn (written by the Stop hook)
$lt = [long]0; $li = [long]0; $lo = [long]0; $lc = [long]0
if ($sid) {
    $sf = Join-Path (Join-Path $env:TEMP 'cc_token_state') ($sid + '.json')
    if (Test-Path -LiteralPath $sf) {
        $st = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
        $lt = [long]$st.lt; $li = [long]$st.li; $lo = [long]$st.lo
        $lc = [long]$st.lc + [long]$st.lw
    }
}

$win = 200000
if ($env:CLAUDE_CODE_AUTO_COMPACT_WINDOW) { $win = [int]$env:CLAUDE_CODE_AUTO_COMPACT_WINDOW }
$pct = if ($win -gt 0) { [math]::Round(100.0 * $stats.ctx / $win, 1) } else { 0 }

function F([long]$n) {
    if ($n -ge 1000000) { '{0:N2}M' -f ($n / 1MB) }
    elseif ($n -ge 1000) { '{0:N1}k' -f ($n / 1KB) }
    else { $n.ToString() }
}

$esc = [char]27
$cRst = "$esc[0m"; $cDim = "$esc[2m"; $cYel = "$esc[33m"; $cGrn = "$esc[32m"; $cRed = "$esc[31m"
$ctxCol = if ($pct -ge 80) { $cRed } elseif ($pct -ge 60) { $cYel } else { $cGrn }
$winTxt = if ($win -ge 1000000) { '{0:N0}M' -f ($win / 1MB) } else { '{0:N0}k' -f ($win / 1KB) }

$line = "⚡ 本轮 $($cYel)$(F $lt)$cRst $cDim(输入 $(F $li) / 输出 $(F $lo) / 缓存 $(F $lc))$cRst" +
        " $cDim│$cRst 上下文 $ctxCol$pct%$cRst $cDim($(F $stats.ctx) / $winTxt)$cRst" +
        " $cDim│ $model$cRst"
try { [System.IO.File]::AppendAllText($Log, ("OUT " + (Get-Date -Format 'HH:mm:ss.fff') + " pct=$pct lt=$lt") + "`n") } catch {}
Write-Output $line
exit 0
