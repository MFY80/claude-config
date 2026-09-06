# Shared incremental token-usage scanner for cc transcripts. Dot-source this file.
# Transcripts are append-only JSONL: we cache a byte offset per file and parse
# only newly appended lines, so rescans are O(new bytes), not O(file).
# Cache: %TEMP%\cc_token_state\<sid>.scan.json  (auto full-rescan if a file shrank,
# which happens on compact/rewind).

function Scan-File-Incremental {
    param([string]$Path, [hashtable]$State)
    if (-not $State) { $State = @{ off = [long]0; i = [long]0; o = [long]0; c = [long]0; w = [long]0; ctx = [long]0; lastId = '' } }
    try {
        $fi = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
        if (-not $fi) { return $State }
        $size = [long]$fi.Length
        if ($size -lt [long]$State.off) {
            $State.off = [long]0; $State.i = [long]0; $State.o = [long]0
            $State.c = [long]0; $State.w = [long]0; $State.ctx = [long]0; $State.lastId = ''
        }
        if ($size -le [long]$State.off) { return $State }

        $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $got = 0
        try {
            $null = $fs.Seek([long]$State.off, [System.IO.SeekOrigin]::Begin)
            $toRead = [int]($size - [long]$State.off)
            $bytes = New-Object byte[] $toRead
            while ($got -lt $toRead) {
                $n = $fs.Read($bytes, $got, $toRead - $got)
                if ($n -le 0) { break }
                $got += $n
            }
        } finally { $fs.Close() }
        if ($got -le 0) { return $State }

        $nl = -1
        for ($k = $got - 1; $k -ge 0; $k--) { if ($bytes[$k] -eq 10) { $nl = $k; break } }
        if ($nl -lt 0) { return $State }   # no fully-written line yet

        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 0, $nl + 1)
        foreach ($line in ($text -split "`n")) {
            if ($line.EndsWith("`r")) { $line = $line.Substring(0, $line.Length - 1) }
            if ($line -notmatch '"usage"') { continue }
            $e = $null
            try { $e = $line | ConvertFrom-Json } catch { continue }
            if ($e.type -ne 'assistant') { continue }
            $u = $e.message.usage
            if (-not $u) { continue }
            $mid = ''
            if ($e.message.id) { $mid = [string]$e.message.id }
            if ($mid -and $mid -eq [string]$State.lastId) { continue }
            if ($mid) { $State.lastId = $mid }
            $State.i += [long]$u.input_tokens
            $State.o += [long]$u.output_tokens
            $State.c += [long]$u.cache_read_input_tokens
            $State.w += [long]$u.cache_creation_input_tokens
            $State.ctx = [long]$u.input_tokens + [long]$u.cache_read_input_tokens + [long]$u.cache_creation_input_tokens + [long]$u.output_tokens
        }
        $State.off += [long]($nl + 1)
    } catch {}
    return $State
}

function Get-TokenStats {
    param([string]$TranscriptPath, [string]$Sid, [switch]$IncludeSubagents)
    $dir = Join-Path $env:TEMP 'cc_token_state'
    $cachePath = $null
    if ($Sid) { $cachePath = Join-Path $dir ($Sid + '.scan.json') }

    $main = @{ off = [long]0; i = [long]0; o = [long]0; c = [long]0; w = [long]0; ctx = [long]0; lastId = '' }
    $subs = @{}
    if ($cachePath -and (Test-Path -LiteralPath $cachePath)) {
        try {
            $c = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
            if ($c.main) {
                $main.off = [long]$c.main.off; $main.i = [long]$c.main.i; $main.o = [long]$c.main.o
                $main.c = [long]$c.main.c; $main.w = [long]$c.main.w; $main.ctx = [long]$c.main.ctx; $main.lastId = [string]$c.main.lastId
            }
            if ($c.subs) {
                foreach ($p in $c.subs.PSObject.Properties) {
                    $subs[$p.Name] = @{ off = [long]$p.Value.off; i = [long]$p.Value.i; o = [long]$p.Value.o; c = [long]$p.Value.c; w = [long]$p.Value.w; ctx = [long]0; lastId = [string]$p.Value.lastId }
                }
            }
        } catch {}
    }

    if ($TranscriptPath -and (Test-Path -LiteralPath $TranscriptPath)) {
        $main = Scan-File-Incremental -Path $TranscriptPath -State $main
        if ($IncludeSubagents) {
            # subagents live at <project>\<session-id>\subagents\ — the dir named
            # after the transcript file itself, not the project dir
            $base = [System.IO.Path]::GetFileNameWithoutExtension($TranscriptPath)
            $sdir = Join-Path (Join-Path (Split-Path -Parent $TranscriptPath) $base) 'subagents'
            if (Test-Path -LiteralPath $sdir) {
                foreach ($f in (Get-ChildItem -LiteralPath $sdir -Filter *.jsonl -ErrorAction SilentlyContinue)) {
                    $st = $subs[$f.Name]
                    if (-not $st) { $st = @{ off = [long]0; i = [long]0; o = [long]0; c = [long]0; w = [long]0; ctx = [long]0; lastId = '' } }
                    $st = Scan-File-Incremental -Path $f.FullName -State $st
                    $subs[$f.Name] = $st
                }
            }
        }
    }

    $si = [long]0; $so = [long]0; $sc = [long]0; $sw = [long]0
    foreach ($k in @($subs.Keys)) { $si += [long]$subs[$k].i; $so += [long]$subs[$k].o; $sc += [long]$subs[$k].c; $sw += [long]$subs[$k].w }

    if ($cachePath) {
        try {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            @{ main = $main; subs = $subs } |
                ConvertTo-Json -Depth 6 -Compress |
                Set-Content -LiteralPath $cachePath -Encoding UTF8
        } catch {}
    }
    return @{ i = ([long]$main.i + $si); o = ([long]$main.o + $so); c = ([long]$main.c + $sc); w = ([long]$main.w + $sw); ctx = [long]$main.ctx }
}
