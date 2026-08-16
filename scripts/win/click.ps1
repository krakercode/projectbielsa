# Synthetic mouse input for driving FM's UI from a script.
#
# WHY THIS EXISTS
# Phase 2's write layer is being built on UI simulation rather than memory writes
# (see docs/session-log/2026-08-16-phase2-lineup-read.md). That decision only pays
# off if the clicking can be driven by a SCRIPT -- the eval has to run many
# decision points unattended, so an agent-in-the-loop clicking tool is not enough.
# This is the input primitive the write layer sits on.
#
# COORDINATES ARE REAL SCREEN PIXELS.
# Note the agent's own screenshots are downscaled: 1456x819 for this 1920x1080
# display. To convert a coordinate read off one of those screenshots, multiply by
# 1920/1456 = 1.3187. Pass -FromScreenshot to have this script do that for you,
# which keeps the conversion in one place instead of scattered through callers.
#
#   powershell -File click.ps1 -X 1411 -Y 363
#   powershell -File click.ps1 -X 1070 -Y 275 -FromScreenshot
#   powershell -File click.ps1 -X 1070 -Y 275 -FromScreenshot -MoveOnly
#
# Prints the resolved screen coordinate so callers can verify the mapping.

param(
  [Parameter(Mandatory = $true)][int]$X,
  [Parameter(Mandatory = $true)][int]$Y,
  [int]$ToX = -1,
  [int]$ToY = -1,
  [switch]$Drag,
  [switch]$FromScreenshot,
  [switch]$MoveOnly,
  [int]$SettleMs = 120
)

# -Drag exists because the swap dropdown's candidate ORDER is not stable -- the
# same player appeared 2nd in one opening and 4th in another -- so clicking a row
# by index cannot be made reliable. Drag-and-drop has fixed endpoints at both ends
# (a known list row, a known pitch slot), which is deterministic.

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BielsaInput {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);

  [StructLayout(LayoutKind.Sequential)]
  public struct MOUSEINPUT { public int dx; public int dy; public uint mouseData;
    public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
  [StructLayout(LayoutKind.Sequential)]
  public struct INPUT { public uint type; public MOUSEINPUT mi; }

  [DllImport("user32.dll", SetLastError=true)]
  public static extern uint SendInput(uint n, INPUT[] inputs, int size);

  public const uint MOUSEEVENTF_MOVE        = 0x0001;
  public const uint MOUSEEVENTF_ABSOLUTE    = 0x8000;
  public const uint MOUSEEVENTF_LEFTDOWN    = 0x0002;
  public const uint MOUSEEVENTF_LEFTUP      = 0x0004;

  // Absolute SendInput coordinates are normalised to 0..65535 across the screen,
  // NOT pixels -- getting this wrong sends the pointer to the wrong place.
  public static void MoveAbs(int x, int y) {
    int w = GetSystemMetrics(0), h = GetSystemMetrics(1);
    INPUT[] inp = new INPUT[1];
    inp[0].type = 0;
    inp[0].mi.dx = (int)((x * 65535.0) / (w - 1));
    inp[0].mi.dy = (int)((y * 65535.0) / (h - 1));
    inp[0].mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE;
    SendInput(1, inp, Marshal.SizeOf(typeof(INPUT)));
  }

  public static void LeftClick() {
    INPUT[] inp = new INPUT[2];
    inp[0].type = 0; inp[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    inp[1].type = 0; inp[1].mi.dwFlags = MOUSEEVENTF_LEFTUP;
    SendInput(2, inp, Marshal.SizeOf(typeof(INPUT)));
  }

  public static void LeftDown() {
    INPUT[] inp = new INPUT[1];
    inp[0].type = 0; inp[0].mi.dwFlags = MOUSEEVENTF_LEFTDOWN;
    SendInput(1, inp, Marshal.SizeOf(typeof(INPUT)));
  }

  public static void LeftUp() {
    INPUT[] inp = new INPUT[1];
    inp[0].type = 0; inp[0].mi.dwFlags = MOUSEEVENTF_LEFTUP;
    SendInput(1, inp, Marshal.SizeOf(typeof(INPUT)));
  }
}
"@

$scale = if ($FromScreenshot) { [BielsaInput]::GetSystemMetrics(0) / 1456.0 } else { 1.0 }
$sx = [int][math]::Round($X * $scale)
$sy = [int][math]::Round($Y * $scale)

if ($Drag) {
  if ($ToX -lt 0 -or $ToY -lt 0) { Write-Error "-Drag requires -ToX and -ToY"; exit 1 }
  $ex = [int][math]::Round($ToX * $scale)
  $ey = [int][math]::Round($ToY * $scale)

  # Move, press, then creep toward the target in steps. A single jump often reads
  # as a click rather than a drag because the app never sees intermediate motion.
  [BielsaInput]::MoveAbs($sx, $sy); Start-Sleep -Milliseconds $SettleMs
  [BielsaInput]::LeftDown();        Start-Sleep -Milliseconds $SettleMs
  $steps = 24
  for ($i = 1; $i -le $steps; $i++) {
    $ix = [int]($sx + (($ex - $sx) * $i / $steps))
    $iy = [int]($sy + (($ey - $sy) * $i / $steps))
    [BielsaInput]::MoveAbs($ix, $iy)
    Start-Sleep -Milliseconds 18
  }
  Start-Sleep -Milliseconds $SettleMs
  [BielsaInput]::LeftUp()
  Start-Sleep -Milliseconds $SettleMs
  "screen {0}x{1} -> dragged ({2},{3}) to ({4},{5})" -f `
    [BielsaInput]::GetSystemMetrics(0), [BielsaInput]::GetSystemMetrics(1), $sx, $sy, $ex, $ey
  exit 0
}

[BielsaInput]::MoveAbs($sx, $sy)
Start-Sleep -Milliseconds $SettleMs

if (-not $MoveOnly) {
  [BielsaInput]::LeftClick()
  Start-Sleep -Milliseconds $SettleMs
}

"screen {0}x{1} -> clicked ({2},{3}){4}" -f `
  [BielsaInput]::GetSystemMetrics(0), [BielsaInput]::GetSystemMetrics(1), `
  $sx, $sy, $(if ($MoveOnly) { " [move only]" } else { "" })
