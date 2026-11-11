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
