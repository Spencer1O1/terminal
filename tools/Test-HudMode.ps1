# Standalone policy and Win32 input-style tests. Does not launch Terminal.
#Requires -Version 7
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $visualStudio) {
    throw 'A Visual Studio C++ toolchain is required for the native HUD helper tests.'
}
$vcvars = Join-Path $visualStudio 'VC\Auxiliary\Build\vcvarsall.bat'
$buildDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('wt-hud-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $buildDirectory 'tests') | Out-Null
try {
    $source = Join-Path $repositoryRoot 'src\cascadia\WindowsTerminal'
    Copy-Item (Join-Path $source 'HudState.h'), (Join-Path $source 'HudInput.h') $buildDirectory
    Copy-Item (Join-Path $source 'tests\HudStateTests.cpp'), (Join-Path $source 'tests\HudInputTests.cpp') (Join-Path $buildDirectory 'tests')
    @"
@echo off
call "$vcvars" x64 >nul
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /permissive- /Fe:hud-state.exe tests\HudStateTests.cpp
if errorlevel 1 exit /b 1
hud-state.exe
if errorlevel 1 exit /b 1
cl /nologo /std:c++17 /EHsc /W4 /WX /permissive- /Fe:hud-input.exe tests\HudInputTests.cpp user32.lib
if errorlevel 1 exit /b 1
hud-input.exe
exit /b %errorlevel%
"@ | Set-Content -Path (Join-Path $buildDirectory 'run.cmd') -Encoding ascii
    Push-Location $buildDirectory
    try {
        & $env:ComSpec /d /c run.cmd
        if ($LASTEXITCODE -ne 0) {
            throw "Native HUD helper tests failed with exit code $LASTEXITCODE."
        }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item -LiteralPath $buildDirectory -Recurse -Force
}
