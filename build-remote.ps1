# Build os-mihomo package on OPNsense via SSH
$fw = "100.64.13.1"
$user = "root"
$repoUrl = "https://github.com/fedotdev/os-mihomo-v2"
$branch = "phase-2-transactional-config"

if (-not $env:FW_ROOT_PASSWORD) {
    Write-Host "Error: Set FW_ROOT_PASSWORD environment variable"
    exit 1
}

Write-Host "Cloning repo on firewall..."
$cmd = @"
cd /root && \
rm -rf os-mihomo-v2 && \
git clone --depth 1 --branch $branch $repoUrl && \
cd os-mihomo-v2/src/os-mihomo && \
sh build.sh && \
ls -lh dist/os-mihomo.pkg
"@

$password = $env:FW_ROOT_PASSWORD
$sshPass = "sshpass -p '$password'"
$sshCmd = "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL ${user}@${fw}"

# Note: sshpass not on Windows, need workaround
Write-Host @"

Run this manually in WSL or Git Bash:
-----------------------------------------
$cmd
-----------------------------------------
Or via SSH client with password prompt.
"@
