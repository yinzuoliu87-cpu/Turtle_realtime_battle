param([string]$k)
. "$PSScriptRoot/common.ps1"
[System.Windows.Forms.SendKeys]::SendWait($k)
