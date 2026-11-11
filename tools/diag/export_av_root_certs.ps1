# Turtle Arena - TLS diagnostics (2026-11-11, mainsite beta test: Norton -> "TLS handshake error -9984").
# Exports the root certificates that antivirus products install into the Windows "Trusted Root" store
# (Norton / Symantec / Avast / AVG / Kaspersky / ESET / Bitdefender / Avira / McAfee / Sophos ...)
# to a folder on the Desktop, so the game team can test whether the game's TLS library can parse them.
# These are PUBLIC certificates (no private keys). Nothing is uploaded; send the folder yourself.
#
# Run: right-click -> "Run with PowerShell"   (or: powershell -ExecutionPolicy Bypass -File export_av_root_certs.ps1)

$ErrorActionPreference = "Stop"
$out = Join-Path ([Environment]::GetFolderPath("Desktop")) "turtle_tls_diag"
New-Item -ItemType Directory -Force -Path $out | Out-Null
$pat = "Norton|Symantec|Gen Digital|Avast|AVG|Kaspersky|ESET|Bitdefender|Avira|McAfee|Sophos|Web.?Shield|Mail Shield|Trend Micro|Malwarebytes"
$stores = @("Cert:\LocalMachine\Root", "Cert:\CurrentUser\Root", "Cert:\LocalMachine\AuthRoot")
$n = 0
$summary = @()
foreach ($s in $stores) {
	foreach ($c in (Get-ChildItem -Path $s -ErrorAction SilentlyContinue)) {
		if (($c.Subject -match $pat) -or ($c.Issuer -match $pat)) {
			$name = ($c.Subject -replace "[^A-Za-z0-9]+", "_")
			if ($name.Length -gt 40) { $name = $name.Substring(0, 40) }
			$file = Join-Path $out ("{0}_{1}.pem" -f $name, $c.Thumbprint.Substring(0, 8))
			$b64 = [Convert]::ToBase64String($c.RawData, "InsertLineBreaks")
			Set-Content -Path $file -Encoding Ascii -Value ("-----BEGIN CERTIFICATE-----`r`n" + $b64 + "`r`n-----END CERTIFICATE-----")
			$summary += ("{0} | {1} | sig={2} | key={3} | {4}" -f $s, $c.Subject, $c.SignatureAlgorithm.FriendlyName, $c.PublicKey.Oid.FriendlyName, $c.Thumbprint)
			$n++
		}
	}
}
$all = @()
foreach ($s in $stores) { $all += (Get-ChildItem -Path $s -ErrorAction SilentlyContinue | Measure-Object).Count }
$summary += ("root store sizes: " + ($all -join " / ") + "   exported: " + $n)
Set-Content -Path (Join-Path $out "summary.txt") -Encoding Ascii -Value $summary
Write-Host ("Exported {0} certificate(s) to {1}" -f $n, $out)
Write-Host "Please send the whole folder (and the game log with the -9984 line) to the game team."
