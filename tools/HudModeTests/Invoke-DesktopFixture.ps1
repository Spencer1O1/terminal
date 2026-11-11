# Owned native Windows fixture for the dedicated, Quake-style HUD lifecycle.
#Requires -Version 7
param([Parameter(Mandatory)][string]$Executable,[Parameter(Mandatory)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'DesktopIsolation.ps1')
Assert-HudDesktopIsolation
Add-Type -AssemblyName System.Windows.Forms,System.Drawing,UIAutomationClient,UIAutomationTypes
Add-Type -TypeDefinition @'
using System;using System.Text;using System.Collections.Generic;using System.Runtime.InteropServices;
public static class HudProbe {
 public delegate bool Callback(IntPtr window,IntPtr unused);
 [StructLayout(LayoutKind.Sequential)]public struct Rect {public int Left,Top,Right,Bottom;}
 [DllImport("user32.dll")]public static extern bool EnumWindows(Callback callback,IntPtr data);
 [DllImport("user32.dll")]public static extern uint GetWindowThreadProcessId(IntPtr window,out uint pid);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]public static extern int GetClassNameW(IntPtr window,StringBuilder text,int size);
 [DllImport("user32.dll")]public static extern bool GetWindowRect(IntPtr window,out Rect rect);
 [DllImport("user32.dll")]public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr window);
 [DllImport("user32.dll")]public static extern bool IsWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern bool IsIconic(IntPtr window);
 [DllImport("user32.dll")]public static extern IntPtr GetWindowLongPtrW(IntPtr window,int index);
 [DllImport("user32.dll")]public static extern bool SetWindowPos(IntPtr window,IntPtr order,int x,int y,int w,int h,uint flags);
 [DllImport("user32.dll")]public static extern bool PostMessageW(IntPtr window,uint message,IntPtr a,IntPtr b);
 [DllImport("user32.dll")]public static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
 [DllImport("user32.dll")]public static extern bool UnregisterHotKey(IntPtr window,int id);
 [DllImport("user32.dll")]public static extern uint GetDpiForWindow(IntPtr window);
 [DllImport("user32.dll")]public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")]public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")]public static extern void keybd_event(byte key,byte scan,uint flags,UIntPtr extra);
 [DllImport("user32.dll")]public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
 public static IntPtr[] Windows(int target){var result=new List<IntPtr>();EnumWindows((window,unused)=>{uint pid;GetWindowThreadProcessId(window,out pid);if(pid==(uint)target){var name=new StringBuilder(256);GetClassNameW(window,name,256);if(name.ToString()=="CASCADIA_HOSTING_WINDOW_CLASS")result.Add(window);}return true;},IntPtr.Zero);return result.ToArray();}
 public static void Chord(byte key){keybd_event(0x11,0,0,UIntPtr.Zero);keybd_event(0x12,0,0,UIntPtr.Zero);keybd_event(key,0,0,UIntPtr.Zero);keybd_event(key,0,2,UIntPtr.Zero);keybd_event(0x12,0,2,UIntPtr.Zero);keybd_event(0x11,0,2,UIntPtr.Zero);}
}
'@
[void][HudProbe]::SetThreadDpiAwarenessContext([IntPtr]::new(-4))
function Wait-Ui([int]$Milliseconds=500){$until=[DateTime]::UtcNow.AddMilliseconds($Milliseconds);do{[System.Windows.Forms.Application]::DoEvents();Start-Sleep -Milliseconds 20}while([DateTime]::UtcNow -lt $until)}
function Assert-Probe([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message};Write-Output "PASS: $Message"}
function Read-State([IntPtr]$Window){$rect=[HudProbe+Rect]::new();[void][HudProbe]::GetWindowRect($Window,[ref]$rect);@{visible=[HudProbe]::IsWindowVisible($Window);exstyle=[HudProbe]::GetWindowLongPtrW($Window,-20).ToInt64();rect=$rect}}
function Invoke-FixtureChord([byte]$Key){
 $owned=@($process.Id)+@($script:additionalProcesses|ForEach-Object Id)
 Assert-HudDesktopIsolation -OwnedProcessIds $owned
 $fore=[HudProbe]::GetForegroundWindow();$pidOwner=0u;[void][HudProbe]::GetWindowThreadProcessId($fore,[ref]$pidOwner)
 if($fore -ne $background.Handle -and $pidOwner -notin $owned){throw 'Focus left the owned fixture; stopping before input.'}
 [HudProbe]::Chord($Key)
}
function Shell-Records {@(Get-ChildItem -LiteralPath $receipts -Filter 'shell-*.json'|ForEach-Object {Get-Content -LiteralPath $_.FullName -Raw|ConvertFrom-Json})}
function Wait-NewWindow($Process,[IntPtr[]]$Except=@()){
 for($attempt=0;$attempt -lt 100;$attempt++){foreach($window in [HudProbe]::Windows($Process.Id)){if($window -notin $Except -and [HudProbe]::IsWindowVisible($window)){return $window}};if($Process.HasExited){throw 'Owned Terminal exited during window creation.'};Wait-Ui 100}
 throw 'Owned Terminal window did not appear.'
}
function Assert-Opacity([double]$Opacity){
 $bitmap=[System.Drawing.Bitmap]::new(1,1);$paint=[System.Drawing.Graphics]::FromImage($bitmap)
 try{$paint.CopyFromScreen($screen.Left+[int]($screen.Width/2),$screen.Top+[int]($screen.Height/2),0,0,$bitmap.Size);$pixel=$bitmap.GetPixel(0,0);$factor=1-$Opacity/100;Assert-Probe ([Math]::Abs($pixel.R-40*$factor) -le 3 -and [Math]::Abs($pixel.G-160*$factor) -le 3 -and [Math]::Abs($pixel.B-220*$factor) -le 3) "HUD background has $Opacity percent opacity"}finally{$paint.Dispose();$bitmap.Dispose()}
}
. (Join-Path $PSScriptRoot 'PaddingProbes.ps1')
$exe=Get-Item -LiteralPath $Executable
$portableRoot=$exe.DirectoryName
if(-not(Test-Path (Join-Path $portableRoot '.hud-test-fixture'))){throw 'Expected an isolated, marked test runtime.'}
New-Item -ItemType File (Join-Path $portableRoot '.portable') -Force|Out-Null
$settingsFolder=Join-Path $portableRoot 'settings';New-Item -ItemType Directory $settingsFolder|Out-Null
$settingsPath=Join-Path $settingsFolder 'settings.json'
$receipts=Join-Path $EvidenceDirectory 'receipts';New-Item -ItemType Directory $receipts|Out-Null
$profileId=[guid]::NewGuid().ToString('B')
$fixtureSettings=@{
 hudActiveOpacity=35;hudHorizontalPadding=48;hudVerticalPadding=24;initialCols=60;initialRows=20;defaultProfile=$profileId
 disabledProfileSources=@('Microsoft.WSL','Windows.Terminal.PowershellCore','Windows.Terminal.Azure','Windows.Terminal.VisualStudio','Windows.Terminal.SSH')
 profiles=@{list=@(@{guid=$profileId;name='HUD owned lifecycle fixture';commandline=('"'+(Join-Path $PSHOME 'pwsh.exe')+'" -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'SmokeShell.ps1')+'" -Receipt "'+$receipts+'"');startingDirectory=$EvidenceDirectory;elevate=$false;opacity=65;useAcrylic=$false;scrollbarState='visible';showMarksOnScrollbar=$true;font=@{face='Consolas';size=18};background='#000000';foreground='#FFFFFF'})}
 keybindings=@(@{keys='win+sc(41)';command='unbound'},@{keys='win+shift+sc(41)';command='unbound'},@{keys='alt+sc(41)';command='unbound'},@{keys='ctrl+alt+f13';id='Terminal.HudMode'},@{keys='ctrl+alt+f14';id='Terminal.HudVisibility'},@{keys='ctrl+alt+f6';id='Terminal.OpenSettingsUI'})
}
$fixtureSettings|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $settingsPath -Encoding utf8NoBOM
$screen=[System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$background=[System.Windows.Forms.Form]::new();$background.Text='Owned HUD lifecycle background';$background.FormBorderStyle='None';$background.StartPosition='Manual';$background.Bounds=$screen;$background.BackColor=[System.Drawing.Color]::FromArgb(40,160,220)
$script:clicks=0;$background.Add_MouseDown({$script:clicks++})
$cursor=[System.Windows.Forms.Cursor]::Position
$process=$null;$second=$null;$script:additionalProcesses=@()
try{
 foreach($key in @(0x75,0x7C,0x7D)){if(-not[HudProbe]::RegisterHotKey([IntPtr]::Zero,$key,0x4003,$key)){throw 'A fixture shortcut is occupied.'};[void][HudProbe]::UnregisterHotKey([IntPtr]::Zero,$key)}
 $background.Show();[void][HudProbe]::SetForegroundWindow($background.Handle);Wait-Ui 200
 $process=Start-Process -FilePath $exe.FullName -ArgumentList '-w','hud-lifecycle-seed','-p',$profileId -WorkingDirectory $portableRoot -PassThru
 $normal=Wait-NewWindow $process;Wait-Ui 1000
 $normalShell=@(Shell-Records)[0].pid
 Assert-Probe ($null -ne $normalShell) 'normal terminal shell started'
 [void][HudProbe]::SetWindowPos($normal,[IntPtr]::Zero,$screen.Left+60,$screen.Top+60,900,650,0x14);Wait-Ui 300
 $before=Read-State $normal
 Invoke-FixtureChord 0x7C;Wait-Ui 200
 Assert-Probe (@([HudProbe]::Windows($process.Id)).Count -eq 1 -and ((Read-State $normal).exstyle -band 0x28) -eq 0) 'interaction with no HUD left the normal terminal unchanged'
 [void][HudProbe]::SetCursorPos($screen.Right-40,$screen.Bottom-80)
 Invoke-FixtureChord 0x7D
 $target=Wait-NewWindow $process @($normal);Wait-Ui 700
 $hudShell=@(Shell-Records|Where-Object pid -ne $normalShell)[0].pid
 Assert-Probe ($null -ne $hudShell -and $hudShell -ne $normalShell) 'summon created a dedicated HUD with its own shell'
 Assert-Probe (((Read-State $target).exstyle -band 8) -ne 0 -and [HudProbe]::GetForegroundWindow() -eq $target) 'new HUD is Active and topmost'
 Assert-Probe ((Read-State $normal).rect.Equals($before.rect) -and ((Read-State $normal).exstyle -band 0x28) -eq 0) 'normal terminal retained its bounds and ordinary presentation'
 Assert-Opacity 35
 Invoke-FixtureChord 0x7D;Wait-Ui 500
 Assert-Probe (-not [HudProbe]::IsWindowVisible($target)) 'same-monitor Active summon hid HUD'
 Invoke-FixtureChord 0x7C;Wait-Ui 200
 Assert-Probe (-not [HudProbe]::IsWindowVisible($target)) 'interaction did not expose a hidden HUD'
 Invoke-FixtureChord 0x7D;Wait-Ui 500
 Assert-Probe ([HudProbe]::IsWindowVisible($target) -and [HudProbe]::GetForegroundWindow() -eq $target) 'summon restored Hidden HUD as Active'
 Invoke-FixtureChord 0x7C;Wait-Ui 300
 Assert-Probe (((Read-State $target).exstyle -band 0x8000020) -eq 0x8000020) 'interaction made the visible HUD Passive'
 Assert-Opacity 0
 [void][HudProbe]::SetForegroundWindow($background.Handle);Wait-Ui 150
 [void][HudProbe]::SetCursorPos($screen.Right-40,$screen.Bottom-80)
 Assert-HudDesktopIsolation -OwnedProcessIds @($process.Id)
 [HudProbe]::mouse_event(2,0,0,0,[UIntPtr]::Zero);[HudProbe]::mouse_event(4,0,0,0,[UIntPtr]::Zero);Wait-Ui 200
 Assert-Probe ($script:clicks -eq 1) 'Passive pointer input reached the owned background'
 Invoke-FixtureChord 0x7D;Wait-Ui 500
 Assert-Probe ([HudProbe]::IsWindowVisible($target) -and [HudProbe]::GetForegroundWindow() -eq $target) 'summoning Passive HUD activated it instead of hiding it'
 $bounds=Read-State $target
 Invoke-FixtureChord 0x7C;Wait-Ui 200;Invoke-FixtureChord 0x7C;Wait-Ui 300
 Assert-Probe ((Read-State $target).rect.Equals($bounds.rect)) 'interaction did not move HUD'
 # Different executable paths prove sole-owner activation across processes.
 $secondRoot=Join-Path $EvidenceDirectory 'second-runtime'
 & robocopy.exe $portableRoot $secondRoot /E /XD settings /R:1 /W:1 /NFL /NDL /NJH /NJS /NP|Out-Null
 if($LASTEXITCODE -ge 8){throw 'Secondary runtime copy failed.'}
 New-Item -ItemType Directory (Join-Path $secondRoot 'settings')|Out-Null
 $fixtureSettings|ConvertTo-Json -Depth 20|Set-Content -LiteralPath (Join-Path $secondRoot 'settings\settings.json') -Encoding utf8NoBOM
 $secondExe=Join-Path $secondRoot 'WindowsTerminal.exe'
 $second=Start-Process -FilePath $secondExe -ArgumentList '-w','hud-second-seed','-p',$profileId -PassThru
 $script:additionalProcesses=@($second)
 $secondWindow=Wait-NewWindow $second;Wait-Ui 500
 & $secondExe -w _hud
 Wait-Ui 600
 Assert-Probe (@([HudProbe]::Windows($second.Id)).Count -eq 1 -and @([HudProbe]::Windows($process.Id)).Count -eq 2 -and [HudProbe]::GetForegroundWindow() -eq $target) 'second process activated the sole HUD without creating another'
 [void][HudProbe]::PostMessageW($secondWindow,0x10,[IntPtr]::Zero,[IntPtr]::Zero);Wait-Ui 300
 if(-not $second.HasExited){$second.Kill($true);[void]$second.WaitForExit(5000)}
 $script:additionalProcesses=@()
 [void][HudProbe]::SetForegroundWindow($target);Wait-Ui 150
 $shellCount=@(Shell-Records).Count
 Invoke-FixtureChord 0x75
 $settingsWindow=Wait-NewWindow $process @($normal,$target);Wait-Ui 500
 Assert-Probe (((Read-State $settingsWindow).exstyle -band 0x28) -eq 0) 'Settings opened in a separate ordinary window'
 Assert-Probe (((Read-State $target).exstyle -band 0x8000028) -eq 0x8000028 -and [HudProbe]::IsWindowVisible($target)) 'HUD retained its role and became Passive while Settings had focus'
 Assert-Probe (@(Shell-Records).Count -eq $shellCount -and $null -ne (Get-Process -Id $hudShell -ErrorAction SilentlyContinue)) 'Settings preserved the HUD shell without starting an extra shell'
 [void][HudProbe]::SetWindowPos($settingsWindow,[IntPtr]::Zero,$screen.Left+80,$screen.Top+80,$screen.Width-160,$screen.Height-160,0x14);Wait-Ui 400
 $root=[System.Windows.Automation.AutomationElement]::FromHandle($settingsWindow)
 $appearance=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'AppearanceNavItem'))
 Assert-Probe ($null -ne $appearance) 'separate Settings window exposes Appearance'
 ([System.Windows.Automation.SelectionItemPattern]$appearance.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)).Select();Wait-Ui 400
 $horizontal=Get-HudPaddingField $root 'HUD horizontal padding';$vertical=Get-HudPaddingField $root 'HUD vertical padding'
 $save=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.PropertyCondition]::new([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'SaveButton'))
 Set-HudPaddingField $horizontal '64';Set-HudPaddingField $vertical '32'
 ([System.Windows.Automation.InvokePattern]$save.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)).Invoke();Wait-Ui 1000
 $saved=Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json
 Assert-Probe ($saved.hudHorizontalPadding -eq 64 -and $saved.hudVerticalPadding -eq 32) 'separate Settings window saved HUD padding'
 Invoke-FixtureChord 0x7D;Wait-Ui 500
 $content=@(Get-TerminalBounds)[0];$scale=[HudProbe]::GetDpiForWindow($target)/96.0
 Assert-Probe ([Math]::Abs($content.Left-($screen.Left+64*$scale)) -le 2 -and [Math]::Abs($content.Top-($screen.Top+32*$scale)) -le 2) 'existing HUD applied the saved DPI-aware padding'
 [void][HudProbe]::PostMessageW($settingsWindow,0x10,[IntPtr]::Zero,[IntPtr]::Zero);Wait-Ui 300
 [void][HudProbe]::PostMessageW($target,0x10,[IntPtr]::Zero,[IntPtr]::Zero);Wait-Ui 600
 Assert-Probe (-not [HudProbe]::IsWindow($target) -and $null -eq (Get-Process -Id $hudShell -ErrorAction SilentlyContinue)) 'closing HUD ended its shell'
 Assert-Probe ([HudProbe]::IsWindow($normal) -and $null -ne (Get-Process -Id $normalShell -ErrorAction SilentlyContinue)) 'closing HUD retained the ordinary terminal and its shell'
 [void][HudProbe]::SetForegroundWindow($background.Handle);Wait-Ui 100
 Invoke-FixtureChord 0x7D
 $replacement=Wait-NewWindow $process @($normal);Wait-Ui 500
 Assert-Probe ($replacement -ne $target -and ((Read-State $replacement).exstyle -band 8) -ne 0) 'global summon recreated HUD while an ordinary window kept the fork running'
 Assert-Probe ((Read-State $normal).rect.Equals($before.rect)) 'normal terminal remained unchanged throughout HUD lifecycle'
 Write-Output 'DESKTOP_SMOKE_PASSED'
}finally{
 if($second -and -not $second.HasExited){$second.Kill($true);[void]$second.WaitForExit(5000)}
 if($process -and -not $process.HasExited){$process.Kill($true);[void]$process.WaitForExit(5000)}
 [void][HudProbe]::SetCursorPos($cursor.X,$cursor.Y)
 $background.Close();$background.Dispose()
}
