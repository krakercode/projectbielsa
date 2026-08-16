# Scan fm.exe's writable memory for a byte pattern. No Cheat Engine involved.
#
# WHY THIS EXISTS
# Locating structures previously meant CE's AOBScan, and CE's Lua engine is
# single-threaded and uninterruptible -- one badly-shaped scan blocked it for ~25
# minutes with no way to stop it. Anything the harness needs to do routinely (like
# re-finding an address after a restart) should not depend on that.
#
# The enumeration+read is PowerShell; the inner byte search is C# via Add-Type,
# because a naive PowerShell loop over ~1 GB is far too slow to be usable.
#
# READ-ONLY by design: PROCESS_VM_READ only, never PROCESS_VM_WRITE. The write
# layer is UI-driven on purpose (see scripts/lua/actions.lua) -- do not add a poke.
#
#   powershell -File scan_mem.ps1 -Pattern "0F EF D5 00 08 00 00 00"
#   powershell -File scan_mem.ps1 -Pattern "0F EF D5 00" -Out hits.json -Max 500

param(
  [Parameter(Mandatory = $true)][string]$Pattern,   # space-separated hex bytes
  [string]$ProcessName = "fm",
  [string]$Out = "",
  [int]$Max = 2000
)

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public class BielsaScan {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, IntPtr size, out IntPtr read);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll")]
  public static extern IntPtr VirtualQueryEx(IntPtr h, IntPtr addr, out MEMORY_BASIC_INFORMATION mbi, IntPtr len);

  [StructLayout(LayoutKind.Sequential)]
  public struct MEMORY_BASIC_INFORMATION {
    public IntPtr BaseAddress; public IntPtr AllocationBase; public uint AllocationProtect;
    public IntPtr RegionSize; public uint State; public uint Protect; public uint Type;
  }

  const int PROCESS_VM_READ = 0x0010;
  const int PROCESS_QUERY_INFORMATION = 0x0400;
  const uint MEM_COMMIT = 0x1000;
  const uint PAGE_GUARD = 0x100;
  const uint PAGE_NOACCESS = 0x01;

  static bool Writable(uint p) {
    uint b = p & 0xFF;
    return b == 0x04 || b == 0x08 || b == 0x40 || b == 0x80;   // RW, WC, ERW, EWC
  }

  // Scan a chunk for the pattern. Returns offsets within the chunk.
  static void Find(byte[] buf, int len, byte[] pat, long baseAddr, List<long> hits, int max) {
    int n = pat.Length;
    byte first = pat[0];
    for (int i = 0; i + n <= len; i++) {
      if (buf[i] != first) continue;
      int j = 1;
      while (j < n && buf[i + j] == pat[j]) j++;
      if (j == n) {
        hits.Add(baseAddr + i);
        if (hits.Count >= max) return;
      }
    }
  }

  public static List<long> Scan(int pid, byte[] pat, int max, out long bytesScanned, out int regions) {
    var hits = new List<long>();
    bytesScanned = 0; regions = 0;
    IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
    if (h == IntPtr.Zero) return hits;

    long addr = 0;
    long limit = 0x7FFFFFFFFFFF;
    int mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
    // Chunked reads with an overlap, so a pattern straddling a chunk edge is
    // still found rather than silently missed.
    int chunk = 4 * 1024 * 1024;
    byte[] buf = new byte[chunk];

    while (addr < limit && hits.Count < max) {
      MEMORY_BASIC_INFORMATION mbi;
      if (VirtualQueryEx(h, (IntPtr)addr, out mbi, (IntPtr)mbiSize) == IntPtr.Zero) break;
      long regionBase = (long)mbi.BaseAddress;
      long regionSize = (long)mbi.RegionSize;
      if (regionSize <= 0) break;

      bool ok = mbi.State == MEM_COMMIT
             && (mbi.Protect & PAGE_GUARD) == 0
             && (mbi.Protect & PAGE_NOACCESS) == 0
             && Writable(mbi.Protect);

      if (ok) {
        regions++;
        long off = 0;
        while (off < regionSize && hits.Count < max) {
          int want = (int)Math.Min((long)chunk, regionSize - off);
          IntPtr got;
          if (ReadProcessMemory(h, (IntPtr)(regionBase + off), buf, (IntPtr)want, out got) && (long)got > 0) {
            int len = (int)got;
            Find(buf, len, pat, regionBase + off, hits, max);
            bytesScanned += len;
          }
          if (want <= pat.Length) break;
          off += want - pat.Length;      // overlap by pattern length
        }
      }
      addr = regionBase + regionSize;
    }
    CloseHandle(h);
    return hits;
  }
}
"@

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Error "process '$ProcessName' not running"; exit 1 }

$bytes = @($Pattern -split '\s+' | Where-Object { $_ } | ForEach-Object { [byte][Convert]::ToInt32($_, 16) })
if ($bytes.Count -lt 2) { Write-Error "pattern must be at least 2 bytes"; exit 1 }

$scanned = [long]0
$regions = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
$hits = [BielsaScan]::Scan($proc.Id, $bytes, $Max, [ref]$scanned, [ref]$regions)
$sw.Stop()

$hex = $hits | ForEach-Object { $_.ToString('X') }

if ($Out) {
  [ordered]@{ pattern = $Pattern; count = $hits.Count; hits = @($hex) } |
    ConvertTo-Json -Compress -Depth 3 | Out-File -FilePath $Out -Encoding utf8
  "{0} hit(s) in {1} regions, {2:N0} MB scanned, {3:N1}s -> {4}" -f `
    $hits.Count, $regions, ($scanned / 1MB), $sw.Elapsed.TotalSeconds, $Out
} else {
  "{0} hit(s) in {1} regions, {2:N0} MB scanned, {3:N1}s" -f `
    $hits.Count, $regions, ($scanned / 1MB), $sw.Elapsed.TotalSeconds
  $hex | ForEach-Object { "  $_" }
}
