# ============================================================
# setup-virtualbox-vm.ps1
# Run this on the HOST machine to create a Windows Server 2025
# VM in Oracle VirtualBox and boot it ready for IIS setup.
#
# Prerequisites (host):
#   - Oracle VirtualBox 7.x installed
#   - VBoxManage in PATH
#   - Windows Server 2025 ISO downloaded
# ============================================================

param (
    [string]$VMName        = "WinServer2025-IIS",
    [string]$ISOPath       = "C:\ISOs\WinServer2025.iso",
    [string]$VDIDir        = "$env:USERPROFILE\VirtualBox VMs",
    [int]   $MemoryMB      = 4096,
    [int]   $CPUs          = 2,
    [int]   $DiskGB        = 60,
    [int]   $HostOnlyPort  = 8080     # Port forwarded to VM port 80
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Helper ──────────────────────────────────────────────────
function VBox { VBoxManage @args }

Write-Host "=== Oracle VirtualBox – Windows Server 2025 IIS VM Setup ===" -ForegroundColor Cyan

# ── 1. Validate ISO ─────────────────────────────────────────
if (-not (Test-Path $ISOPath)) {
    Write-Error "ISO not found at '$ISOPath'. Update -ISOPath and retry."
    exit 1
}

# ── 2. Create VM ────────────────────────────────────────────
Write-Host "`n[1/8] Creating VM '$VMName'..."
VBox createvm --name $VMName --ostype "Windows2022_64" --register

# ── 3. Hardware settings ────────────────────────────────────
Write-Host "[2/8] Configuring hardware ($MemoryMB MB RAM, $CPUs vCPUs)..."
VBox modifyvm $VMName `
    --memory        $MemoryMB `
    --cpus          $CPUs `
    --vram          128 `
    --graphicscontroller vboxsvga `
    --firmware      efi `
    --boot1         dvd `
    --boot2         disk `
    --boot3         none `
    --clipboard-mode bidirectional `
    --draganddrop   bidirectional

# ── 4. Storage controller ────────────────────────────────────
Write-Host "[3/8] Adding storage controllers..."
VBox storagectl $VMName --name "SATA Controller" --add sata --controller IntelAhci --portcount 2
VBox storagectl $VMName --name "IDE Controller"  --add ide

# ── 5. Virtual hard disk ─────────────────────────────────────
$VDIPath = "$VDIDir\$VMName\$VMName.vdi"
$DiskMB  = $DiskGB * 1024
Write-Host "[4/8] Creating ${DiskGB}GB dynamic VDI at '$VDIPath'..."
New-Item -ItemType Directory -Force -Path "$VDIDir\$VMName" | Out-Null
VBox createmedium disk --filename $VDIPath --size $DiskMB --format VDI --variant Standard

VBox storageattach $VMName --storagectl "SATA Controller" --port 0 --device 0 --type hdd    --medium $VDIPath
VBox storageattach $VMName --storagectl "IDE Controller"  --port 1 --device 0 --type dvddrive --medium $ISOPath

# ── 6. Network ───────────────────────────────────────────────
Write-Host "[5/8] Configuring network (NAT + port forwarding HTTP/RDP)..."
VBox modifyvm $VMName --nic1 nat

# Forward host:$HostOnlyPort → guest:80  (IIS HTTP)
VBox modifyvm $VMName --natpf1 "IIS-HTTP,tcp,,$HostOnlyPort,,80"
# Forward host:33389 → guest:3389 (RDP)
VBox modifyvm $VMName --natpf1 "RDP,tcp,,33389,,3389"

# ── 7. Performance tweaks ────────────────────────────────────
Write-Host "[6/8] Applying performance settings..."
VBox modifyvm $VMName `
    --nested-hw-virt on `
    --paravirtprovider hyperv `
    --hwvirtex          on `
    --vtxvpid           on `
    --largepages        on

# ── 8. Guest Additions ISO (attach for later install) ────────
$GAIso = "$env:ProgramFiles\Oracle\VirtualBox\VBoxGuestAdditions.iso"
if (Test-Path $GAIso) {
    Write-Host "[7/8] Attaching Guest Additions ISO..."
    VBox storageattach $VMName --storagectl "SATA Controller" --port 1 --device 0 --type dvddrive --medium $GAIso
} else {
    Write-Warning "[7/8] Guest Additions ISO not found – skipping."
}

# ── 9. Start VM ──────────────────────────────────────────────
Write-Host "[8/8] Starting VM..."
VBox startvm $VMName --type gui

Write-Host @"

=== VM '$VMName' is booting ===

Next steps inside the VM:
  1. Complete Windows Server 2025 installation (choose 'Desktop Experience').
  2. Set Administrator password.
  3. Copy setup-iis.ps1 into the VM (drag-drop or shared folder).
  4. Run setup-iis.ps1 in an elevated PowerShell session.

IIS will be reachable at:  http://localhost:$HostOnlyPort
RDP available on host at:  localhost:33389
"@ -ForegroundColor Green
