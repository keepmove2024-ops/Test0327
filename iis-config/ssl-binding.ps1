# ============================================================
# ssl-binding.ps1
# Run INSIDE the VM (elevated PowerShell) AFTER setup-iis.ps1.
# Adds HTTPS (port 443) to IIS using either:
#   (a) A self-signed certificate (dev/test), or
#   (b) An existing PFX certificate (production).
# ============================================================

#Requires -RunAsAdministrator
param (
    [ValidateSet("SelfSigned","PFX")]
    [string]$Mode         = "SelfSigned",

    [string]$PfxPath      = "",          # Required when Mode=PFX
    [string]$PfxPassword  = "",          # Required when Mode=PFX
    [string]$SiteName     = "Default Web Site",
    [string]$Hostname     = "",          # Leave blank for IP-based binding
    [int]   $Port         = 443,
    [string]$CertSubject  = "WinServer2025-IIS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module WebAdministration

# ── 1. Obtain certificate ────────────────────────────────────
if ($Mode -eq "SelfSigned") {
    Write-Host "Creating self-signed certificate for '$CertSubject'..."
    $cert = New-SelfSignedCertificate `
        -DnsName        $CertSubject `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter       (Get-Date).AddYears(2) `
        -KeyAlgorithm   RSA `
        -KeyLength      2048 `
        -HashAlgorithm  SHA256 `
        -KeyUsage       DigitalSignature, KeyEncipherment `
        -TextExtension  @("2.5.29.37={text}1.3.6.1.5.5.7.3.1")

    Write-Host "  Certificate thumbprint: $($cert.Thumbprint)"
    $thumbprint = $cert.Thumbprint

} elseif ($Mode -eq "PFX") {
    if (-not (Test-Path $PfxPath)) { throw "PFX not found at '$PfxPath'" }
    Write-Host "Importing PFX from '$PfxPath'..."
    $secPwd = ConvertTo-SecureString $PfxPassword -AsPlainText -Force
    $cert   = Import-PfxCertificate -FilePath $PfxPath -CertStoreLocation "Cert:\LocalMachine\My" -Password $secPwd
    Write-Host "  Certificate thumbprint: $($cert.Thumbprint)"
    $thumbprint = $cert.Thumbprint
}

# ── 2. Create HTTPS binding in IIS ──────────────────────────
Write-Host "Adding HTTPS binding (port $Port) to '$SiteName'..."

$bindingInfo = "*:${Port}:${Hostname}"
$existing    = Get-WebBinding -Name $SiteName -Protocol "https" -Port $Port -ErrorAction SilentlyContinue

if ($null -eq $existing) {
    New-WebBinding -Name $SiteName -Protocol "https" -Port $Port -HostHeader $Hostname -SslFlags 0
    Write-Host "  Binding created: https $bindingInfo"
} else {
    Write-Host "  Binding already exists – updating certificate."
}

# ── 3. Associate certificate with binding ───────────────────
Write-Host "Binding certificate to port $Port..."

$sslPath = "IIS:\SslBindings\0.0.0.0!${Port}"
if (Test-Path $sslPath) { Remove-Item $sslPath -Force }

Get-Item "Cert:\LocalMachine\My\$thumbprint" | New-Item $sslPath | Out-Null

# ── 4. Optional: HTTP → HTTPS redirect ──────────────────────
Write-Host "Enabling HTTP → HTTPS redirect..."

$webConfigPath = (Get-WebFilePath "IIS:\Sites\$SiteName").FullName
[xml]$wc = Get-Content $webConfigPath

# Inject/update rewrite rules (requires URL Rewrite module)
$rewriteRule = @"

  <system.webServer>
    <rewrite>
      <rules>
        <rule name="HTTP to HTTPS" stopProcessing="true">
          <match url="(.*)" />
          <conditions>
            <add input="{HTTPS}" pattern="^OFF$" />
          </conditions>
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
        </rule>
      </rules>
    </rewrite>
  </system.webServer>

"@

Write-Host "  Note: HTTP→HTTPS redirect requires URL Rewrite module."
Write-Host "  Download: https://www.iis.net/downloads/microsoft/url-rewrite"

# ── 5. Firewall ──────────────────────────────────────────────
if (-not (Get-NetFirewallRule -DisplayName "IIS HTTPS" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "IIS HTTPS" -Direction Inbound `
        -Protocol TCP -LocalPort 443 -Action Allow | Out-Null
    Write-Host "Firewall rule for port 443 created."
}

Write-Host @"

=== SSL/TLS binding complete ===
URL: https://localhost/
Thumbprint: $thumbprint

For a trusted certificate in production use:
  - Let's Encrypt (win-acme: https://www.win-acme.com/)
  - Your organization's PKI / purchased certificate
"@ -ForegroundColor Green
