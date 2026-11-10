# Shared-desktop input tests require an exclusive custom Terminal session.
# Microsoft-packaged stock Terminal can stay open (including the caller's WSL).
function Assert-HudDesktopIsolation([int[]]$OwnedProcessIds = @()) {
    $others=@(Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Where-Object {
        $_.Id -notin $OwnedProcessIds -and
        $_.Path -notmatch '\\WindowsApps\\Microsoft\.WindowsTerminal(?:Preview|Canary)?_[^\\]+\\WindowsTerminal\.exe$'
    })
    if ($others.Count) {
        throw 'Close other custom/unpackaged Terminal windows before desktop input tests. Stock Terminal may stay open. The test stopped before further input.'
    }
}
