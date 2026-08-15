# Bring a window to the foreground, reliably.
#
# WHY THIS EXISTS
# Two gotchas cost real time in this project:
#   1. open_application spawns a NEW Cheat Engine rather than focusing the running
#      one, so it can never be used to switch to CE.
#   2. SetForegroundWindow ALONE silently fails much of the time -- Windows
#      refuses foreground changes from a process that does not own the current
#      foreground window. It returns without error and nothing moves, which then
#      shows up as a mystifying "the desktop shell is frontmost" click failure.
#
# The combination that actually works is AttachThreadInput to the current
# foreground thread, then ShowWindow + SetWindowPos(TOPMOST then NOTOPMOST) +
# BringWindowToTop + SetForegroundWindow, then verify by reading back the
# foreground PID. This script does that and prints the resulting PID so the
# caller can confirm rather than assume.
#
#   powershell -File focus.ps1 -Title "Lua Engine"
#   powershell -File focus.ps1 -ProcessId 22352
#   powershell -File focus.ps1 -ProcessName fm

param(
  [string]$Title = "",
  [int]$ProcessId = 0,
  [string]$ProcessName = ""
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BielsaFocus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  [DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string n);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool f);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
}
"@

$h = [IntPtr]::Zero
if ($Title)            { $h = [BielsaFocus]::FindWindow($null, $Title) }
if ($h -eq [IntPtr]::Zero -and $ProcessId)   { $p = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue;   if ($p) { $h = $p.MainWindowHandle } }
if ($h -eq [IntPtr]::Zero -and $ProcessName) { $p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1; if ($p) { $h = $p.MainWindowHandle } }
if ($h -eq [IntPtr]::Zero) { Write-Error "no window found (Title='$Title' ProcessId=$ProcessId ProcessName='$ProcessName')"; exit 1 }

$fg  = [BielsaFocus]::GetForegroundWindow()
$tid = [BielsaFocus]::GetWindowThreadProcessId($fg, [ref]([uint32]0))
$me  = [BielsaFocus]::GetCurrentThreadId()

[BielsaFocus]::AttachThreadInput($tid, $me, $true) | Out-Null
[BielsaFocus]::ShowWindow($h, 9) | Out-Null                                  # SW_RESTORE
[BielsaFocus]::SetWindowPos($h, [IntPtr]::new(-1), 0,0,0,0, 3) | Out-Null    # HWND_TOPMOST
[BielsaFocus]::SetWindowPos($h, [IntPtr]::new(-2), 0,0,0,0, 3) | Out-Null    # HWND_NOTOPMOST
[BielsaFocus]::BringWindowToTop($h) | Out-Null
[BielsaFocus]::SetForegroundWindow($h) | Out-Null
[BielsaFocus]::AttachThreadInput($tid, $me, $false) | Out-Null

Start-Sleep -Milliseconds 400
$now = 0
[BielsaFocus]::GetWindowThreadProcessId([BielsaFocus]::GetForegroundWindow(), [ref]$now) | Out-Null
"foreground pid = $now"
