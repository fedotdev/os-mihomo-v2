@echo off
REM SSH wrapper for OPNsense 100.64.13.1 (restricted shell workaround)
REM Password from environment variable FW_ROOT_PASSWORD
if not defined FW_ROOT_PASSWORD (
    echo Error: FW_ROOT_PASSWORD not set
    exit /b 1
)
echo %FW_ROOT_PASSWORD%| ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL root@100.64.13.1 "/bin/sh -c '%*'"
