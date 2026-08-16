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

# Read page by page rather than in one call. A single large read fails outright
# the moment the range touches an unmapped page, which happens routinely when a
# window is centred on a hit near an allocation boundary. Unreadable pages are
# left as zeroes and counted, so callers get the data that does exist instead of
# an error.
$buf = New-Object byte[] $Length
$page = 4096
$okPages = 0; $badPages = 0
for ($off = 0; $off -lt $Length; $off += $page) {
  $want = [Math]::Min($page, $Length - $off)
  $tmp = New-Object byte[] $want
  $read = [IntPtr]::Zero
  if ([MemRead]::ReadProcessMemory($h, [IntPtr]($addr + $off), $tmp, $want, [ref]$read) -and [int]$read -gt 0) {
    [Array]::Copy($tmp, 0, $buf, $off, [int]$read)
    $okPages++
  } else {
    $badPages++
  }
}
[MemRead]::CloseHandle($h) | Out-Null

if ($okPages -eq 0) {
  Write-Error "ReadProcessMemory failed for every page at 0x$($addr.ToString('X'))"
  exit 1
}

if ($AsJson) {
  $obj = [ordered]@{ address = $addr.ToString('X'); length = $Length; bytes = $buf
                     pagesOk = $okPages; pagesUnreadable = $badPages }
  $obj | ConvertTo-Json -Compress -Depth 3 | Out-File -FilePath $AsJson -Encoding utf8
  "wrote $AsJson ($okPages page(s) read, $badPages unreadable)"
} else {
  # qword view, which is what pointer arrays need
  for ($i = 0; $i + 8 -le $Length; $i += 8) {
    $q = [BitConverter]::ToUInt64($buf, $i)
    "{0:X}  +{1,-4} {2:X}" -f ($addr + $i), $i, $q
  }
}
