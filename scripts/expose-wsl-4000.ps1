param(
  [string]$ListenAddress = "192.168.0.250",
  [int]$Port = 4000
)

$ErrorActionPreference = "Stop"

function Test-Admin {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
  $args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", "`"$PSCommandPath`"",
    "-ListenAddress", $ListenAddress,
    "-Port", $Port
  )

  Write-Host "Requesting Administrator rights to update Windows port forwarding..."
  Start-Process powershell.exe -Verb RunAs -ArgumentList $args
  exit
}

$wslIps = (wsl.exe hostname -I).Trim().Split(" ", [StringSplitOptions]::RemoveEmptyEntries)
$wslIp = $wslIps | Where-Object { $_ -match '^\d+\.\d+\.\d+\.\d+$' } | Select-Object -First 1

if (-not $wslIp) {
  throw "Could not determine the WSL IPv4 address."
}

Write-Host "Using WSL backend ${wslIp}:$Port"

$backendReachable = Test-NetConnection -ComputerName $wslIp -Port $Port -InformationLevel Quiet
if (-not $backendReachable) {
  throw "Windows cannot reach WSL at ${wslIp}:$Port. Start the app in WSL first."
}

netsh interface portproxy delete v4tov4 listenaddress=$ListenAddress listenport=$Port | Out-Null
netsh interface portproxy add v4tov4 listenaddress=$ListenAddress listenport=$Port connectaddress=$wslIp connectport=$Port | Out-Null

$ruleName = "Kakemono WSL $Port"
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
if ($existingRule) {
  Remove-NetFirewallRule -DisplayName $ruleName
}

New-NetFirewallRule `
  -DisplayName $ruleName `
  -Direction Inbound `
  -Action Allow `
  -Protocol TCP `
  -LocalPort $Port `
  -Profile Private `
  -RemoteAddress LocalSubnet | Out-Null

Write-Host ""
Write-Host "Current portproxy rules:"
netsh interface portproxy show v4tov4

Write-Host ""
Write-Host "Windows listener:"
Get-NetTCPConnection -LocalPort $Port -State Listen | Format-Table -AutoSize

Write-Host ""
$localReachable = Test-NetConnection -ComputerName $ListenAddress -Port $Port -InformationLevel Quiet
if ($localReachable) {
  Write-Host "OK: http://${ListenAddress}:$Port/d/saman-tablet"
} else {
  throw "Portproxy was created, but Windows still cannot connect to ${ListenAddress}:$Port."
}

Read-Host "Press Enter to close"
