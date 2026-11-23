Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices; using System.Text;
public class WW2 { [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n); [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h); }
'@
$h = [IntPtr][long](Get-Content (Join-Path (Join-Path $PSScriptRoot "../../.out/telegram") "hwnd.txt") | Select-Object -First 1)
$last = ""
while ($true) {
  if (-not [WW2]::IsWindow($h)) { "Telegram 窗口没了"; exit 0 }
  $sb = New-Object System.Text.StringBuilder 256
  [WW2]::GetWindowText($h, $sb, 256) | Out-Null
  $t = $sb.ToString()
  if ($t -ne $last) { "$(Get-Date -Format HH:mm:ss) 标题: $t"; [Console]::Out.Flush(); $last = $t }
  Start-Sleep -Seconds 10
}
