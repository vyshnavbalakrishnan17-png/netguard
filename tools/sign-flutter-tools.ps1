# Re-sign Flutter's Windows tool binaries so Smart App Control (SAC)
# accepts them. Run this after a Flutter upgrade (fresh downloads are
# unsigned again and SAC blocks them).
#
# The signing certificate stays in CurrentUser\My + Root + TrustedPublisher
# for 2 years; deleting it invalidates the signatures (re-run this script).
$ErrorActionPreference = 'Stop'

$cert = Get-ChildItem Cert:\CurrentUser\My |
  Where-Object { $_.Subject -eq 'CN=Flutter Local Build' -and $_.NotAfter -gt (Get-Date).AddDays(30) } |
  Sort-Object NotAfter -Descending | Select-Object -First 1
if (-not $cert) {
  $cert = New-SelfSignedCertificate -Type CodeSigningCert `
    -Subject 'CN=Flutter Local Build' -CertStoreLocation Cert:\CurrentUser\My `
    -NotAfter (Get-Date).AddYears(2)
  foreach ($store in @('Root', 'TrustedPublisher')) {
    $s = New-Object System.Security.Cryptography.X509Certificates.X509Store($store, 'CurrentUser')
    $s.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
    $s.Add($cert)
    $s.Close()
  }
  Write-Host "created certificate $($cert.Thumbprint)"
}

$paths = @(
  'C:\src\flutter\bin\cache\artifacts\engine',
  'C:\src\flutter\bin\cache\dart-sdk\bin'
)
$count = 0
foreach ($root in $paths) {
  if (-not (Test-Path $root)) { continue }
  Get-ChildItem $root -Recurse -Filter *.exe -File | ForEach-Object {
    $sig = Get-AuthenticodeSignature $_.FullName
    if ($sig.Status -eq 'Valid') { return } # already trusted by someone
    try {
      $r = Set-AuthenticodeSignature -FilePath $_.FullName -Certificate $cert
      if ($r.Status -eq 'Valid') { $count++; Write-Host "signed $($_.FullName)" }
      else { Write-Host "FAILED $($_.FullName): $($r.Status)" }
    } catch { Write-Host "ERROR $($_.FullName): $($_.Exception.Message)" }
  }
}
Write-Host "done - $count file(s) signed"
