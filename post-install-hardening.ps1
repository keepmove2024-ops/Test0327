# ============================================================
# post-install-hardening.ps1
# Run INSIDE the VM (elevated PowerShell) after setup-iis.ps1.
# Hardens Windows Server 2025 + IIS for production use.
# ============================================================

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== Post-Install Security Hardening ===" -ForegroundColor Cyan

# ── 1. Windows Update ────────────────────────────────────────
Write-Host "`n[1/8] Checking Windows Update..."
Install-Module PSWindowsUpdate -Force -SkipPublisherCheck -ErrorAction SilentlyContinue
Import-Module PSWindowsUpdate -ErrorAction SilentlyContinue
if (Get-Command Get-WindowsUpdate -ErrorAction SilentlyContinue) {
    Get-WindowsUpdate -AcceptAll -Install -AutoReboot:$false | Out-Null
    Write-Host "  Updates installed (reboot may be required)."
} else {
    Write-Warning "  PSWindowsUpdate not available – run Windows Update manually."
}

# ── 2. Disable unnecessary Windows features ──────────────────
Write-Host "`n[2/8] Disabling unneeded Windows features..."
$DisableFeatures = @(
    "SMB1Protocol",
    "TelnetClient",
    "TFTP",
    "WindowsMediaPlayer"
)
foreach ($f in $DisableFeatures) {
    Disable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -ErrorAction SilentlyContinue
    Write-Host "  Disabled: $f"
}

# ── 3. TLS configuration ─────────────────────────────────────
Write-Host "`n[3/8] Hardening TLS (disable SSL3/TLS1.0/TLS1.1)..."

$ProtocolsBase = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols"
$DisableProtos = @("SSL 2.0","SSL 3.0","TLS 1.0","TLS 1.1")
$EnableProtos  = @("TLS 1.2","TLS 1.3")

foreach ($proto in $DisableProtos) {
    $path = "$ProtocolsBase\$proto\Server"
    New-Item -Path $path -Force | Out-Null
    Set-ItemProperty -Path $path -Name "Enabled"             -Value 0 -Type DWord
    Set-ItemProperty -Path $path -Name "DisabledByDefault"   -Value 1 -Type DWord
    Write-Host "  Disabled: $proto"
}
foreach ($proto in $EnableProtos) {
    $path = "$ProtocolsBase\$proto\Server"
    New-Item -Path $path -Force | Out-Null
    Set-ItemProperty -Path $path -Name "Enabled"           -Value 1 -Type DWord
    Set-ItemProperty -Path $path -Name "DisabledByDefault" -Value 0 -Type DWord
    Write-Host "  Enabled:  $proto"
}

# Disable weak cipher suites
$WeakCiphers = @("RC4 128/128","RC4 40/128","RC4 56/128","DES 56/56","NULL","Triple DES 168")
foreach ($c in $WeakCiphers) {
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\$c"
    New-Item -Path $path -Force | Out-Null
    Set-ItemProperty -Path $path -Name "Enabled" -Value 0 -Type DWord
    Write-Host "  Disabled cipher: $c"
}

# ── 4. Windows Firewall baseline ─────────────────────────────
Write-Host "`n[4/8] Configuring Windows Firewall..."

# Ensure firewall is on for all profiles
Set-NetFirewallProfile -Profile Domain,Public,Private -Enabled True
Write-Host "  Firewall enabled on all profiles"

# Block inbound by default; allow established outbound
Set-NetFirewallProfile -Profile Domain,Public,Private -DefaultInboundAction Block -DefaultOutboundAction Allow
Write-Host "  Default inbound: Block | Default outbound: Allow"

# Explicitly allow needed inbound ports
$AllowedPorts = @(
    @{Name="IIS HTTP";  Port=80;   Proto="TCP"},
    @{Name="IIS HTTPS"; Port=443;  Proto="TCP"},
    @{Name="RDP";       Port=3389; Proto="TCP"}
)
foreach ($r in $AllowedPorts) {
    if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound `
            -Protocol $r.Proto -LocalPort $r.Port -Action Allow | Out-Null
    }
    Write-Host "  Allowed: $($r.Name) (port $($r.Port))"
}

# ── 5. IIS security hardening ────────────────────────────────
Write-Host "`n[5/8] IIS-specific hardening..."
Import-Module WebAdministration

# Remove unused HTTP methods globally
# (OPTIONS/TRACE already blocked in setup-iis.ps1 web.config)

# Disable WebDAV
$webdav = Get-WindowsFeature -Name "Web-DAV-Publishing" -ErrorAction SilentlyContinue
if ($webdav -and $webdav.Installed) {
    Remove-WindowsFeature Web-DAV-Publishing | Out-Null
    Write-Host "  Removed WebDAV"
} else {
    Write-Host "  WebDAV not installed – skipping"
}

# Set IIS application pool identity (already set in setup-iis.ps1, verify here)
$poolName = "WinServer2025Pool"
if (Test-Path "IIS:\AppPools\$poolName") {
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.userName  -Value ""
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.password  -Value ""
    Set-ItemProperty "IIS:\AppPools\$poolName" -Name processModel.identityType -Value 4  # ApplicationPoolIdentity
    Write-Host "  App pool '$poolName' using ApplicationPoolIdentity"
}

# Disable directory listing site-wide
Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
    -Filter "system.webServer/directoryBrowse" -Name "enabled" -Value $false
Write-Host "  Directory listing disabled"

# ── 6. Account policies ──────────────────────────────────────
Write-Host "`n[6/8] Applying account & audit policies..."

# Password policy
net accounts /minpwlen:14 /maxpwage:90 /minpwage:1 /uniquepw:10 | Out-Null
Write-Host "  Password policy: min 14 chars, max 90 days, history 10"

# Account lockout
net accounts /lockoutthreshold:5 /lockoutwindow:30 /lockoutduration:30 | Out-Null
Write-Host "  Lockout: 5 attempts / 30-min window / 30-min lockout"

# Audit policies (success + failure)
$AuditCategories = @(
    "Logon",
    "Account Logon",
    "Account Management",
    "Policy Change",
    "Privilege Use",
    "System"
)
foreach ($cat in $AuditCategories) {
    auditpol /set /category:"$cat" /success:enable /failure:enable | Out-Null
    Write-Host "  Audit enabled: $cat"
}

# ── 7. Event log sizing ──────────────────────────────────────
Write-Host "`n[7/8] Resizing event logs..."
$Logs = @("Application","Security","System")
foreach ($log in $Logs) {
    wevtutil sl $log /ms:104857600 | Out-Null   # 100 MB
    Write-Host "  $log log: 100 MB"
}

# ── 8. Guest Additions (if ISO attached) ─────────────────────
Write-Host "`n[8/8] Checking for VirtualBox Guest Additions..."
$vboxGA = Get-Volume | Where-Object { $_.DriveType -eq "CD-ROM" } |
          ForEach-Object { "$($_.DriveLetter):\" } |
          Where-Object { Test-Path "${_}VBoxWindowsAdditions.exe" } |
          Select-Object -First 1

if ($vboxGA) {
    Write-Host "  Guest Additions found at $vboxGA – installing silently..."
    Start-Process "${vboxGA}VBoxWindowsAdditions.exe" -ArgumentList "/S" -Wait
    Write-Host "  Guest Additions installed."
} else {
    Write-Warning "  Guest Additions ISO not mounted or already installed – skipping."
}

Write-Host @"

=== Hardening Complete ===

Recommended follow-up actions:
  1. REBOOT the server to apply TLS and feature changes.
  2. Run Windows Update again after reboot.
  3. Configure SSL certificate  – run: iis-config\ssl-binding.ps1
  4. Review IIS logs at: C:\inetpub\logs\LogFiles
  5. Enable HSTS once HTTPS is working (add Strict-Transport-Security header).
"@ -ForegroundColor Green
