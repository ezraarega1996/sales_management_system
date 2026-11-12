# Runs the app on a connected phone, pointed at the backend on THIS computer's current Wi-Fi IP.
# The router can give the computer a new IP at any time; this picks up whatever it is now.
#
#   .\run_on_phone.ps1            # first connected Android phone
#   .\run_on_phone.ps1 -Device R8YYC1D518P
param([string]$Device = "")

$ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceAlias "Wi-Fi*" -ErrorAction SilentlyContinue |
  Where-Object { $_.IPAddress -notlike '169.254.*' } |
  Select-Object -First 1 -ExpandProperty IPAddress
if (-not $ip) { Write-Error "No Wi-Fi IP found. Is the computer connected to Wi-Fi?"; exit 1 }

$api = "http://${ip}:5000/api"
Write-Host "Backend: $api"
$deviceArgs = if ($Device) { @("-d", $Device) } else { @() }
flutter run @deviceArgs --debug "--dart-define=API_URL=$api"
