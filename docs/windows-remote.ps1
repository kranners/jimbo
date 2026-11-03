# Lets butler on spike see and drive the Windows install of the jimbo PC, the way modules/butler-access does for the
# Macs and the PC's NixOS install. Windows is not managed by Nix, so Aaron runs this by hand, once, in an
# administrator PowerShell, after setting up OpenSSH Server himself:
#
#   powershell -ExecutionPolicy Bypass -File windows-remote.ps1
#
# It is safe to run again: it keeps TightVNC and its password unless the password file is gone or -NewPassword is given,
# and writes that password into TightVNC's registry each time, so a run repairs a server that lost it.
#
# What it does:
#   1. installs TightVNC Server 2.8.90 (the GPL edition) from tightvnc.com, pinned by SHA-256, as a service that
#      listens on 127.0.0.1:5900 alone, with an 8-character random VNC password;
#   2. writes that password to C:\ProgramData\butler-access\vnc-password, readable by Administrators and SYSTEM
#      alone, which butler's `mac` tool reads over ssh, as it reads ~/.local/state/butler-access/vnc-password on a Mac;
#   3. blocks inbound TCP 5900 and 5800 in Windows Firewall, so nothing but ssh's tunnel ever reaches VNC;
#   4. registers the scheduled task butler-desktop, which lists the windows on Aaron's own desktop, since an ssh
#      session runs in session 0 and sees none of them.
#
# butler installs a second task, butler-screenshot, from docs/windows-screenshot.ps1 itself over ssh when it first looks.
#
# Checked from a cloud session on 3 Nov 2026, without a Windows machine to run it on:
#   - the installer URL and its SHA-256, 9693cb4c...170ce, from the file tightvnc.com serves;
#   - the MSI's property names (SET_*/VALUE_OF_*, SERVER_REGISTER_AS_SERVICE, ADDLOCAL=Server), read from the MSI itself;
#   - that this file parses in PowerShell 7.
# Verified on jimbo's Windows install on 3 Nov 2026:
#   - the service is named tvnserver and listens on 127.0.0.1:5900 alone;
#   - the MSI's silent install wrote no Password value at all, so TightVNC refused every login with "Server is not
#     configured properly"; the script therefore writes Password and ControlPassword itself, DES-encrypted as
#     TightVNC stores them, and the hand-written value made screenshots and typing work.
# Not verified, so check it in the output:
#   - that the scheduled task runs on Aaron's desktop without flashing a window (it runs hidden through wscript).
#
# Driving it, as found on jimbo:
#   - after the screen has been blank or asleep, the first capture can be black until a key or mouse move wakes it;
#   - Start menu search did not open apps by `key super` and typing, while Win+R did: `key super-r`, type, `key enter`.

param(
  [string] $User = $env:USERNAME,
  [switch] $NewPassword
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$version = '2.8.90'
$url = "https://www.tightvnc.com/download/$version/tightvnc-$version-gpl-setup-64bit.msi"
$sha256 = '9693CB4CDC2E7E482E8E3F5890415B57EF87DE3369FA5C337DB516218A1170CE'
$dir = 'C:\ProgramData\butler-access'
$passwordFile = Join-Path $dir 'vnc-password'
$serverKey = 'HKLM:\SOFTWARE\TightVNC\Server'

function Step($text) { Write-Host "==> $text" -ForegroundColor Cyan }

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run this in an administrator PowerShell.'
}

Step "making $dir, readable by Administrators and SYSTEM alone"
New-Item -ItemType Directory -Force $dir | Out-Null
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetAccessRuleProtection($true, $false)
foreach ($who in 'BUILTIN\Administrators', 'NT AUTHORITY\SYSTEM') {
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule(
          $who, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
}
Set-Acl $dir $acl

function New-Password {
  $alphabet = [char[]] 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
  $bytes = New-Object byte[] 8
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
  -join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })
}

# TightVNC stores a password as the first 8 bytes of it, zero-padded, DES-encrypted in ECB mode with VNC's fixed key
# (23,82,107,6,35,78,88,7 with each byte's bits reversed), as a REG_BINARY value.
function ConvertTo-VncPassword([string] $text) {
  $plain = New-Object byte[] 8
  $ascii = [Text.Encoding]::ASCII.GetBytes($text)
  [Array]::Copy($ascii, $plain, [Math]::Min(8, $ascii.Length))
  $key = [byte[]] (23, 82, 107, 6, 35, 78, 88, 7 | ForEach-Object {
      $b = $_; $r = 0
      for ($i = 0; $i -lt 8; $i++) { $r = ($r -shl 1) -bor (($b -shr $i) -band 1) }
      [byte] $r
    })
  $des = [Security.Cryptography.DES]::Create()
  $des.Mode = [Security.Cryptography.CipherMode]::ECB
  $des.Padding = [Security.Cryptography.PaddingMode]::None
  $des.Key = $key
  $encrypted = $des.CreateEncryptor().TransformFinalBlock($plain, 0, 8)
  $des.Dispose()
  , $encrypted
}

$installed = Get-Service tvnserver -ErrorAction SilentlyContinue
# The password file is butler's copy and the source of truth: a run without -NewPassword writes it back into TightVNC's
# registry, so only a new password, or a lost copy, means installing TightVNC afresh.
$fresh = -not $installed -or $NewPassword -or -not (Test-Path $passwordFile)
$password = if ($fresh) { New-Password } else { (Get-Content -Raw $passwordFile).Trim() }
# The control password guards TightVNC's own settings window, so a program on the desktop cannot reopen it to the network.
# Nobody needs to know it, so it is not kept, and an existing one is replaced only on a fresh install or when missing.
$controlPassword = New-Password

if ($installed -and $fresh) {
  Step 'uninstalling TightVNC, to install it again with a new password'
  Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall' |
    Get-ItemProperty | Where-Object { $_.DisplayName -like 'TightVNC*' -and $_.PSChildName -like '{*}' } |
    ForEach-Object { Start-Process msiexec.exe -ArgumentList '/x', $_.PSChildName, '/quiet', '/norestart' -Wait }
}

if ($fresh) {
  Step "downloading TightVNC $version"
  $msi = Join-Path $env:TEMP "tightvnc-$version-gpl-setup-64bit.msi"
  Invoke-WebRequest -UseBasicParsing $url -OutFile $msi
  $actual = (Get-FileHash -Algorithm SHA256 $msi).Hash
  if ($actual -ne $sha256) { Remove-Item $msi; throw "TightVNC's installer has SHA-256 $actual, not $sha256; not installing it." }
  $signature = Get-AuthenticodeSignature $msi
  Write-Host "    signature: $($signature.Status), $($signature.SignerCertificate.Subject)"

  Step 'installing TightVNC Server as a service, on loopback alone'
  $arguments = @(
    '/i', "`"$msi`"", '/quiet', '/norestart',
    'ADDLOCAL=Server',
    'SERVER_REGISTER_AS_SERVICE=1',
    'SERVER_ADD_FIREWALL_EXCEPTION=0',
    'SERVER_ALLOW_SAS=1',
    'SET_USEVNCAUTHENTICATION=1', 'VALUE_OF_USEVNCAUTHENTICATION=1',
    'SET_PASSWORD=1', "VALUE_OF_PASSWORD=$password",
    'SET_USECONTROLAUTHENTICATION=1', 'VALUE_OF_USECONTROLAUTHENTICATION=1',
    'SET_CONTROLPASSWORD=1', "VALUE_OF_CONTROLPASSWORD=$controlPassword",
    'SET_LOOPBACKONLY=1', 'VALUE_OF_LOOPBACKONLY=1',
    'SET_ALLOWLOOPBACK=1', 'VALUE_OF_ALLOWLOOPBACK=1',
    'SET_ACCEPTHTTPCONNECTIONS=1', 'VALUE_OF_ACCEPTHTTPCONNECTIONS=0',
    'SET_ENABLEFILETRANSFERS=1', 'VALUE_OF_ENABLEFILETRANSFERS=0',
    'SET_REMOVEWALLPAPER=1', 'VALUE_OF_REMOVEWALLPAPER=0'
  )
  $install = Start-Process msiexec.exe -ArgumentList $arguments -Wait -PassThru
  Remove-Item $msi
  if ($install.ExitCode -notin 0, 3010) { throw "msiexec failed with exit code $($install.ExitCode)" }
} else {
  Step 'TightVNC is already installed; enforcing its loopback settings and its password from the password file'
}

# Written again whatever the MSI did, since these are what keep VNC off the network.
if (-not (Test-Path $serverKey)) { New-Item -Force $serverKey | Out-Null }
foreach ($setting in @{ LoopbackOnly = 1; AllowLoopback = 1; AcceptHttpConnections = 0; UseVncAuthentication = 1
    UseControlAuthentication = 1; EnableFileTransfers = 0 }.GetEnumerator()) {
  Set-ItemProperty $serverKey -Name $setting.Key -Value $setting.Value -Type DWord
}
# The MSI's silent install left no Password value on jimbo, so the passwords are written here rather than trusted to it.
Set-ItemProperty $serverKey -Name Password -Value (ConvertTo-VncPassword $password) -Type Binary
if ($fresh -or $null -eq (Get-ItemProperty $serverKey -Name ControlPassword -ErrorAction SilentlyContinue)) {
  Set-ItemProperty $serverKey -Name ControlPassword -Value (ConvertTo-VncPassword $controlPassword) -Type Binary
}
Set-Service tvnserver -StartupType Automatic
Restart-Service tvnserver

Step "writing the VNC password to $passwordFile"
[IO.File]::WriteAllText($passwordFile, $password)

Step 'blocking inbound VNC in Windows Firewall'
Get-NetFirewallRule -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -like '*TightVNC*' -and $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' } |
  Remove-NetFirewallRule
if (-not (Get-NetFirewallRule -Name butler-access-block-vnc -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -Name butler-access-block-vnc -DisplayName 'butler-access: block inbound VNC' `
    -Direction Inbound -Protocol TCP -LocalPort 5800, 5900 -Action Block -Profile Any | Out-Null
}

Step 'registering the butler-desktop task, which lists the windows on your desktop'
$lister = @'
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class ButlerWindows {
  public delegate bool EnumProc(IntPtr hwnd, IntPtr data);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc proc, IntPtr data);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern bool IsZoomed(IntPtr hwnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hwnd);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int length);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hwnd, int index);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attribute, out int value, int size);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@
[void][ButlerWindows]::SetProcessDPIAware()
function Describe($hwnd) {
  $text = New-Object Text.StringBuilder ([ButlerWindows]::GetWindowTextLength($hwnd) + 1)
  [void][ButlerWindows]::GetWindowText($hwnd, $text, $text.Capacity)
  $id = [uint32]0
  [void][ButlerWindows]::GetWindowThreadProcessId($hwnd, [ref]$id)
  $process = (Get-Process -Id $id -ErrorAction SilentlyContinue).ProcessName
  $rect = New-Object ButlerWindows+RECT
  [void][ButlerWindows]::GetWindowRect($hwnd, [ref]$rect)
  $state = if ([ButlerWindows]::IsIconic($hwnd)) { 'minimised' } elseif ([ButlerWindows]::IsZoomed($hwnd)) { 'maximised' } else { 'normal' }
  [pscustomobject]@{ Process = $process; State = $state; Title = $text.ToString()
    Place = "$($rect.Left),$($rect.Top) $($rect.Right - $rect.Left)x$($rect.Bottom - $rect.Top)" }
}
$found = New-Object Collections.ArrayList
[void][ButlerWindows]::EnumWindows({
    param($hwnd, $data)
    $cloaked = 0
    [void][ButlerWindows]::DwmGetWindowAttribute($hwnd, 14, [ref]$cloaked, 4)
    $tool = [ButlerWindows]::GetWindowLong($hwnd, -20) -band 0x80
    if ([ButlerWindows]::IsWindowVisible($hwnd) -and -not $cloaked -and -not $tool -and [ButlerWindows]::GetWindowTextLength($hwnd) -gt 0) {
      [void]$found.Add($hwnd)
    }
    $true
  }, [IntPtr]::Zero)
$front = Describe ([ButlerWindows]::GetForegroundWindow())
"front: $($front.Process), $($front.Title)"
$windows = $found | ForEach-Object { Describe $_ } | Where-Object { $_.Process -notin 'TextInputHost', 'ApplicationFrameHost' -or $_.Title }
"apps: $(($windows.Process | Select-Object -Unique) -join ', ')"
foreach ($screen in [System.Windows.Forms.Screen]::AllScreens) {
  $b = $screen.Bounds
  "screen: $($screen.DeviceName) $($b.Width)x$($b.Height) pixels at $($b.X),$($b.Y)$(if ($screen.Primary) { ', primary' })"
}
'windows, front to back, as process, state, x,y widthxheight in pixels, title:'
$windows | ForEach-Object { "  $($_.Process), $($_.State), $($_.Place), $($_.Title)" }
'@
Set-Content -Encoding UTF8 (Join-Path $dir 'desktop.ps1') $lister

$launcher = @'
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = "C:\ProgramData\butler-access"
shell.Run "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ""& '" & folder & "\desktop.ps1' *> '" & folder & "\desktop.out'""", 0, True
files.CreateTextFile(folder & "\desktop.done", True).Close
'@
Set-Content -Encoding ASCII (Join-Path $dir 'desktop.vbs') $launcher

$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //NoLogo `"$dir\desktop.vbs`""
$principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$User" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
  -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName butler-desktop -Action $action -Principal $principal -Settings $settings -Force | Out-Null

Step 'checking'
$sshd = Get-Service sshd -ErrorAction SilentlyContinue
Write-Host "    sshd: $(if ($sshd) { "$($sshd.Status), $($sshd.StartType)" } else { 'NOT INSTALLED' })"
$keys = 'C:\ProgramData\ssh\administrators_authorized_keys'
Write-Host "    butler's key in administrators_authorized_keys: $(if ((Test-Path $keys) -and (Select-String -Quiet 'butler@spike-macs' $keys)) { 'yes' } else { 'NO' })"
Write-Host "    tvnserver: $((Get-Service tvnserver).Status)"
$listeners = Get-NetTCPConnection -State Listen -LocalPort 5900 -ErrorAction SilentlyContinue
Write-Host "    VNC listens on: $(if ($listeners) { ($listeners.LocalAddress | Select-Object -Unique) -join ', ' } else { 'nothing yet' }) (should be 127.0.0.1 alone)"
Write-Host "    sleep and display timeouts on AC: $((powercfg /query SCHEME_CURRENT SUB_SLEEP STANDBYIDLE | Select-String 'Current AC').Line.Trim())"
Write-Host ''
Write-Host 'Done. Ask butler for `mac hosts`; it should say jimbo (Windows) is up.' -ForegroundColor Green
