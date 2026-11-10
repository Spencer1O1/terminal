# Window-order regression probes for the owned desktop fixture.
function Assert-NewWindowBelowHud([bool]$Activate, [string]$Context) {
    $newApp=[HudProbeApplication]::new()
    $newApp.Text='HUD owned new-application probe'
    $newApp.FormBorderStyle='None'
    $newApp.StartPosition='Manual'
    $newApp.Bounds=$screen
    $newApp.BackColor=[System.Drawing.Color]::FromArgb(40,160,220)
    $newApp.ActivateOnShow=$Activate
    $newApp.TopMost=$false
    try {
        $newApp.Show()
        if ($Activate) { [void][HudProbe]::SetForegroundWindow($newApp.Handle) }
        Wait-Ui 800
        $hud=Read-State $target
        Write-Output ("New application ($Context): HUD styles={0:X}; app styles={1:X}" -f $hud.exstyle,([HudProbe]::GetWindowLongPtrW($newApp.Handle,-20).ToInt64()))
        Assert-Probe (($hud.exstyle -band 8) -ne 0) "$Context retained HUD topmost style"
        Assert-Probe ([HudProbe]::IsAbove($target,$newApp.Handle)) "$Context kept HUD above a window created later"
        $expected=if ($Activate) { $newApp.Handle } else { $target }
        Assert-Probe ([HudProbe]::GetForegroundWindow() -eq $expected) "$Context preserved the expected input focus"
        $capture=[System.Drawing.Bitmap]::new([Math]::Min(900,$screen.Width),[Math]::Min(350,$screen.Height))
        $paint=[System.Drawing.Graphics]::FromImage($capture)
        try {
            $paint.CopyFromScreen($screen.Location,[System.Drawing.Point]::Empty,$capture.Size)
            $capture.Save((Join-Path $EvidenceDirectory ($Context+'-new-application.png')))
            $white=0
            for ($y=0;$y -lt $capture.Height;$y+=2) {
                for ($x=0;$x -lt $capture.Width;$x+=2) {
                    $pixel=$capture.GetPixel($x,$y)
                    if ($pixel.R -ge 245 -and $pixel.G -ge 245 -and $pixel.B -ge 245) { $white++ }
                }
            }
            Assert-Probe ($white -gt 1000) "$Context retained visible HUD text over the new window"
        } finally { $paint.Dispose();$capture.Dispose() }
    } finally {
        $newApp.Close();$newApp.Dispose()
        if ($Activate) { [void][HudProbe]::SetForegroundWindow($background.Handle) }
        Wait-Ui 200
    }
}
function Assert-NewExplorerBelowHud([string]$Context) {
    $folder=Join-Path $EvidenceDirectory ('explorer-'+$Context)
    New-Item -ItemType Directory -Path $folder | Out-Null
    $shell=New-Object -ComObject Shell.Application
    $before=@($shell.Windows() | ForEach-Object { $_.HWND })
    $explorer=$null
    try {
        Start-Process -FilePath explorer.exe -ArgumentList ('/n,"'+$folder+'"') | Out-Null
        for ($attempt=0;$attempt -lt 100;$attempt++) {
            Wait-Ui 100
            foreach ($candidate in $shell.Windows()) {
                try {
                    if ($candidate.LocationURL -and ([uri]$candidate.LocationURL).LocalPath.TrimEnd('\') -eq $folder.TrimEnd('\')) { $explorer=$candidate;break }
                } catch { }
            }
            if ($explorer) { break }
        }
        Assert-Probe ($null -ne $explorer) "$Context opened the owned Explorer folder"
        $window=[IntPtr]::new([long]$explorer.HWND)
        Assert-Probe ($explorer.HWND -notin $before) "$Context created a new Explorer window"
        [void][HudProbe]::SetForegroundWindow($window)
        Wait-Ui 500
        $hud=Read-State $target
        Write-Output ("Explorer ($Context): HUD styles={0:X}; Explorer styles={1:X}" -f $hud.exstyle,([HudProbe]::GetWindowLongPtrW($window,-20).ToInt64()))
        Assert-Probe ([HudProbe]::IsAbove($target,$window)) "$Context kept HUD above newly opened Explorer"
        Assert-Probe ([HudProbe]::GetForegroundWindow() -eq $window) "$Context retained Explorer keyboard focus"
        # Cover the text probe with this owned Explorer window for a pixel check.
        [void][HudProbe]::SetWindowPos($window,[IntPtr]::Zero,$screen.Left,$screen.Top,[Math]::Min(1200,$screen.Width),[Math]::Min(800,$screen.Height),0x14)
        Wait-Ui 400
        $capture=[System.Drawing.Bitmap]::new([Math]::Min(900,$screen.Width),[Math]::Min(350,$screen.Height))
        $paint=[System.Drawing.Graphics]::FromImage($capture)
        try {
            $paint.CopyFromScreen($screen.Location,[System.Drawing.Point]::Empty,$capture.Size)
            $capture.Save((Join-Path $EvidenceDirectory ($Context+'-explorer.png')))
            $magenta=0
            for ($y=0;$y -lt $capture.Height;$y+=2) {
                for ($x=0;$x -lt $capture.Width;$x+=2) {
                    $pixel=$capture.GetPixel($x,$y)
                    if ($pixel.R -ge 240 -and $pixel.G -le 15 -and $pixel.B -ge 240) { $magenta++ }
                }
            }
            Assert-Probe ($magenta -gt 500) "$Context retained HUD text visibly over Explorer"
        } finally { $paint.Dispose();$capture.Dispose() }
    } finally {
        # Never close an existing Explorer window or a window the user navigated.
        if ($explorer -and $explorer.HWND -notin $before -and ([uri]$explorer.LocationURL).LocalPath.TrimEnd('\') -eq $folder.TrimEnd('\')) { $explorer.Quit() }
        [void][HudProbe]::SetForegroundWindow($background.Handle)
        Wait-Ui 200
    }
}
