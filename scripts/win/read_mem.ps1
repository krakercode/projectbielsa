# Read fm.exe memory directly via ReadProcessMemory, without Cheat Engine.
#
# WHY THIS EXISTS
# CE's Lua Engine is single-threaded: while a long AOBScan runs, no other script
# can execute, and there is no way to interrupt one from the GUI. That blocked a
# session mid-investigation. Killing CE would have freed it but would also have
# destroyed a scan result worth keeping (a 5,081-address found-list) -- and none
# of that is necessary, because reading another process's memory needs nothing
# from CE at all.
#
# It is also useful on its own terms: address dumps no longer require driving the
# CE GUI over screenshots, which is the slowest part of this project's loop.
#
# NOTE: this is READ-ONLY by design. It requests PROCESS_VM_READ only, not
# PROCESS_VM_WRITE -- the write layer is Phase 2 and must be UI-equivalent by
# construction (see PLAN.md), so nothing here should ever grow a poke function.
#
#   powershell -File read_mem.ps1 -ProcessName fm -Address 0x945BAAC0 -Length 320
#   powershell -File read_mem.ps1 -ProcessName fm -Address 0x945BAAC0 -Length 320 -AsJson out.json

param(
  [string]$ProcessName = "fm",
  [Parameter(Mandatory = $true)][string]$Address,
  [int]$Length = 256,
  [string]$AsJson = ""
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MemRead {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out IntPtr read);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr h);
  public const int PROCESS_VM_READ = 0x0010;
  public const int PROCESS_QUERY_INFORMATION = 0x0400;
}
"@

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Error "process '$ProcessName' not running"; exit 1 }

$h = [MemRead]::OpenProcess([MemRead]::PROCESS_VM_READ -bor [MemRead]::PROCESS_QUERY_INFORMATION, $false, $proc.Id)
if ($h -eq [IntPtr]::Zero) { Write-Error "OpenProcess failed (err $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"; exit 1 }

$addr = [Convert]::ToInt64($Address.TrimStart('0','x','X').PadLeft(1,'0'), 16)
if ($Address -notmatch '^0[xX]') { $addr = [Convert]::ToInt64($Address, 16) }

$buf = New-Object byte[] $Length
$read = [IntPtr]::Zero
$ok = [MemRead]::ReadProcessMemory($h, [IntPtr]$addr, $buf, $Length, [ref]$read)
[MemRead]::CloseHandle($h) | Out-Null

if (-not $ok) { Write-Error "ReadProcessMemory failed at 0x$($addr.ToString('X')) (err $([Runtime.InteropServices.Marshal]::GetLastWin32Error()))"; exit 1 }

if ($AsJson) {
  $obj = [ordered]@{ address = $addr.ToString('X'); length = $Length; bytes = $buf }
  $obj | ConvertTo-Json -Compress -Depth 3 | Out-File -FilePath $AsJson -Encoding utf8
  "wrote $AsJson ($([int]$read) bytes read)"
} else {
  # qword view, which is what pointer arrays need
  for ($i = 0; $i + 8 -le $Length; $i += 8) {
    $q = [BitConverter]::ToUInt64($buf, $i)
    "{0:X}  +{1,-4} {2:X}" -f ($addr + $i), $i, $q
  }
}
