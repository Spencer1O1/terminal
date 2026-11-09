param([string]$Receipt)
$ErrorActionPreference = 'Stop'
@{ pid = $PID; started = [DateTime]::UtcNow.ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $Receipt
[Console]::Write("`e[2J`e[H`e[38;2;255;255;255;48;2;0;0;0m")
for ($row = 0; $row -lt 8; $row++) {
    [Console]::WriteLine(('HUD MODE PROBE ' + [string][char]0x2588 * 24))
}
[Console]::Write("`e[0m")
while ($true) {
    $key = [Console]::ReadKey($true)
    Add-Content -LiteralPath ($Receipt + '.keys') -Value ([int]$key.KeyChar)
    if ($key.Key -eq [ConsoleKey]::F8) { break }
}
