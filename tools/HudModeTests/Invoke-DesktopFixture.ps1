# Native GUI fixture for the isolated portable fork. Never targets installed Terminal.
#Requires -Version 7
param(
    [Parameter(Mandatory)][string]$Executable,
    [Parameter(Mandatory)][string]$EvidenceDirectory,
    [string]$WindowName = '_hud',
    [double]$ActiveOpacity = 35,
    [switch]$ConvertExisting
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,UIAutomationClient,UIAutomationTypes
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public static class HudProbe {
    public delegate bool EnumProc(IntPtr window, IntPtr data);
    [StructLayout(LayoutKind.Sequential)] public struct Rect { public int Left,Top,Right,Bottom; }
    [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr data);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr window,int id);
    [DllImport("user32.dll")] public static extern uint MapVirtualKeyW(uint code,uint type);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr window,IntPtr order,int x,int y,int width,int height,uint flags);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern IntPtr GetWindowLongPtrW(IntPtr window, int index);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassNameW(IntPtr window, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern IntPtr PostMessageW(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(long point);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    public static IntPtr[] Windows(int process) {
        var result=new List<IntPtr>();
        EnumWindows((window,data)=> { uint owner; GetWindowThreadProcessId(window,out owner); if (owner==process) result.Add(window); return true; }, IntPtr.Zero);
        return result.ToArray();
    }
    public static void Chord(byte function) {
        // Dedicated fixture bindings: Ctrl+Alt+F11/F12. Never sends Windows shortcuts.
        keybd_event(0x11,0,0,UIntPtr.Zero); keybd_event(0x12,0,0,UIntPtr.Zero);
        keybd_event(function,0,0,UIntPtr.Zero); keybd_event(function,0,2,UIntPtr.Zero);
        keybd_event(0x12,0,2,UIntPtr.Zero); keybd_event(0x11,0,2,UIntPtr.Zero);
    }
}
'@
[void][HudProbe]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
function Wait-Ui([int]$Milliseconds = 500) {
    $until = [DateTime]::UtcNow.AddMilliseconds($Milliseconds)
    do { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } while ([DateTime]::UtcNow -lt $until)
}
function Assert-Probe([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    Write-Output "PASS: $Message"
}
function Invoke-FixtureChord([byte]$Key) {
    $foreground = [HudProbe]::GetForegroundWindow()
    if ($foreground -ne $target -and $foreground -ne $background.Handle) {
        throw 'Desktop focus moved outside the owned fixture; stopping before input injection.'
    }
    [HudProbe]::Chord($Key)
}
function Invoke-ModeToggle {
    if ([HudProbe]::GetForegroundWindow() -ne $target) { throw 'Mode toggle requires the owned Terminal to be focused.' }
    $key=[byte][HudProbe]::MapVirtualKeyW(41,3)
    [HudProbe]::keybd_event(0x11,0,0,[UIntPtr]::Zero)
    [HudProbe]::keybd_event(0x5B,0,0,[UIntPtr]::Zero)
    [HudProbe]::keybd_event($key,41,0,[UIntPtr]::Zero)
    [HudProbe]::keybd_event($key,41,2,[UIntPtr]::Zero)
    [HudProbe]::keybd_event(0x5B,0,2,[UIntPtr]::Zero)
    [HudProbe]::keybd_event(0x11,0,2,[UIntPtr]::Zero)
}
function Assert-BackgroundOpacity([double]$Opacity, [int]$X=($screen.Left+[int]($screen.Width/2)), [int]$Y=($screen.Top+[int]($screen.Height/2)), [string]$Context="Active") {
    $probe=[System.Drawing.Bitmap]::new(1,1)
    $paint=[System.Drawing.Graphics]::FromImage($probe)
    try {
        $paint.CopyFromScreen($X,$Y,0,0,$probe.Size)
        $pixel=$probe.GetPixel(0,0)
        $factor=1-$Opacity/100
        Assert-Probe ([Math]::Abs($pixel.R-40*$factor) -le 3 -and [Math]::Abs($pixel.G-160*$factor) -le 3 -and [Math]::Abs($pixel.B-220*$factor) -le 3) "$Context background matches $Opacity percent opacity"
    } finally { $paint.Dispose(); $probe.Dispose() }
}
function Read-State([IntPtr]$Window) {
    $rect = [HudProbe+Rect]::new()
    [void][HudProbe]::GetWindowRect($Window,[ref]$rect)
    @{ visible = [HudProbe]::IsWindowVisible($Window); foreground = [HudProbe]::GetForegroundWindow().ToInt64(); exstyle = [HudProbe]::GetWindowLongPtrW($Window,-20).ToInt64(); rect = $rect }
}
$exe = Get-Item -LiteralPath $Executable
if (-not (Test-Path (Join-Path $exe.DirectoryName '.hud-test-fixture'))) { throw 'Expected an isolated runtime created by Test-HudModeDesktop.ps1.' }
$portableRoot = $exe.DirectoryName
New-Item -ItemType File -Path (Join-Path $portableRoot '.portable') -Force | Out-Null
$settingsFolder = Join-Path $portableRoot 'settings'
New-Item -ItemType Directory -Path $settingsFolder -Force | Out-Null
$settingsPath = Join-Path $settingsFolder 'settings.json'
if (Test-Path $settingsPath) { throw 'Use a fresh fixture directory; existing settings are preserved.' }
$receipt = Join-Path $EvidenceDirectory ('shell-' + [guid]::NewGuid().ToString('N') + '.json')
$profileId = [guid]::NewGuid().ToString('B')
$fixtureSettings = @{
    hudActiveOpacity=$ActiveOpacity
    initialCols=60; initialRows=20
    defaultProfile=$profileId
    disabledProfileSources=@('Microsoft.WSL','Windows.Terminal.PowershellCore','Windows.Terminal.Azure','Windows.Terminal.VisualStudio','Windows.Terminal.SSH')
    profiles=@{ list=@(@{
        guid=$profileId; name='HUD owned smoke fixture'; commandline=('"' + (Join-Path $PSHOME 'pwsh.exe') + '" -NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'SmokeShell.ps1') + '" -Receipt "' + $receipt + '"')
        startingDirectory=$EvidenceDirectory; elevate=$false; opacity=65; useAcrylic=$false; font=@{face='Consolas';size=18}; background='#000000'; foreground='#FFFFFF'
    }) }
    keybindings=@(
        @{keys='win+sc(41)';command='unbound'},
        @{keys='win+shift+sc(41)';command='unbound'},
        @{keys='alt+sc(41)';command='unbound'},
        @{keys='ctrl+alt+f5';command=@{action='renameWindow';name='review-smoke'}},
        @{keys='ctrl+alt+f7';command='toggleFullscreen'},
        @{keys='ctrl+alt+f8';command=@{action='renameWindow';name='_quake'}},
        @{keys='ctrl+alt+f6';command=@{action='globalSummon';name=$WindowName;toggleVisibility=$false;dropdownDuration=0;monitor='any'}},
        @{keys='ctrl+alt+f11';id='Terminal.HudMode'},
        @{keys='ctrl+alt+f12';id='Terminal.HudVisibility'}
    )
}
$fixtureSettings | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
$background = [System.Windows.Forms.Form]::new()
$background.Text='Owned HUD test background'
$background.BackColor=[System.Drawing.Color]::FromArgb(40,160,220)
$background.FormBorderStyle='None'
$background.Bounds=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$background.StartPosition='Manual'
$script:fixtureClicks=0
$background.Add_MouseDown({ $script:fixtureClicks++ })
$originalCursor=[System.Windows.Forms.Cursor]::Position
$background.Show()
[void][HudProbe]::SetForegroundWindow($background.Handle)
Wait-Ui
$process=$null
try {
    foreach ($key in @(0x74,0x75,0x76,0x77,0x7A,0x7B)) {
        if (-not [HudProbe]::RegisterHotKey([IntPtr]::Zero,$key,0x4006,$key)) { throw "Fixture shortcut is already occupied: $key" }
        [void][HudProbe]::UnregisterHotKey([IntPtr]::Zero,$key)
    }
    $process=Start-Process -FilePath $exe.FullName -ArgumentList '-w',$WindowName,'-p',$profileId -WorkingDirectory $portableRoot -PassThru
    $target=[IntPtr]::Zero
    for ($attempt=0;$attempt -lt 150;$attempt++) {
        Wait-Ui 100
        if ($process.HasExited) { throw "Fork exited during startup: $($process.ExitCode)" }
        foreach ($candidate in [HudProbe]::Windows($process.Id)) {
            $class=[System.Text.StringBuilder]::new(256)
            [void][HudProbe]::GetClassNameW($candidate,$class,256)
            if ($class.ToString() -eq 'CASCADIA_HOSTING_WINDOW_CLASS' -and [HudProbe]::IsWindowVisible($candidate)) { $target=$candidate }
        }
        if ($target -ne [IntPtr]::Zero -and (Test-Path $receipt)) { break }
    }
    Assert-Probe ($target -ne [IntPtr]::Zero) 'owned HUD window appeared'
    Assert-Probe (Test-Path $receipt) 'owned shell started'
    Wait-Ui 1000
    $normalBefore=$null
    if ($ConvertExisting) {
        $screens=@([System.Windows.Forms.Screen]::AllScreens)
        $monitor=if ($screens.Count -gt 1) { @($screens | Where-Object { -not $_.Primary })[0] } else { $screens[0] }
        $screen=$monitor.Bounds
        $background.Bounds=$screen
        [void][HudProbe]::SetWindowPos($target,[IntPtr]::Zero,$screen.Left+60,$screen.Top+60,[Math]::Min(900,$screen.Width-120),[Math]::Min(650,$screen.Height-140),20)
        Wait-Ui 1000
        $normalBefore=Read-State $target
        Write-Output "Mode conversion monitor: $($monitor.DeviceName), exposed monitors: $($screens.Count)"
        Invoke-ModeToggle
        Wait-Ui 1000
    } else {
        $screen=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    }
    for ($ready=0; $ready -lt 50; $ready++) {
        $state=Read-State $target
        if (($state.exstyle -band 8) -ne 0 -and $state.foreground -eq $target.ToInt64()) { break }
        Wait-Ui 100
    }
    Assert-Probe ($state.rect.Left -eq $screen.Left -and $state.rect.Top -eq $screen.Top -and $state.rect.Right -eq $screen.Right -and $state.rect.Bottom -eq $screen.Bottom) 'HUD covers the selected monitor'
    Write-Output ('Initial HUD: HWND={0:X}, foreground={1:X}, extended style={2:X}' -f $target.ToInt64(),$state.foreground,$state.exstyle)
    Assert-Probe (($state.exstyle -band 8) -ne 0) 'HUD is topmost'
    Assert-Probe ([HudProbe]::GetForegroundWindow() -eq $target) 'HUD started Active'
    $activeBitmap=[System.Drawing.Bitmap]::new($screen.Width,$screen.Height)
    $activeGraphics=[System.Drawing.Graphics]::FromImage($activeBitmap)
    try {
        $activeGraphics.CopyFromScreen($screen.Location,[System.Drawing.Point]::Empty,$screen.Size)
        $activeBitmap.Save((Join-Path $EvidenceDirectory 'active.png'))
        $activeSample=$activeBitmap.GetPixel([int]($screen.Width/2),[int]($screen.Height/2))
        Write-Output ('Active sample RGB: {0},{1},{2}' -f $activeSample.R,$activeSample.G,$activeSample.B)
        Assert-BackgroundOpacity $ActiveOpacity
    } finally { $activeGraphics.Dispose(); $activeBitmap.Dispose() }
    Invoke-FixtureChord 0x76 # Ordinary fullscreen action cannot break HUD presentation.
    Wait-Ui 300
    $presentation=Read-State $target
    Assert-Probe ($presentation.rect.Left -eq $screen.Left -and $presentation.rect.Top -eq $screen.Top -and $presentation.rect.Right -eq $screen.Right -and $presentation.rect.Bottom -eq $screen.Bottom) 'HUD retained fullscreen presentation after ordinary fullscreen action'
    Invoke-FixtureChord 0x75 # Generic globalSummon must activate, never toggle.
    Wait-Ui 400
    Assert-Probe ([HudProbe]::GetForegroundWindow() -eq $target -and ((Read-State $target).exstyle -band 0x20) -eq 0) 'generic summon of HUD retains Active input'
    Invoke-FixtureChord 0x7A # F11
    Wait-Ui 800
    $state=Read-State $target
    Assert-Probe ($state.visible -and ($state.exstyle -band 0x80020) -eq 0x80020) 'interaction shortcut made HUD Passive'
    Assert-Probe ([HudProbe]::GetForegroundWindow() -eq $background.Handle) 'Passive restored owned foreground'
    $bitmap=[System.Drawing.Bitmap]::new($screen.Width,$screen.Height)
    $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($screen.Location,[System.Drawing.Point]::Empty,$screen.Size)
        $bitmap.Save((Join-Path $EvidenceDirectory 'passive.png'))
        $sample=$bitmap.GetPixel([int]($screen.Width/2),[int]($screen.Height/2))
        Assert-Probe ($sample.R -eq 40 -and $sample.G -eq 160 -and $sample.B -eq 220) 'Passive background is transparent over owned blue surface'
        $white=0
        for ($y=0;$y -lt [Math]::Min(350,$screen.Height);$y+=2) {
            for ($x=0;$x -lt [Math]::Min(900,$screen.Width);$x+=2) {
                $pixel=$bitmap.GetPixel($x,$y)
                if ($pixel.R -ge 245 -and $pixel.G -ge 245 -and $pixel.B -ge 245) { $white++ }
            }
        }
        Write-Output "Passive opaque-white text samples: $white"
        Assert-Probe ($white -gt 1000) 'Passive text remains opaque and visible'
    } finally { $graphics.Dispose(); $bitmap.Dispose() }
    $clickX=$screen.Left+[int]($screen.Width/2)
    $clickY=$screen.Top+[int]($screen.Height/2)
    $point=([long]$clickY -shl 32) -bor [long]$clickX
    Assert-Probe ([HudProbe]::WindowFromPoint($point) -eq $background.Handle) 'native hit-test routes Passive pointer to owned background'
    [void][HudProbe]::SetCursorPos($clickX,$clickY)
    if ([HudProbe]::WindowFromPoint($point) -ne $background.Handle) { throw 'Owned sink moved before click; aborting injection.' }
    [HudProbe]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    [HudProbe]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
    Wait-Ui 200
    Assert-Probe ($script:fixtureClicks -eq 1) 'one physical click reached owned background through Passive HUD'
    Invoke-FixtureChord 0x7B # F12
    Wait-Ui 500
    Assert-Probe (-not [HudProbe]::IsWindowVisible($target)) 'visibility shortcut hid Passive'
    Invoke-FixtureChord 0x7B
    Wait-Ui 500
    $state=Read-State $target
    Assert-Probe ($state.visible -and ($state.exstyle -band 0x20) -ne 0 -and [HudProbe]::GetForegroundWindow() -eq $background.Handle) 'visibility shortcut restored Passive without activation'
    Invoke-FixtureChord 0x7A
    Wait-Ui 500
    Assert-Probe ([HudProbe]::GetForegroundWindow() -eq $target) 'interaction shortcut restored Active focus'
    Invoke-FixtureChord 0x7B
    Wait-Ui 500
    Assert-Probe (-not [HudProbe]::IsWindowVisible($target)) 'visibility shortcut hid Active'
    Invoke-FixtureChord 0x7B
    Wait-Ui 500
    Assert-Probe ([HudProbe]::GetForegroundWindow() -eq $target) 'visibility shortcut restored Active focus'
    $updatedOpacity=if ($ActiveOpacity -eq 35) { 65 } else { 35 }
    $updatedSettings=Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $updatedSettings | Add-Member -NotePropertyName hudActiveOpacity -NotePropertyValue $updatedOpacity -Force
    $updatedSettings | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
    Wait-Ui 1500
    Assert-BackgroundOpacity $updatedOpacity
    Invoke-FixtureChord 0x7A
    Wait-Ui 600
    Assert-Probe ((Read-State $target).exstyle -band 0x20) 'opacity reload preserved Passive input behavior'
    Invoke-FixtureChord 0x7A
    Wait-Ui 600
    Assert-BackgroundOpacity $updatedOpacity
    $shell=Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    Assert-Probe ($null -ne (Get-Process -Id $shell.pid -ErrorAction SilentlyContinue)) 'same shell survived all transitions'
    if ([HudProbe]::GetForegroundWindow() -ne $target) { throw 'HUD lost focus before Escape test.' }
    [HudProbe]::keybd_event(0x1B,0,0,[UIntPtr]::Zero)
    [HudProbe]::keybd_event(0x1B,0,2,[UIntPtr]::Zero)
    Wait-Ui 500
    $delivered=Test-Path ($receipt + '.keys')
    if ($delivered) { $delivered=@(Get-Content -LiteralPath ($receipt + '.keys')) -contains '27' }
    Assert-Probe $delivered 'Escape passed through to the running terminal program'
    Assert-Probe ([HudProbe]::GetForegroundWindow() -eq $target) 'Escape did not change HUD interaction state'
    Invoke-ModeToggle
    Wait-Ui 800
    $normalAfter=Read-State $target
    Write-Output ("Normal bounds after: {0},{1} to {2},{3}; monitor: {4}x{5}" -f $normalAfter.rect.Left,$normalAfter.rect.Top,$normalAfter.rect.Right,$normalAfter.rect.Bottom,$screen.Width,$screen.Height)
    Assert-Probe ($normalAfter.visible -and ($normalAfter.exstyle -band 0x20) -eq 0) 'leaving HUD restored visible normal input'
    Assert-Probe ([HudProbe]::GetForegroundWindow() -eq $target) 'leaving HUD retained focus'
    if ($normalBefore) {
        Assert-Probe ($normalAfter.rect.Left -eq $normalBefore.rect.Left -and $normalAfter.rect.Top -eq $normalBefore.rect.Top -and $normalAfter.rect.Right -eq $normalBefore.rect.Right -and $normalAfter.rect.Bottom -eq $normalBefore.rect.Bottom) 'leaving HUD restored exact previous bounds'
        Assert-Probe (($normalAfter.exstyle -band 8) -eq ($normalBefore.exstyle -band 8)) 'leaving HUD restored previous topmost policy'
    } else {
        Assert-Probe (($normalAfter.rect.Right-$normalAfter.rect.Left) -lt $screen.Width) 'fresh HUD can return to normal window size'
    }
    Assert-BackgroundOpacity 65 ([int](($normalAfter.rect.Left+$normalAfter.rect.Right)/2)) ($normalAfter.rect.Bottom-80) 'Normal'
    Assert-Probe ($null -ne (Get-Process -Id $shell.pid -ErrorAction SilentlyContinue)) 'same shell survived leaving HUD mode'
    Invoke-FixtureChord 0x7A
    Invoke-FixtureChord 0x7B
    Wait-Ui 300
    $withoutHud=Read-State $target
    Assert-Probe (($withoutHud.exstyle -band 0x28) -eq 0 -and $withoutHud.rect.Equals($normalAfter.rect)) 'global HUD actions left an ordinary window unchanged'
    Invoke-ModeToggle
    Wait-Ui 800
    $again=Read-State $target
    Assert-Probe ($again.rect.Left -eq $screen.Left -and $again.rect.Top -eq $screen.Top -and $again.rect.Right -eq $screen.Right -and $again.rect.Bottom -eq $screen.Bottom) 'mode toggle re-entered HUD on the same monitor'
    Invoke-ModeToggle
    Wait-Ui 500
    # Exercise a queued activation concurrently with a local mode change.
    for ($cycle=0;$cycle -lt 8;$cycle++) {
        Invoke-ModeToggle
        Wait-Ui 200
        Invoke-FixtureChord 0x75
        Invoke-ModeToggle
        Wait-Ui 300
        $ordinary=Read-State $target
        Assert-Probe (($ordinary.exstyle -band 0x20) -eq 0 -and ($ordinary.rect.Right-$ordinary.rect.Left) -lt $screen.Width) 'queued summon did not restore HUD after leaving its mode'
    }
    # Use a wide window so the Settings navigation pane is expanded. Placement
    # restoration was verified above before changing the fixture geometry.
    [void][HudProbe]::SetWindowPos($target,[IntPtr]::Zero,$screen.Left+80,$screen.Top+80,$screen.Width-160,$screen.Height-160,20)
    Wait-Ui 500
    Invoke-ModeToggle
    Wait-Ui 300
    # Opening Settings from HUD must return to ordinary window presentation.
    # Exercise the real settings control and its save path in this private copy.
    if ([HudProbe]::GetForegroundWindow() -ne $target) { throw 'Settings test requires the owned Terminal to be focused.' }
    [HudProbe]::keybd_event(0x11,0,0,[UIntPtr]::Zero)
    [HudProbe]::keybd_event(0xBC,0,0,[UIntPtr]::Zero)
    [HudProbe]::keybd_event(0xBC,0,2,[UIntPtr]::Zero)
    [HudProbe]::keybd_event(0x11,0,2,[UIntPtr]::Zero)
    Wait-Ui 1000
    $root=[System.Windows.Automation.AutomationElement]::FromHandle($target)
    $appearance=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'AppearanceNavItem'))
    Assert-Probe ($null -ne $appearance) 'Appearance settings navigation is accessible'
    $settingsState=Read-State $target
    Assert-Probe (($settingsState.exstyle -band 0x28) -eq 0 -and ($settingsState.rect.Right-$settingsState.rect.Left) -lt $screen.Width) 'opening Settings left HUD and restored ordinary input/presentation'
    ([System.Windows.Automation.SelectionItemPattern]$appearance.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select()
    Wait-Ui 600
    $opacityControls=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::NameProperty,'HUD Active opacity (%)'))
    $input=$null
    foreach ($control in $opacityControls) {
        Write-Output "Opacity UI control: $($control.Current.ControlType.ProgrammaticName) / $($control.Current.AutomationId)"
        $candidate=$control.FindFirst([System.Windows.Automation.TreeScope]::Subtree,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit))
        if ($candidate) { $input=$candidate; break }
    }
    Assert-Probe ($null -ne $input) 'HUD Active opacity input is exposed in Appearance'
    $input.SetFocus()
    ([System.Windows.Automation.ValuePattern]$input.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)).SetValue('47')
    if ([HudProbe]::GetForegroundWindow() -ne $target) { throw 'Focus left the fixture before committing the opacity field.' }
    [HudProbe]::keybd_event(9,0,0,[UIntPtr]::Zero)
    [HudProbe]::keybd_event(9,0,2,[UIntPtr]::Zero)
    Wait-Ui 200
    $save=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'SaveButton'))
    Assert-Probe ($null -ne $save) 'Settings save button is accessible'
    ([System.Windows.Automation.InvokePattern]$save.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke()
    Wait-Ui 800
    $savedSettings=Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    Assert-Probe ($savedSettings.hudActiveOpacity -eq 47) 'Appearance UI saved the requested HUD opacity'
    # Select the terminal tab explicitly, as a user would before entering HUD.
    $tabs=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TabItem))
    $terminalTab=$null
    foreach ($tab in $tabs) {
        if ($tab.Current.Name -eq 'HUD owned smoke fixture') { $terminalTab=$tab; break }
    }
    Assert-Probe ($null -ne $terminalTab) 'existing terminal tab is available for manual selection'
    ([System.Windows.Automation.SelectionItemPattern]$terminalTab.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select()
    Wait-Ui 300
    Invoke-ModeToggle
    Wait-Ui 500
    Assert-BackgroundOpacity 47
    $afterSettings=Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json
    Assert-Probe ($afterSettings.pid -eq $shell.pid) 'HUD return from Settings reused the existing terminal session'
    Invoke-FixtureChord 0x7A
    Wait-Ui 400
    Assert-BackgroundOpacity 0 -Context 'Passive terminal after Settings'
    Invoke-FixtureChord 0x7A
    Wait-Ui 300
    Invoke-ModeToggle
    Wait-Ui 300
    Invoke-ModeToggle
    Wait-Ui 300
    Invoke-FixtureChord 0x77 # Rename to the reserved Quake name.
    Wait-Ui 500
    $quake=Read-State $target
    Assert-Probe (($quake.exstyle -band 0x20) -eq 0 -and ($quake.rect.Bottom-$quake.rect.Top) -lt $screen.Height) 'renaming HUD to Quake released HUD input and sizing'
    Invoke-ModeToggle
    Wait-Ui 300
    $stillQuake=Read-State $target
    Assert-Probe (($stillQuake.rect.Bottom-$stillQuake.rect.Top) -lt $screen.Height) 'Quake refused simultaneous HUD mode'
    Invoke-FixtureChord 0x74 # Rename to an ordinary window again.
    Wait-Ui 300
    Invoke-ModeToggle
    Wait-Ui 400
    $backToHud=Read-State $target
    Assert-Probe ($backToHud.rect.Left -eq $screen.Left -and $backToHud.rect.Top -eq $screen.Top -and $backToHud.rect.Right -eq $screen.Right -and $backToHud.rect.Bottom -eq $screen.Bottom) 'ordinary renamed window can enter HUD again'
    Invoke-ModeToggle
    Wait-Ui 300
    Write-Output 'DESKTOP_SMOKE_PASSED'
} finally {
    if ($process -and -not $process.HasExited) {
        # Target only our exact fixture process; never close installed Terminal.
        $process.Kill($true)
        $process.WaitForExit(5000) | Out-Null
    }
    [void][HudProbe]::SetCursorPos($originalCursor.X,$originalCursor.Y)
    $background.Close()
    $background.Dispose()
}
