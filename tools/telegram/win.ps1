param([string]$Act = "move")
. "$PSScriptRoot/common.ps1"
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class WW {
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
'@
## 打开某个对话后标题会变成对方名字(「Tom」), 按标题找不到 ⇒ 先用 open.ps1 存下的句柄(2026-11-23)
$hf = Join-Path (Join-Path $PSScriptRoot "../../.out/telegram") "hwnd.txt"
$h = [IntPtr]::Zero
if (Test-Path $hf) { $h = [IntPtr][long](Get-Content $hf | Select-Object -First 1) }
if ($h -eq [IntPtr]::Zero) {
  $p = Get-Process chrome -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*Telegram*" } | Select-Object -First 1
  if (-not $p) { "no telegram window"; exit 1 }
  $h = $p.MainWindowHandle
}
if ($Act -eq "close") { [WW]::PostMessage($h, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null; "closed"; exit 0 }
$s = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
[WW]::ShowWindow($h, 9) | Out-Null
[WW]::MoveWindow($h, $s.Bounds.X + 50, $s.Bounds.Y + 50, 1600, 1100, $true) | Out-Null
Start-Sleep -Milliseconds 300
[WW]::ShowWindow($h, 3) | Out-Null
[WW]::SetForegroundWindow($h) | Out-Null
"moved {0} to {1}" -f $h, $s.Bounds
