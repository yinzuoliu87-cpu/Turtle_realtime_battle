param([int]$ix, [int]$iy, [int]$scale = 2)
. "$PSScriptRoot/common.ps1"
$s = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
$x = $s.Bounds.X + $ix * $scale; $y = $s.Bounds.Y + $iy * $scale
[W]::SetCursorPos($x, $y) | Out-Null
Start-Sleep -Milliseconds 150
$p = New-Object W+P; [W]::GetCursorPos([ref]$p) | Out-Null
"cursor at {0},{1} (wanted {2},{3})" -f $p.X, $p.Y, $x, $y
[W]::mouse_event(2, 0, 0, 0, [IntPtr]::Zero); Start-Sleep -Milliseconds 60; [W]::mouse_event(4, 0, 0, 0, [IntPtr]::Zero)
