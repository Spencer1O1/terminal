# Native desktop regression for a prepared, unpackaged HUD fork runtime.
# Launches private copies with isolated settings and injects guarded test input.
#Requires -Version 7
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RuntimeDirectory,
    [string]$ArtifactDirectory = (Join-Path ([System.IO.Path]::GetTempPath()) ('wt-hud-desktop-' + [guid]::NewGuid().ToString('N')))
)

$ErrorActionPreference = 'Stop'
$runtime = (Get-Item -LiteralPath $RuntimeDirectory).FullName
if (-not (Test-Path -LiteralPath (Join-Path $runtime 'WindowsTerminal.exe'))) {
    throw 'RuntimeDirectory must contain the built fork and its prepared runtime dependencies.'
}
if (Test-Path -LiteralPath $ArtifactDirectory) {
    throw 'ArtifactDirectory must be a new directory; existing files are preserved.'
}
$evidence = (New-Item -ItemType Directory -Path $ArtifactDirectory).FullName
Write-Output "Desktop test artifacts: $evidence"
Start-Transcript -Path (Join-Path $evidence 'desktop-output.txt') | Out-Null
try {
    foreach ($kind in @('fresh', 'converted')) {
        $fixture = Join-Path $evidence $kind
        $copy = Join-Path $fixture 'runtime'
        New-Item -ItemType Directory -Path $fixture | Out-Null
        & robocopy.exe $runtime $copy /E /XF *.pdb /XD settings /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "Runtime copy failed: $LASTEXITCODE" }
        New-Item -ItemType File -Path (Join-Path $copy '.hud-test-fixture') | Out-Null
        $arguments = @{
            Executable = Join-Path $copy 'WindowsTerminal.exe'
            EvidenceDirectory = $fixture
        }
        if ($kind -eq 'converted') {
            $arguments.ActiveOpacity = 65
            $arguments.WindowName = 'mode-smoke'
            $arguments.ConvertExisting = $true
        }
        & (Join-Path $PSScriptRoot 'HudModeTests\Invoke-DesktopFixture.ps1') @arguments
    }
} finally {
    Stop-Transcript | Out-Null
}
