. "$PSScriptRoot/common.ps1"
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public class WW {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc f, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int hh, bool r);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
'@
function Find-Tg {
  $script:found = [IntPtr]::Zero
  [WW]::EnumWindows({ param($h, $l)
    if ([WW]::IsWindowVisible($h)) {
      $sb = New-Object System.Text.StringBuilder 512
      [WW]::GetWindowText($h, $sb, 512) | Out-Null
      if ($sb.ToString() -like "*Telegram*") { $script:found = $h; return $false }
    }
    return $true }, [IntPtr]::Zero) | Out-Null
  return $script:found
}
Start-Process chrome -ArgumentList "--new-window", "https://web.telegram.org/a/"
$h = [IntPtr]::Zero
for ($i = 0; $i -lt 40 -and $h -eq [IntPtr]::Zero; $i++) { Start-Sleep -Milliseconds 250; $h = Find-Tg }
if ($h -eq [IntPtr]::Zero) { "no telegram window"; exit 1 }
$s = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
[WW]::ShowWindow($h, 9) | Out-Null
[WW]::MoveWindow($h, $s.Bounds.X + 40, $s.Bounds.Y + 40, 1200, 900, $true) | Out-Null
Start-Sleep -Milliseconds 300
[WW]::ShowWindow($h, 3) | Out-Null
[WW]::SetForegroundWindow($h) | Out-Null
"hwnd {0} moved to right screen {1}" -f $h, $s.Bounds
$h.ToInt64() | Out-File -Encoding ascii (Join-Path (Join-Path $PSScriptRoot "../../.out/telegram") "hwnd.txt")
