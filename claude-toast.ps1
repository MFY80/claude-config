# Claude Code hook: Windows toast notification (fire-and-forget, exits immediately).
# Reads the hook JSON payload from stdin; $Fallback is used when the payload has no message.
param([string]$Fallback = 'Claude Code needs your approval')

$ErrorActionPreference = 'SilentlyContinue'

$raw = [Console]::In.ReadToEnd()
$msg = $Fallback
try {
    $j = $raw | ConvertFrom-Json
    if ($j.message) { $msg = $j.message }
} catch {}

[void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
[void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]

$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$esc = [System.Security.SecurityElement]::Escape($msg)
$xml.LoadXml("<toast scenario=""reminder""><visual><binding template=""ToastText02""><text id=""1"">Claude Code</text><text id=""2"">$esc</text></binding></visual><audio src=""ms-winsoundevent:Notification.Default""/></toast>")

$toast = New-Object Windows.UI.Notifications.ToastNotification $xml
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe').Show($toast)
exit 0
