# Open Notebook airgap — detect this PC's primary LAN IPv4 (for CORS_ORIGINS / LAN access).
# Prefers the Up adapter that has a default gateway; otherwise falls back to the first
# private IPv4 (192.168 / 10 / 172.16-31), skipping loopback (127.*) and APIPA (169.254.*).
# Prints one IP line, or nothing if none found. (Mirrors AeroOne scripts\windows\detect_lan_ip.ps1.)
$ErrorActionPreference = 'SilentlyContinue'

$ip = $null

$gw = Get-NetIPConfiguration |
  Where-Object { $_.NetAdapter -and $_.NetAdapter.Status -eq 'Up' -and $_.IPv4DefaultGateway } |
  Select-Object -First 1
if ($gw -and $gw.IPv4Address) {
  $ip = @($gw.IPv4Address)[0].IPAddress
}

if (-not $ip) {
  $candidate = Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object {
      $_.IPAddress -notlike '127.*' -and
      $_.IPAddress -notlike '169.254.*' -and
      (
        $_.IPAddress -like '192.168.*' -or
        $_.IPAddress -like '10.*' -or
        $_.IPAddress -match '^172\.(1[6-9]|2[0-9]|3[0-1])\.'
      )
    } |
    Select-Object -First 1
  if ($candidate) { $ip = $candidate.IPAddress }
}

if ($ip) { Write-Output $ip }
