# Two independent portable paths force separate Terminal processes while sharing
# the production user/session HUD lease. All processes and settings are owned.
function Assert-SingleHudAcrossInstances {
    $second=$null
    $secondRoot=Join-Path $EvidenceDirectory 'secondary-runtime'
    & robocopy.exe $portableRoot $secondRoot /E /XD settings /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw 'Secondary fixture runtime copy failed.' }
    $secondReceipt=Join-Path $EvidenceDirectory 'secondary-shell.json'
    $secondSettings=$fixtureSettings | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $secondSettings.profiles.list[0].commandline=('"'+(Join-Path $PSHOME 'pwsh.exe')+'" -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'SmokeShell.ps1')+'" -Receipt "'+$secondReceipt+'"')
    # Do not compete with the primary fixture's generic global-summon test key.
    $secondSettings.keybindings=@($secondSettings.keybindings | Where-Object keys -ne 'ctrl+alt+f6')
    New-Item -ItemType Directory -Path (Join-Path $secondRoot 'settings') | Out-Null
    $secondSettings | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $secondRoot 'settings\settings.json') -Encoding utf8NoBOM
    try {
        Invoke-ModeToggle
        Wait-Ui 500
        Assert-Probe (((Read-State $target).exstyle -band 8) -ne 0) 'primary process acquired HUD before the competing instance'
        $secondExe=Join-Path $secondRoot 'WindowsTerminal.exe'
        $second=Start-Process -FilePath $secondExe -ArgumentList '-w','second-normal','-p',$profileId -PassThru
        $script:additionalProcesses+=@($second)
        $secondWindow=[IntPtr]::Zero
        for ($attempt=0;$attempt -lt 100;$attempt++) {
            Wait-Ui 100
            if ($second.HasExited) { throw 'Secondary fixture exited during startup.' }
            foreach ($candidate in [HudProbe]::Windows($second.Id)) {
                $class=[System.Text.StringBuilder]::new(256)
                [void][HudProbe]::GetClassNameW($candidate,$class,256)
                if ($class.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS' -and [HudProbe]::IsWindowVisible($candidate)) { $secondWindow=$candidate }
            }
            if ($secondWindow -ne [IntPtr]::Zero -and (Test-Path $secondReceipt)) { break }
        }
        Assert-Probe ($secondWindow -ne [IntPtr]::Zero -and $second.Id -ne $process.Id) 'second executable path started an independent normal Terminal process'
        Wait-Ui 700
        Assert-Probe (((Read-State $secondWindow).exstyle -band 0x28) -eq 0) 'secondary window stayed normal while another process owned HUD'
        # A HUD launch through the other instance forwards activation instead of
        # creating another window, terminal connection or HUD.
        & $secondExe -w _hud
        Wait-Ui 800
        $visible=@([HudProbe]::Windows($second.Id) | Where-Object {
            $class=[System.Text.StringBuilder]::new(256)
            [void][HudProbe]::GetClassNameW($_,$class,256)
            $class.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS' -and [HudProbe]::IsWindowVisible($_)
        })
        Assert-Probe ($visible.Count -eq 1 -and [HudProbe]::GetForegroundWindow() -eq $target) 'HUD launch in another process activated the sole existing HUD without adding a window'
        [void][HudProbe]::SetForegroundWindow($secondWindow)
        Wait-Ui 300
        Invoke-ModeToggle
        Wait-Ui 500
        Assert-Probe (((Read-State $target).exstyle -band 0x28) -eq 0 -and [HudProbe]::GetForegroundWindow() -eq $target) 'global mode key in the secondary process exited the primary owner'
        [void][HudProbe]::SetForegroundWindow($secondWindow)
        Wait-Ui 200
        Invoke-ModeToggle
        Wait-Ui 500
        Assert-Probe (((Read-State $secondWindow).exstyle -band 8) -ne 0 -and ((Read-State $target).exstyle -band 0x28) -eq 0) 'secondary process acquired the released HUD role without changing the primary window'
        Invoke-FixtureChord 0x7D
        Wait-Ui 300
        Invoke-ModeToggle
        Wait-Ui 500
        Assert-Probe ((Read-State $secondWindow).visible -and ((Read-State $secondWindow).exstyle -band 0x28) -eq 0) 'global mode key restored the secondary owner from Hidden to normal'
        Invoke-ModeToggle
        Wait-Ui 400
        Assert-Probe (((Read-State $secondWindow).exstyle -band 8) -ne 0) 'secondary process reacquired HUD for the crash-recovery check'
        $second.Kill($true);$second.WaitForExit(5000) | Out-Null
        $script:additionalProcesses=@()
        [void][HudProbe]::SetForegroundWindow($target)
        Wait-Ui 300
        Invoke-ModeToggle
        Wait-Ui 500
        Assert-Probe (((Read-State $target).exstyle -band 8) -ne 0) 'primary process recovered ownership after the other HUD process terminated'
        Invoke-ModeToggle
        Wait-Ui 300
        Assert-Probe (((Read-State $target).exstyle -band 0x28) -eq 0) 'cross-process tests left the primary terminal in normal mode'
    } finally {
        if ($second -and -not $second.HasExited) { $second.Kill($true);$second.WaitForExit(5000) | Out-Null }
        $script:additionalProcesses=@()
        [void][HudProbe]::SetForegroundWindow($target)
        Wait-Ui 200
    }
}
