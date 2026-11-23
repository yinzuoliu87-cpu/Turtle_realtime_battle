param([int]$ix, [int]$iy, [int]$notches = 5, [int]$scale = 2)
. "$PSScriptRoot/common.ps1"
$s = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
[W]::SetCursorPos($s.Bounds.X + $ix * $scale, $s.Bounds.Y + $iy * $scale) | Out-Null
Start-Sleep -Milliseconds 100
[uint32]$d = if ($notches -ge 0) { 120 } else { 4294967176 }   # -120 的无符号写法
for ($i = 0; $i -lt [math]::Abs($notches); $i++) {
  [W]::mouse_event(0x0800, 0, 0, $d, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 40
}
"scrolled $notches"
