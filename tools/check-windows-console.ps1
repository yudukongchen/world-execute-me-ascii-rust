# Run in a separate PowerShell process: this probe attaches to a real console.
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ConsoleProbe {
 [DllImport("kernel32.dll")] public static extern bool FreeConsole();
 [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint pid);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr CreateFileW(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
 [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr handle, out uint mode);
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode)] public static extern bool ReadConsoleOutputCharacterW(IntPtr handle, StringBuilder text, uint length, uint coordinate, out uint read);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr handle);
}
'@
$root = Split-Path $PSScriptRoot
$player = Start-Process -FilePath "$root\target\release\world-execute-me-rust.exe" -ArgumentList '--paused' -WorkingDirectory $root -WindowStyle Normal -PassThru
try {
 Start-Sleep -Seconds 2
 [ConsoleProbe]::FreeConsole() | Out-Null
 if (-not [ConsoleProbe]::AttachConsole($player.Id)) { throw 'Cannot attach to player console' }
 $handle = [ConsoleProbe]::CreateFileW('CONOUT$', 2147483648, 3, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
 [uint32]$mode = 0
 if (-not [ConsoleProbe]::GetConsoleMode($handle, [ref]$mode)) { throw 'Cannot read console mode' }
 $screen = [System.Text.StringBuilder]::new(16000)
 [uint32]$read = 0
 if (-not [ConsoleProbe]::ReadConsoleOutputCharacterW($handle, $screen, 16000, 0, [ref]$read)) { throw 'Cannot read console text' }
 $result = [ordered]@{ virtualTerminal = (($mode -band 4) -ne 0); literalAnsi = ($screen.ToString() -match '\[\d+(;\d+)*[mH]'); consoleMode = $mode }
 $result | ConvertTo-Json | Set-Content "$root\target\console-probe.json"
 [ConsoleProbe]::CloseHandle($handle) | Out-Null
 [ConsoleProbe]::FreeConsole() | Out-Null
 if (-not $result.virtualTerminal -or $result.literalAnsi) { exit 1 }
} catch {
 $_ | Out-String | Set-Content "$root\target\console-probe-error.txt"
 exit 2
} finally {
 if (-not $player.HasExited) { Stop-Process -Id $player.Id }
}
