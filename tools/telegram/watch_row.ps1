## watch first chat row of Telegram list on right screen; print when pixels change
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public class DpiW { [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr c); }
'@
[DpiW]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
$s = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
$x = $s.Bounds.X + 130; $y = $s.Bounds.Y + 320; $w = 520; $h = 100
$last = ""
$sha = [System.Security.Cryptography.SHA1]::Create()
while ($true) {
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($x, $y, 0, 0, $bmp.Size)
  $ms = New-Object System.IO.MemoryStream
  $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Bmp)
  $hash = [BitConverter]::ToString($sha.ComputeHash($ms.ToArray())).Substring(0, 11)
  $g.Dispose(); $bmp.Dispose(); $ms.Dispose()
  if ($last -ne "" -and $hash -ne $last) { "$(Get-Date -Format HH:mm:ss) CHAT ROW CHANGED"; [Console]::Out.Flush() }
  $last = $hash
  Start-Sleep -Seconds 8
}
