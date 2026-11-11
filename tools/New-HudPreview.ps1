# Prepare an isolated portable preview. Normal Terminal startup is the default.
#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RuntimeDirectory,
    [Parameter(Mandatory)][string]$DestinationDirectory,
    [string]$SettingsPath = (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    [switch]$UseTemporaryHudKeys
)

$ErrorActionPreference = 'Stop'
$runtime = (Get-Item -LiteralPath $RuntimeDirectory).FullName
$DestinationDirectory = [System.IO.Path]::GetFullPath($DestinationDirectory)
$runtimePrefix = $runtime.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($DestinationDirectory.Equals($runtime, [System.StringComparison]::OrdinalIgnoreCase) -or
    $DestinationDirectory.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'DestinationDirectory must be outside RuntimeDirectory to prevent recursive copying.'
}
foreach ($file in @('WindowsTerminal.exe', 'resources.pri')) {
    if (-not (Test-Path -LiteralPath (Join-Path $runtime $file))) {
        throw "RuntimeDirectory must contain a prepared unpackaged build ($file is missing)."
    }
}
if (Test-Path -LiteralPath $DestinationDirectory) {
    throw 'DestinationDirectory must be new. Existing previews and settings are preserved.'
}
$settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json -AsHashtable
if ($UseTemporaryHudKeys) {
    $temporaryKeys = @('win+sc(41)', 'win+shift+sc(41)', 'ctrl+alt+f9', 'ctrl+alt+f10', 'win+ctrl+sc(41)')
    $settings.keybindings = @($settings.keybindings | Where-Object { $null -ne $_ -and $_.keys -notin $temporaryKeys }) + @(
        @{ keys = 'win+sc(41)'; command = 'unbound' },
        @{ keys = 'win+shift+sc(41)'; command = 'unbound' },
        @{ keys = 'ctrl+alt+f9'; id = 'Terminal.HudMode' },
        @{ keys = 'ctrl+alt+f10'; id = 'Terminal.HudVisibility' }
    )
}
$destination = (New-Item -ItemType Directory -Path $DestinationDirectory).FullName
& robocopy.exe $runtime $destination /E /XF *.pdb /XD settings /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "Runtime copy failed: $LASTEXITCODE" }
New-Item -ItemType File -Path (Join-Path $destination '.portable') -Force | Out-Null
$settingsDirectory = New-Item -ItemType Directory -Path (Join-Path $destination 'settings') -Force
$settings | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $settingsDirectory.FullName 'settings.json') -Encoding utf8NoBOM
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut((Join-Path $destination 'Start-Terminal.lnk'))
$shortcut.TargetPath = Join-Path $destination 'WindowsTerminal.exe'
$shortcut.Arguments = '-w new'
$shortcut.WorkingDirectory = $destination
$shortcut.IconLocation = $shortcut.TargetPath + ',0'
$shortcut.Save()
$interactionKey = if ($UseTemporaryHudKeys) { 'Ctrl+Alt+F9' } else { 'Win+Backtick' }
$visibilityKey = if ($UseTemporaryHudKeys) { 'Ctrl+Alt+F10' } else { 'Win+Shift+Backtick' }
@"
Windows Terminal with optional HUD mode

Open Start-Terminal.lnk. It opens an ordinary Terminal window using a private
copy of your settings. Installed Terminal settings and OS defaults are unchanged.

$interactionKey`: toggle visible HUD Active/Passive.
$visibilityKey`: create/summon/hide the dedicated HUD, like Quake.
Alt+Backtick: Quake. Escape passes through.

Change bindings in Settings > Actions.
Change HUD Active opacity in Settings > Appearance (0-100%, default 35%).
Normal appearance follows your profiles. Passive HUD backgrounds are transparent.

This is an unpackaged Debug preview requiring the local Visual Studio runtime.
"@ | Set-Content -LiteralPath (Join-Path $destination 'README.txt') -Encoding utf8NoBOM
Write-Output "Preview ready: $destination"
