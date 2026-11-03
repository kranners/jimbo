# Lets spike's remote-desk gateway, Aaron's iPad remote desktop, reach the jimbo PC's Windows install the way
# modules/butler-access lets it reach the Macs and the PC's NixOS: one line in administrators_authorized_keys for the
# gateway's own key, accepted only from spike's WireGuard address 10.100.0.1, allowed to forward to TightVNC on
# 127.0.0.1:5900 alone, and whose forced command only prints whether the screen is locked, so the key runs nothing else.
# Run it by hand, once, in an administrator PowerShell, after docs/windows-remote.ps1, with the key that
# `sudo remote-desk key` prints on spike:
#
#   powershell -ExecutionPolicy Bypass -File windows-remote-desk.ps1 -PublicKey 'ssh-ed25519 AAAA... remote-desk@spike'
#
# Run it again with a new key to replace the old one, or with -Remove to withdraw the gateway from this PC.
# Not verified on Windows: written from a cloud session on 3 Nov 2026 without a Windows machine, so check that the
# gateway's launcher shows the PC as up and unlocked once it has run.

param(
  [string] $PublicKey,
  [switch] $Remove
)

$ErrorActionPreference = 'Stop'
$keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
$comment = 'remote-desk@spike'

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this in an administrator PowerShell.'
}
if (-not $Remove -and $PublicKey -notmatch '^ssh-ed25519 [A-Za-z0-9+/=]+( \S+)?$') {
  throw 'Give the key from `sudo remote-desk key` on spike as -PublicKey, or -Remove.'
}
if (-not (Test-Path $keys)) { throw "$keys is missing: set up OpenSSH Server and butler's key first." }

$status = @'
$user = (Get-CimInstance Win32_ComputerSystem).UserName
if (-not $user) { 'at the login screen' } elseif (Get-Process LogonUI -ErrorAction SilentlyContinue) { 'locked' } else { 'unlocked' }
'@
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($status))

# Rewriting the file in place keeps its ACL, which sshd insists gives only Administrators and SYSTEM access.
$lines = @(Get-Content $keys | Where-Object { $_ -notmatch [regex]::Escape($comment) })
if (-not $Remove) {
  $key = ($PublicKey -split ' ')[0..1] -join ' '
  $lines += "from=`"10.100.0.1`",restrict,port-forwarding,permitopen=`"127.0.0.1:5900`",command=`"powershell.exe -NoProfile -NonInteractive -EncodedCommand $encoded`" $key $comment"
}
Set-Content -Path $keys -Value $lines -Encoding ascii

Write-Host "==> administrators_authorized_keys now has $(if ($Remove) { 'no' } else { 'the' }) remote-desk key"
Get-Content $keys | ForEach-Object { if ($_ -match [regex]::Escape($comment)) { '    ' + ($_ -replace 'EncodedCommand \S+', 'EncodedCommand ...') } }
