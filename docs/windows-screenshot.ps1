# Installs the scheduled task butler-screenshot on the Windows install of the jimbo PC, which saves a downscaled
# screenshot of Aaron's desktop for butler's `mac jimbo look`, since a whole 5120x1440 frame in raw VNC pixels, 29 MB,
# took longer to cross ssh and WireGuard than any look should.
#
# butler's `mac` tool runs this itself over ssh at the start of each screen session, so nothing needs doing by hand,
# but Aaron can also run it in an administrator PowerShell, after docs/windows-remote.ps1:
#
#   powershell -ExecutionPolicy Bypass -File windows-screenshot.ps1
#
# It is safe to run again: it rewrites its files and the task only when they differ from these, and prints what it did.
#
# Each look writes the wanted size to shot.request and runs the task, which runs shot.ps1 hidden on Aaron's own
# desktop, since an ssh session runs in session 0 and sees none of it: it captures the whole virtual screen,
# DPI-aware so the pixels are real ones, scales it to that size and saves shot.png, then writes shot.done.

param(
  [string] $User = $env:USERNAME
)

$ErrorActionPreference = 'Stop'
$dir = 'C:\ProgramData\butler-access'
if (-not (Test-Path $dir)) { throw "$dir is missing; run docs/windows-remote.ps1 first." }

$shot = @'
$ErrorActionPreference = 'Stop'
$dir = 'C:\ProgramData\butler-access'
try {
  Add-Type -AssemblyName System.Drawing, System.Windows.Forms
  # Compiled once, since compiling C# on every look costs a second.
  $dll = Join-Path $dir 'ButlerDpi.dll'
  if (-not (Test-Path $dll)) {
    Add-Type -OutputAssembly $dll -OutputType Library -TypeDefinition 'using System.Runtime.InteropServices; public static class ButlerDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }'
  }
  Add-Type -Path $dll
  [void][ButlerDpi]::SetProcessDPIAware()
  $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
  $size = (Get-Content -Raw (Join-Path $dir 'shot.request')).Trim() -split '\s+'
  $width = [int]$size[0]
  $height = [int]$size[1]
  if ($width -le 0 -or $height -le 0) { $width = $bounds.Width; $height = $bounds.Height }
  $full = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [System.Drawing.Graphics]::FromImage($full)
  $graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $full.Size)
  $graphics.Dispose()
  $small = New-Object System.Drawing.Bitmap $width, $height
  $scaler = [System.Drawing.Graphics]::FromImage($small)
  $scaler.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $scaler.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $scaler.DrawImage($full, 0, 0, $width, $height)
  $scaler.Dispose()
  $full.Dispose()
  $small.Save((Join-Path $dir 'shot.png'), [System.Drawing.Imaging.ImageFormat]::Png)
  $small.Dispose()
  "ok $($bounds.Width) $($bounds.Height)"
} catch {
  "error $($_.Exception.Message)"
}
'@

$launcher = @'
Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
folder = "C:\ProgramData\butler-access"
shell.Run "powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ""& '" & folder & "\shot.ps1' *> '" & folder & "\shot.out'""", 0, True
files.CreateTextFile(folder & "\shot.done", True).Close
'@
$launcher = $launcher -replace "`r?`n", "`r`n"

$changed = $false
function Put($name, $text, $encoding) {
  $path = Join-Path $dir $name
  if ((Test-Path $path) -and ((Get-Content -Raw $path) -ceq $text)) { return }
  Set-Content -NoNewline -Encoding $encoding $path $text
  $script:changed = $true
  "wrote $path"
}
Put 'shot.ps1' $shot UTF8
Put 'shot.vbs' $launcher ASCII
if ($changed) { Remove-Item (Join-Path $dir 'ButlerDpi.dll') -ErrorAction SilentlyContinue }

& schtasks.exe /query /tn butler-screenshot 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0 -or $changed) {
  $action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //NoLogo `"$dir\shot.vbs`""
  $principal = New-ScheduledTaskPrincipal -UserId "$env:COMPUTERNAME\$User" -LogonType Interactive -RunLevel Highest
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew
  Register-ScheduledTask -TaskName butler-screenshot -Action $action -Principal $principal -Settings $settings -Force | Out-Null
  'registered the butler-screenshot task'
}
'butler-screenshot is ready'
exit 0
