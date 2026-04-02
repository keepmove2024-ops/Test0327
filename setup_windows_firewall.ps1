# Windows Server 2025 - Windows Defender Firewall Setup Script
# Equivalent to: Control Panel > Windows Defender Firewall
# Run as Administrator in PowerShell

#Requires -RunAsAdministrator

Write-Host "=== Windows Server 2025 Firewall Setup ===" -ForegroundColor Cyan

# -------------------------------------------------------
# 1. Enable Windows Defender Firewall on all profiles
# -------------------------------------------------------
Write-Host "`n[1] Enabling Windows Defender Firewall on all profiles..." -ForegroundColor Yellow

Set-NetFirewallProfile -Profile Domain    -Enabled True
Set-NetFirewallProfile -Profile Private   -Enabled True
Set-NetFirewallProfile -Profile Public    -Enabled True

Write-Host "    Firewall enabled on Domain, Private, and Public profiles." -ForegroundColor Green

# -------------------------------------------------------
# 2. Set default inbound/outbound behavior per profile
# -------------------------------------------------------
Write-Host "`n[2] Configuring default inbound/outbound actions..." -ForegroundColor Yellow

# Domain profile: block inbound by default, allow outbound
Set-NetFirewallProfile -Profile Domain `
    -DefaultInboundAction  Block `
    -DefaultOutboundAction Allow `
    -NotifyOnListen        True `
    -LogAllowed            True `
    -LogBlocked            True `
    -LogFileName           "%SystemRoot%\System32\LogFiles\Firewall\pfirewall_domain.log" `
    -LogMaxSizeKilobytes   4096

# Private profile
Set-NetFirewallProfile -Profile Private `
    -DefaultInboundAction  Block `
    -DefaultOutboundAction Allow `
    -NotifyOnListen        True `
    -LogAllowed            False `
    -LogBlocked            True `
    -LogFileName           "%SystemRoot%\System32\LogFiles\Firewall\pfirewall_private.log" `
    -LogMaxSizeKilobytes   4096

# Public profile (most restrictive)
Set-NetFirewallProfile -Profile Public `
    -DefaultInboundAction  Block `
    -DefaultOutboundAction Allow `
    -NotifyOnListen        True `
    -LogAllowed            False `
    -LogBlocked            True `
    -LogFileName           "%SystemRoot%\System32\LogFiles\Firewall\pfirewall_public.log" `
    -LogMaxSizeKilobytes   4096

Write-Host "    Default actions set: Inbound=Block, Outbound=Allow." -ForegroundColor Green

# -------------------------------------------------------
# 3. Remove any conflicting custom rules (optional cleanup)
# -------------------------------------------------------
Write-Host "`n[3] Removing old custom rules named 'Custom-*'..." -ForegroundColor Yellow
Get-NetFirewallRule -Name "Custom-*" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
Write-Host "    Cleanup done." -ForegroundColor Green

# -------------------------------------------------------
# 4. Allow core Windows services (inbound)
# -------------------------------------------------------
Write-Host "`n[4] Adding inbound allow rules for core services..." -ForegroundColor Yellow

$rules = @(
    # Remote Desktop (RDP)
    @{ Name="Custom-RDP-In";       DisplayName="Remote Desktop (RDP)";      Protocol="TCP"; LocalPort=3389;  Direction="Inbound";  Profile="Domain,Private" },
    # WinRM (PowerShell Remoting)
    @{ Name="Custom-WinRM-HTTP";   DisplayName="WinRM HTTP (PS Remoting)";  Protocol="TCP"; LocalPort=5985;  Direction="Inbound";  Profile="Domain,Private" },
    @{ Name="Custom-WinRM-HTTPS";  DisplayName="WinRM HTTPS (PS Remoting)"; Protocol="TCP"; LocalPort=5986;  Direction="Inbound";  Profile="Domain,Private" },
    # Web Server
    @{ Name="Custom-HTTP-In";      DisplayName="Web Server HTTP";           Protocol="TCP"; LocalPort=80;    Direction="Inbound";  Profile="Domain,Private,Public" },
    @{ Name="Custom-HTTPS-In";     DisplayName="Web Server HTTPS";          Protocol="TCP"; LocalPort=443;   Direction="Inbound";  Profile="Domain,Private,Public" },
    # DNS
    @{ Name="Custom-DNS-TCP";      DisplayName="DNS (TCP)";                 Protocol="TCP"; LocalPort=53;    Direction="Inbound";  Profile="Domain,Private" },
    @{ Name="Custom-DNS-UDP";      DisplayName="DNS (UDP)";                 Protocol="UDP"; LocalPort=53;    Direction="Inbound";  Profile="Domain,Private" },
    # ICMP (ping) - allow on Domain/Private only
    @{ Name="Custom-ICMPv4-In";    DisplayName="ICMPv4 Echo Request (Ping)";Protocol="ICMPv4"; LocalPort="Any"; Direction="Inbound"; Profile="Domain,Private" }
)

foreach ($r in $rules) {
    $params = @{
        Name        = $r.Name
        DisplayName = $r.DisplayName
        Protocol    = $r.Protocol
        Direction   = $r.Direction
        Action      = "Allow"
        Enabled     = "True"
        Profile     = $r.Profile -split ","
    }
    if ($r.Protocol -ne "ICMPv4") {
        $params["LocalPort"] = $r.LocalPort
    }
    New-NetFirewallRule @params -ErrorAction SilentlyContinue | Out-Null
    Write-Host "    Added: $($r.DisplayName)" -ForegroundColor Green
}

# -------------------------------------------------------
# 5. Block high-risk ports (inbound)
# -------------------------------------------------------
Write-Host "`n[5] Blocking high-risk inbound ports..." -ForegroundColor Yellow

$blockRules = @(
    @{ Name="Custom-Block-Telnet";  DisplayName="Block Telnet";       Protocol="TCP"; LocalPort=23   },
    @{ Name="Custom-Block-FTP";     DisplayName="Block FTP";          Protocol="TCP"; LocalPort=21   },
    @{ Name="Custom-Block-SMBv1";   DisplayName="Block SMBv1";        Protocol="TCP"; LocalPort=445  },
    @{ Name="Custom-Block-NetBIOS"; DisplayName="Block NetBIOS";      Protocol="TCP"; LocalPort=139  }
)

foreach ($r in $blockRules) {
    New-NetFirewallRule `
        -Name        $r.Name `
        -DisplayName $r.DisplayName `
        -Protocol    $r.Protocol `
        -LocalPort   $r.LocalPort `
        -Direction   "Inbound" `
        -Action      "Block" `
        -Enabled     "True" `
        -Profile     "Any" `
        -ErrorAction SilentlyContinue | Out-Null
    Write-Host "    Blocked: $($r.DisplayName)" -ForegroundColor Green
}

# -------------------------------------------------------
# 6. Display current firewall profile status
# -------------------------------------------------------
Write-Host "`n[6] Current firewall profile status:" -ForegroundColor Yellow
Get-NetFirewallProfile | Select-Object Name, Enabled, DefaultInboundAction, DefaultOutboundAction |
    Format-Table -AutoSize

Write-Host "`n=== Firewall setup complete! ===" -ForegroundColor Cyan
Write-Host "To review rules in Control Panel: firewall.cpl" -ForegroundColor Gray
Write-Host "To open advanced settings:        wf.msc" -ForegroundColor Gray
