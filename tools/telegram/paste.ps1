param([string]$file)
. "$PSScriptRoot/common.ps1"
$t = [System.IO.File]::ReadAllText($file, [System.Text.Encoding]::UTF8)
Set-Clipboard -Value $t
Start-Sleep -Milliseconds 150
[System.Windows.Forms.SendKeys]::SendWait("^v")
