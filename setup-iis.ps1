# ============================================================
# setup-iis.ps1
# Run INSIDE the Windows Server 2025 VM (elevated PowerShell).
#
# What this script does:
#   1. Installs IIS with common features
#   2. Installs ASP.NET 4.8 + ASP.NET Core hosting bundle
#   3. Creates a default site and an example app pool
#   4. Configures logging and compression
#   5. Opens firewall rules for HTTP (80) and HTTPS (443)
#   6. Applies basic security headers via web.config
# ============================================================

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=== IIS Setup on Windows Server 2025 ===" -ForegroundColor Cyan

# ── 1. Install IIS & features ────────────────────────────────
Write-Host "`n[1/7] Installing IIS Windows features..."

$Features = @(
    "Web-Server",                      # Core Web Server
    "Web-Common-Http",                 # Default/Static doc, Dir Browse, HTTP Errors
    "Web-Default-Doc",
    "Web-Dir-Browsing",
    "Web-Http-Errors",
    "Web-Static-Content",
    "Web-Http-Redirect",
    "Web-Health",                      # HTTP Logging, Request Monitor, Tracing
    "Web-Http-Logging",
    "Web-Log-Libraries",
    "Web-Request-Monitor",
    "Web-Http-Tracing",
    "Web-Performance",                 # Static/Dynamic Compression
    "Web-Stat-Compression",
    "Web-Dyn-Compression",
    "Web-Security",                    # Basic/Windows Auth, Request Filtering, IP
    "Web-Filtering",
    "Web-Basic-Auth",
    "Web-Windows-Auth",
    "Web-App-Dev",                     # ASP.NET 4.8, ISAPI
    "Web-Net-Ext45",
    "Web-Asp-Net45",
    "Web-ISAPI-Ext",
    "Web-ISAPI-Filter",
    "Web-Mgmt-Tools",                  # IIS Management Console
    "Web-Mgmt-Console",
    "Web-Mgmt-Service",                # Remote management
    "Web-Scripting-Tools"
)

foreach ($f in $Features) {
    $result = Install-WindowsFeature -Name $f -IncludeManagementTools -ErrorAction SilentlyContinue
    if ($result.Success) {
        Write-Host "  [OK] $f"
    } else {
        Write-Warning "  [SKIP] $f – may already be installed or unavailable."
    }
}

# ── 2. Import WebAdministration module ───────────────────────
Write-Host "`n[2/7] Loading WebAdministration module..."
Import-Module WebAdministration

# ── 3. Configure default web site ────────────────────────────
Write-Host "`n[3/7] Configuring Default Web Site..."

$sitePath  = "C:\inetpub\wwwroot"
$siteName  = "Default Web Site"

# Ensure wwwroot exists
New-Item -ItemType Directory -Force -Path $sitePath | Out-Null

# Remove existing default bindings and re-add clean ones
$site = Get-WebSite -Name $siteName -ErrorAction SilentlyContinue
if ($null -eq $site) {
    New-WebSite -Name $siteName -Port 80 -PhysicalPath $sitePath -Force | Out-Null
    Write-Host "  Created site '$siteName' on port 80"
} else {
    Set-ItemProperty "IIS:\Sites\$siteName" -Name physicalPath -Value $sitePath
    Write-Host "  Updated '$siteName' physical path"
}

# ── 4. Create a dedicated App Pool ──────────────────────────
Write-Host "`n[4/7] Configuring Application Pools..."

$poolName = "WinServer2025Pool"
if (-not (Test-Path "IIS:\AppPools\$poolName")) {
    New-WebAppPool -Name $poolName | Out-Null
    Write-Host "  Created app pool '$poolName'"
}

Set-ItemProperty "IIS:\AppPools\$poolName" -Name managedRuntimeVersion -Value "v4.0"
Set-ItemProperty "IIS:\AppPools\$poolName" -Name managedPipelineMode   -Value "Integrated"
Set-ItemProperty "IIS:\AppPools\$poolName" -Name enable32BitAppOnWin64  -Value $false

# Recycling – recycle at 2 AM daily
$recycleTime = [TimeSpan]"02:00:00"
Clear-ItemProperty "IIS:\AppPools\$poolName" -Name recycling.periodicRestart.schedule
Add-WebConfigurationProperty `
    -PSPath "MACHINE/WEBROOT/APPHOST" `
    -Filter "system.applicationHost/applicationPools/add[@name='$poolName']/recycling/periodicRestart/schedule" `
    -Name  "." `
    -Value @{value=$recycleTime}

# Assign pool to default site
Set-ItemProperty "IIS:\Sites\$siteName" -Name applicationPool -Value $poolName
Write-Host "  Assigned '$poolName' to '$siteName'"

# ── 5. IIS-wide settings ─────────────────────────────────────
Write-Host "`n[5/7] Applying global IIS settings..."

# Enable dynamic and static compression
Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
    -Filter "system.webServer/httpCompression" `
    -Name "doDynamicCompression" -Value $true
Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
    -Filter "system.webServer/httpCompression" `
    -Name "doStaticCompression"  -Value $true

# Logging – W3C format, daily rollover
Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
    -Filter "system.applicationHost/sites/siteDefaults/logFile" `
    -Name "logFormat" -Value "W3C"
Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
    -Filter "system.applicationHost/sites/siteDefaults/logFile" `
    -Name "period" -Value "Daily"
Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
    -Filter "system.applicationHost/sites/siteDefaults/logFile" `
    -Name "truncateSize" -Value 10485760   # 10 MB

# Hide server version banner
Set-WebConfigurationProperty -PSPath "MACHINE/WEBROOT/APPHOST" `
    -Filter "system.webServer/security/requestFiltering" `
    -Name "removeServerHeader" -Value $true

# ── 6. Write secure web.config to wwwroot ────────────────────
Write-Host "`n[6/7] Writing web.config with security headers..."

$webConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>

    <!-- Security headers -->
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
        <add name="X-Content-Type-Options"  value="nosniff" />
        <add name="X-Frame-Options"         value="SAMEORIGIN" />
        <add name="X-XSS-Protection"        value="1; mode=block" />
        <add name="Referrer-Policy"         value="strict-origin-when-cross-origin" />
        <add name="Permissions-Policy"      value="geolocation=(), microphone=(), camera=()" />
        <add name="Content-Security-Policy" value="default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline';" />
      </customHeaders>
    </httpProtocol>

    <!-- Default documents -->
    <defaultDocument>
      <files>
        <clear />
        <add value="index.html" />
        <add value="index.htm" />
        <add value="default.aspx" />
      </files>
    </defaultDocument>

    <!-- Static compression -->
    <urlCompression doStaticCompression="true" doDynamicCompression="true" />

    <!-- Request limits -->
    <security>
      <requestFiltering allowDoubleEscaping="false">
        <requestLimits maxAllowedContentLength="30000000" maxUrl="4096" maxQueryString="2048" />
        <verbs>
          <add verb="OPTIONS" allowed="false" />
          <add verb="TRACE"   allowed="false" />
        </verbs>
        <hiddenSegments>
          <add segment=".git" />
          <add segment=".env" />
        </hiddenSegments>
      </requestFiltering>
    </security>

    <!-- Custom error pages -->
    <httpErrors errorMode="Custom" existingResponse="Replace">
      <remove statusCode="403" />
      <remove statusCode="404" />
      <remove statusCode="500" />
      <error statusCode="403" path="/errors/403.html" responseMode="File" />
      <error statusCode="404" path="/errors/404.html" responseMode="File" />
      <error statusCode="500" path="/errors/500.html" responseMode="File" />
    </httpErrors>

  </system.webServer>
</configuration>
"@

Set-Content -Path "$sitePath\web.config" -Value $webConfig -Encoding UTF8
Write-Host "  web.config written to $sitePath"

# Sample index page
$indexHtml = @"
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Windows Server 2025 – IIS</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; background: #0078d4; color: #fff;
           display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; }
    .card { background: #fff; color: #333; border-radius: 8px; padding: 40px 60px; text-align: center;
            box-shadow: 0 8px 32px rgba(0,0,0,.2); }
    h1 { color: #0078d4; margin-top: 0; }
    p  { color: #555; }
  </style>
</head>
<body>
  <div class="card">
    <h1>IIS is running</h1>
    <p>Windows Server 2025 &bull; Internet Information Services</p>
    <p>Replace this page with your application.</p>
  </div>
</body>
</html>
"@

Set-Content -Path "$sitePath\index.html" -Value $indexHtml -Encoding UTF8

# Error pages directory
$errDir = "$sitePath\errors"
New-Item -ItemType Directory -Force -Path $errDir | Out-Null
"<h1>403 Forbidden</h1>"  | Set-Content "$errDir\403.html" -Encoding UTF8
"<h1>404 Not Found</h1>"  | Set-Content "$errDir\404.html" -Encoding UTF8
"<h1>500 Server Error</h1>" | Set-Content "$errDir\500.html" -Encoding UTF8

# ── 7. Firewall rules ────────────────────────────────────────
Write-Host "`n[7/7] Opening firewall ports 80 and 443..."

$fwRules = @(
    @{Name="IIS HTTP";  Protocol="TCP"; Port=80},
    @{Name="IIS HTTPS"; Protocol="TCP"; Port=443}
)
foreach ($r in $fwRules) {
    if (-not (Get-NetFirewallRule -DisplayName $r.Name -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $r.Name -Direction Inbound -Protocol $r.Protocol `
            -LocalPort $r.Port -Action Allow | Out-Null
        Write-Host "  Opened port $($r.Port) ($($r.Name))"
    } else {
        Write-Host "  Rule '$($r.Name)' already exists – skipping"
    }
}

# ── Restart IIS ──────────────────────────────────────────────
Write-Host "`nRestarting IIS..."
iisreset /restart | Out-Null

Write-Host @"

=== IIS Setup Complete ===

Site root  : $sitePath
IIS Manager: Start > Windows Administrative Tools > Internet Information Services (IIS) Manager
HTTP test  : http://localhost/   (or http://<VM-IP>/ from host)

Next: run post-install-hardening.ps1 to tighten OS & IIS security.
"@ -ForegroundColor Green
