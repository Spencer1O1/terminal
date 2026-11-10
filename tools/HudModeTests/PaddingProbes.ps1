# Layout and Settings checks for HUD-only spacing in the owned desktop fixture.
function Get-TerminalBounds {
    $root=[System.Windows.Automation.AutomationElement]::FromHandle($target)
    $controls=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ClassNameProperty,'TermControl'))
    @($controls | ForEach-Object { $_.Current.BoundingRectangle })
}
function Get-HudPaddingField($Page,[string]$Name) {
    $groups=$Page.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,$Name))
    foreach ($group in $groups) {
        $edit=$group.FindFirst([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit))
        if ($edit) { return $edit }
    }
    $nodes=$Page.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    foreach ($node in $nodes) { if ($node.Current.Name -like '*HUD*') { Write-Host ("HUD UI diagnostic: {0} / {1} / {2}" -f $node.Current.ControlType.ProgrammaticName,$node.Current.AutomationId,$node.Current.Name) } }
    throw "$Name input is not accessible in Appearance."
}
function Set-HudPaddingField($Edit,[string]$Value) {
    # Resolve all controls before editing: Compact NumberBox exposes its spinner
    # popup as the automation root while an input has focus.
    $Edit.SetFocus()
    ([System.Windows.Automation.ValuePattern]$Edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).SetValue($Value)
    $owner=0u
    [void][HudProbe]::GetWindowThreadProcessId([HudProbe]::GetForegroundWindow(),[ref]$owner)
    if ($owner -ne $process.Id) { throw 'Focus left owned Settings before committing HUD padding.' }
    Assert-HudDesktopIsolation -OwnedProcessIds @($process.Id)
    [HudProbe]::keybd_event(9,0,0,[UIntPtr]::Zero)
    [HudProbe]::keybd_event(9,0,2,[UIntPtr]::Zero)
    Wait-Ui 150
}
function Assert-HudPadding([double]$Horizontal,[double]$Vertical) {
    $bounds=@(Get-TerminalBounds)
    Assert-Probe ($bounds.Count -eq 1) 'padding probe has one terminal control'
    $scale=[HudProbe]::GetDpiForWindow($target)/96.0
    $expected=@(($hudContentWithoutPadding.Left+$Horizontal*$scale),($hudContentWithoutPadding.Top+$Vertical*$scale),($hudContentWithoutPadding.Right-$Horizontal*$scale),($hudContentWithoutPadding.Bottom-$Vertical*$scale))
    $actual=@($bounds[0].Left,$bounds[0].Top,$bounds[0].Right,$bounds[0].Bottom)
    Write-Output ('HUD content bounds: '+($actual -join ',')+'; expected: '+($expected -join ',')+'; scale: '+$scale)
    for ($side=0;$side -lt 4;$side++) { Assert-Probe ([Math]::Abs($actual[$side]-$expected[$side]) -le 2) "HUD padding edge $side matches $Horizontal/$Vertical DIPs" }
}
function Assert-HudPaddingReloadAndRestore {
    Assert-HudPadding 48 24
    $scale=[HudProbe]::GetDpiForWindow($target)/96.0
    Assert-BackgroundOpacity 0 ($screen.Left+[int](20*$scale)) ($screen.Top+[int](10*$scale)) 'Passive HUD outer padding'
    $reload=Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $reload.hudHorizontalPadding=96
    $reload.hudVerticalPadding=40
    $reload | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
    Wait-Ui 1500
    Assert-HudPadding 96 40
    Assert-Probe (((Read-State $target).exstyle -band 0x8000020) -eq 0x8000020) 'padding reload preserved Passive input'
    Invoke-FixtureChord 0x7D
    Wait-Ui 200
    $reload.hudHorizontalPadding=80
    $reload.hudVerticalPadding=32
    $reload | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
    Wait-Ui 1000
    Assert-Probe (-not (Read-State $target).visible) 'padding reload kept a Hidden HUD hidden'
    Invoke-FixtureChord 0x7D
    Wait-Ui 400
    Assert-HudPadding 80 32
    Assert-Probe (((Read-State $target).exstyle -band 0x8000020) -eq 0x8000020) 'Hidden padding reload restored Passive input'
    $reload.hudHorizontalPadding=96
    $reload.hudVerticalPadding=40
    $reload | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
    Wait-Ui 1000
    Assert-HudPadding 96 40
    Invoke-FixtureChord 0x7C
    Wait-Ui 300
    $page=[System.Windows.Automation.AutomationElement]::FromHandle($target)
    $terminal=$page.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ClassNameProperty,'TermControl'))
    $terminal.SetFocus()
    Wait-Ui 150
    # Exercise the documented CLI to avoid relying on a synthetic extended
    # function-key event for this layout test. Each isolated process has ID 1.
    & $exe.FullName -w 1 split-pane --duplicate --vertical
    Wait-Ui 1200
    $panes=@(Get-TerminalBounds | Sort-Object Left)
    Write-Output ('Split pane controls: '+$panes.Count)
    Assert-Probe ($panes.Count -eq 2) 'HUD padding test created two panes'
    Assert-Probe ([Math]::Abs($panes[0].Left-($hudContentWithoutPadding.Left+96*$scale)) -le 2 -and [Math]::Abs($panes[1].Right-($hudContentWithoutPadding.Right-96*$scale)) -le 2) 'split panes share one horizontal HUD inset'
    Assert-Probe ([Math]::Abs($panes[0].Top-$panes[1].Top) -le 2 -and [Math]::Abs($panes[0].Top-($hudContentWithoutPadding.Top+40*$scale)) -le 2) 'split panes share one vertical HUD inset'
    Assert-Probe (($panes[1].Left-$panes[0].Right) -lt 8*$scale) 'HUD padding was not duplicated between panes'
    $page=[System.Windows.Automation.AutomationElement]::FromHandle($target)
    $terminals=$page.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ClassNameProperty,'TermControl'))
    $terminals[$terminals.Count-1].SetFocus()
    Invoke-FixtureChord 0x78 # Close only the owned duplicated pane.
    Wait-Ui 500
    Assert-Probe ($null -ne (Get-Process -Id $shell.pid -ErrorAction SilentlyContinue)) 'original shell survived padding and pane changes'
    Invoke-ModeToggle
    Wait-Ui 500
    $normal=@(Get-TerminalBounds)
    Assert-Probe ($normal.Count -eq 1 -and [Math]::Abs($normal[0].Left-$normalContentBeforePadding.Left) -le 2 -and [Math]::Abs($normal[0].Top-$normalContentBeforePadding.Top) -le 2 -and [Math]::Abs($normal[0].Right-$normalContentBeforePadding.Right) -le 2 -and [Math]::Abs($normal[0].Bottom-$normalContentBeforePadding.Bottom) -le 2) 'leaving HUD restored the normal terminal content bounds'
    Invoke-ModeToggle
    Wait-Ui 400
    Assert-HudPadding 96 40
    Invoke-ModeToggle
    Wait-Ui 300
}
