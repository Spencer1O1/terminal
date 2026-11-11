param([string]$Receipt)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Receipt -PathType Container) { $Receipt=Join-Path $Receipt ('shell-'+$PID+'.json') }
[Console]::Title='HUD owned shell '+$PID
@{ pid = $PID; started = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $Receipt
[Console]::Write("`e[2J`e[H`e[38;2;255;255;255;48;2;0;0;0m")
# Alternating colors keep both markers visible after short-window scrollback
# or DPI changes; magenta remains measurable over light application content.
for ($row = 0; $row -lt 8; $row++) {
    $color=if (($row % 2) -eq 0) { "`e[38;2;255;0;255m" } else { "`e[38;2;255;255;255m" }
    [Console]::WriteLine(($color + 'HUD MODE PROBE ' + [string][char]0x2588 * 24))
}
[Console]::Write("`e[0m")
while ($true) {
    $key = [Console]::ReadKey($true)
    Add-Content -LiteralPath ($Receipt + '.keys') -Value ([int]$key.KeyChar)
    if ($key.Key -eq [ConsoleKey]::F8) { break }
}
