param([int]$x, [int]$y, [int]$w, [int]$h, [string]$Name = "crop")
# 右屏全分辨率截一块(坐标按半尺寸截图 ×2)
. "$PSScriptRoot/common.ps1"
$s = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
$bmp = New-Object System.Drawing.Bitmap ($w * 2), ($h * 2)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($s.Bounds.X + $x * 2, $s.Bounds.Y + $y * 2, 0, 0, $bmp.Size)
$out = Join-Path (Join-Path $PSScriptRoot "../../.out/telegram") "$Name.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
"saved $out"
