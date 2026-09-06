# Force UTF-8 so PowerShell output piped to other shells (Git Bash, etc.) is not garbled.
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [System.Text.Encoding]::UTF8

# Launch Claude Code with bypassPermissions available in the Shift+Tab cycle (not active by default).
function cc { claude --allow-dangerously-skip-permissions @args }

# Launch Claude Code with an outbound proxy (VPN mixed port 7897) for external downloads.
# bigmodel.cn stays direct via NO_PROXY; falls back to plain cc if the port is dead.
function ccp {
    $proxyUp = $false
    $c = New-Object Net.Sockets.TcpClient
    try { $proxyUp = $c.ConnectAsync('127.0.0.1', 7897).Wait(500) -and $c.Connected } catch {}
    finally { $c.Dispose() }

    if ($proxyUp) {
        $env:HTTP_PROXY = 'http://127.0.0.1:7897'; $env:HTTPS_PROXY = $env:HTTP_PROXY
        $env:http_proxy = $env:HTTP_PROXY; $env:https_proxy = $env:HTTP_PROXY
        $env:NO_PROXY = 'localhost,127.0.0.1,::1,bigmodel.cn'; $env:no_proxy = $env:NO_PROXY
    } else {
        Write-Warning 'ccp: 127.0.0.1:7897 not reachable - starting WITHOUT proxy (start your VPN, or use cc).'
        Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:http_proxy, Env:https_proxy -ErrorAction SilentlyContinue
    }
    claude --allow-dangerously-skip-permissions @args
}
