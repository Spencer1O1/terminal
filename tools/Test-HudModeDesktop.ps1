# Native desktop regression for a prepared, unpackaged HUD fork runtime.
# Launches private copies with isolated settings and injects guarded test input.
#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RuntimeDirectory,
    [string]$ArtifactDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) ('wt-hud-desktop-' + [guid]::NewGuid().ToString('N')))
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'HudModeTests\DesktopIsolation.ps1')
$runtime = (Get-Item -LiteralPath $RuntimeDirectory).FullName
$ArtifactDirectory = [System.IO.Path]::GetFullPath($ArtifactDirectory)
$runtimePrefix = $runtime.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
if ($ArtifactDirectory.Equals($runtime, [System.StringComparison]::OrdinalIgnoreCase) -or
    $ArtifactDirectory.StartsWith($runtimePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'ArtifactDirectory must be outside RuntimeDirectory to prevent recursive copying.'
}
if (-not (Test-Path -LiteralPath (Join-Path $runtime 'WindowsTerminal.exe'))) {
    throw 'RuntimeDirectory must contain the built fork and its prepared runtime dependencies.'
}
if (Test-Path -LiteralPath $ArtifactDirectory) {
    throw 'ArtifactDirectory must be a new directory; existing files are preserved.'
}
Assert-HudDesktopIsolation
$evidence = (New-Item -ItemType Directory -Path $ArtifactDirectory).FullName
Write-Output "Desktop test artifacts: $evidence"
Start-Transcript -Path (Join-Path $evidence 'desktop-output.txt') | Out-Null
try {
    $copy=Join-Path $evidence 'runtime'
    & robocopy.exe $runtime $copy /E /XF *.pdb /XD settings /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Runtime copy failed: $LASTEXITCODE" }
    New-Item -ItemType File -Path (Join-Path $copy '.hud-test-fixture') | Out-Null
    & (Join-Path $PSScriptRoot 'HudModeTests\Invoke-DesktopFixture.ps1') -Executable (Join-Path $copy 'WindowsTerminal.exe') -EvidenceDirectory $evidence
} finally {
    Stop-Transcript | Out-Null
}
