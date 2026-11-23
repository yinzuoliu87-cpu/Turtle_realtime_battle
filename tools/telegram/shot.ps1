param([string]$Name = "t")
. "$PSScriptRoot/common.ps1"
$s = [System.Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1
$b = $s.Bounds
$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($b.X, $b.Y, 0, 0, $bmp.Size)
$half = New-Object System.Drawing.Bitmap ([int]($b.Width / 2)), ([int]($b.Height / 2))
$g2 = [System.Drawing.Graphics]::FromImage($half)
$g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
$g2.DrawImage($bmp, 0, 0, $half.Width, $half.Height)
$out = Join-Path (Join-Path $PSScriptRoot "../../.out/telegram") "$Name.png"
$half.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $g2.Dispose(); $bmp.Dispose(); $half.Dispose()
"right screen {0} -> {1} (half size)" -f $b, $out
