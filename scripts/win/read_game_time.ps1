# Read FM21's live game-time fingerprint from the authoritative GAME object.
#
# The root is restart-safe for this FM21 build:
#   fm.exe+0x7002EC8 -> GAME object
# The object was identified with MSVC RTTI and verified against visible time
# movement on 4-5 Oct 2020. Nothing here writes to process memory.
#
#   powershell -File read_game_time.ps1
#   powershell -File read_game_time.ps1 -AsJson
param(
  [string]$ProcessName = 'fm',
  [switch]$AsJson
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BielsaGameTime {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, int n, out IntPtr got);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
"@

$p = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $p) { Write-Error "process '$ProcessName' not running"; exit 1 }
$mod = $p.Modules | Where-Object { $_.ModuleName -eq 'fm.exe' } | Select-Object -First 1
if (-not $mod) { Write-Error 'fm.exe module not found'; exit 1 }
$base = $mod.BaseAddress.ToInt64()
$globalOffset = 0x7002EC8L
$global = $base + $globalOffset
$h = [BielsaGameTime]::OpenProcess(0x0010 -bor 0x0400, $false, $p.Id)
if ($h -eq [IntPtr]::Zero) { Write-Error 'OpenProcess failed'; exit 1 }

function Read-Exact([long]$addr, [int]$n) {
  $b = New-Object byte[] $n
  $got = [IntPtr]::Zero
  $ok = [BielsaGameTime]::ReadProcessMemory($h, [IntPtr]$addr, $b, $n, [ref]$got)
  if (-not $ok -or [int]$got -ne $n) { throw ('read failed at 0x{0:X}' -f $addr) }
  return ,$b
}
function Read-U64([long]$addr) { [BitConverter]::ToUInt64((Read-Exact $addr 8), 0) }
function Read-U32([long]$addr) { [BitConverter]::ToUInt32((Read-Exact $addr 4), 0) }

try {
  $game = [long](Read-U64 $global)
  if ($game -eq 0) { throw 'GAME global is null' }
  $vtable = [long](Read-U64 $game)
  $vtableOffset = $vtable - $base

  # These three vtables all resolve through RTTI to .?AVGAME@@ in this build.
  # The global has so far pointed at the +0x6531AA0 variant; accepting all three
  # keeps the check semantic without overfitting one observed subobject.
  $gameVtables = @(0x65318C0L, 0x6531AA0L, 0x6531B98L)
  if ($gameVtables -notcontains $vtableOffset) {
    throw ('unexpected GAME vtable fm.exe+0x{0:X}' -f $vtableOffset)
  }
  $a = Read-U32 ($game + 0x90)
  $b = Read-U32 ($game + 0x94)
  $c = Read-U32 ($game + 0x98)
  $fingerprint = '{0:X8}:{1:X8}:{2:X8}' -f $a, $b, $c

  $out = [ordered]@{
    process_id = $p.Id
    module_base = ('0x{0:X}' -f $base)
    global = ('fm.exe+0x{0:X}' -f $globalOffset)
    game = ('0x{0:X}' -f $game)
    vtable = ('fm.exe+0x{0:X}' -f $vtableOffset)
    clock_a = ('0x{0:X8}' -f $a)
    clock_b = ('0x{0:X8}' -f $b)
    clock_c = ('0x{0:X8}' -f $c)
    fingerprint = $fingerprint
  }

  if ($AsJson) { $out | ConvertTo-Json -Compress }
  else { [pscustomobject]$out | Format-List }
} catch {
  Write-Error $_.Exception.Message
  exit 1
} finally {
  [BielsaGameTime]::CloseHandle($h) | Out-Null
}
