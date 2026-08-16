# Scan fm.exe's writable memory for one or many byte patterns. No Cheat Engine.
#
# WHY THIS EXISTS
# Locating structures previously meant CE's AOBScan, and CE's Lua engine is
# single-threaded and uninterruptible -- one badly-shaped scan blocked it for ~25
# minutes with no way to stop it. Anything the harness needs to do routinely (like
# re-finding an address after a restart) should not depend on that.
#
# WHY MULTI-PATTERN
# Locating a 23-player squad by scanning once per player meant 23 passes over
# ~2.5 GB (~55 s). All patterns are now searched in a SINGLE pass, dispatched on
# their first byte, so 23 patterns cost barely more than one. That is what makes a
# CE-free live squad read practical inside a decision loop.
#
# The enumeration+read is PowerShell; the inner byte search is C# via Add-Type,
# because a naive PowerShell loop over ~1 GB is far too slow to be usable.
#
# READ-ONLY by design: PROCESS_VM_READ only, never PROCESS_VM_WRITE. The write
# layer is UI-driven on purpose (see scripts/lua/actions.lua) -- do not add a poke.
#
#   powershell -File scan_mem.ps1 -Pattern "0F EF D5 00 08 00 00 00"
#   powershell -File scan_mem.ps1 -Pattern "0F EF D5 00" -Out hits.json -Max 500
#   powershell -File scan_mem.ps1 -PatternFile pats.json -Out hits.json
#
# -PatternFile is JSON: [{"label":"martinez","pattern":"0F EF D5 00 ..."}, ...]
# Single-pattern output:  {pattern, count, hits:[hex,...]}
# Multi-pattern output:   {count, byLabel:{label:[hex,...], ...}}

param(
  [string]$Pattern = "",
  [string]$PatternFile = "",
  [string]$ProcessName = "fm",
  [string]$Out = "",
  [int]$Max = 2000            # per pattern
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

  // Results: one list of absolute addresses per pattern, index-aligned to `pats`.
  public static List<long>[] ScanMany(int pid, byte[][] pats, int max,
                                      out long bytesScanned, out int regions) {
    int np = pats.Length;
    var hits = new List<long>[np];
    for (int i = 0; i < np; i++) hits[i] = new List<long>();
    bytesScanned = 0; regions = 0;

    // Dispatch on first byte: at each position only patterns starting with that
    // byte are compared. This is what keeps many patterns near the cost of one.
    var byFirst = new List<int>[256];
    for (int i = 0; i < np; i++) {
      int f = pats[i][0];
      if (byFirst[f] == null) byFirst[f] = new List<int>();
      byFirst[f].Add(i);
    }

    int longest = 0;
    for (int i = 0; i < np; i++) if (pats[i].Length > longest) longest = pats[i].Length;

    IntPtr h = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, false, pid);
    if (h == IntPtr.Zero) return hits;

    long addr = 0;
    long limit = 0x7FFFFFFFFFFF;
    int mbiSize = Marshal.SizeOf(typeof(MEMORY_BASIC_INFORMATION));
    int chunk = 4 * 1024 * 1024;
    byte[] buf = new byte[chunk];

    while (addr < limit) {
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
        while (off < regionSize) {
          int want = (int)Math.Min((long)chunk, regionSize - off);
          IntPtr got;
          if (ReadProcessMemory(h, (IntPtr)(regionBase + off), buf, (IntPtr)want, out got) && (long)got > 0) {
            int len = (int)got;
            long chunkBase = regionBase + off;
            for (int i = 0; i + longest <= len; i++) {
              var cand = byFirst[buf[i]];
              if (cand == null) continue;
              for (int k = 0; k < cand.Count; k++) {
                int pi = cand[k];
                byte[] pat = pats[pi];
                if (i + pat.Length > len) continue;
                if (hits[pi].Count >= max) continue;
                int j = 1;
                while (j < pat.Length && buf[i + j] == pat[j]) j++;
                if (j == pat.Length) hits[pi].Add(chunkBase + i);
              }
            }
            bytesScanned += len;
          }
          if (want <= longest) break;
          off += want - longest;      // overlap so a straddling match is not missed
        }
      }
      addr = regionBase + regionSize;
    }
    CloseHandle(h);
    return hits;
  }
}
"@

function ConvertTo-PatternBytes([string]$s) {
  $parts = $s -split '\s+' | Where-Object { $_ }
  if ($parts.Count -lt 2) { throw "pattern must be at least 2 bytes: '$s'" }
  return ,@($parts | ForEach-Object { [byte][Convert]::ToInt32($_, 16) })
}

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Error "process '$ProcessName' not running"; exit 1 }

$labels = @()
$patternList = @()

if ($PatternFile) {
  $spec = Get-Content $PatternFile -Raw | ConvertFrom-Json
  foreach ($it in $spec) {
    $labels += $it.label
    $patternList += ,(ConvertTo-PatternBytes $it.pattern)
  }
} elseif ($Pattern) {
  $labels += "pattern"
  $patternList += ,(ConvertTo-PatternBytes $Pattern)
} else {
  Write-Error "give -Pattern or -PatternFile"; exit 1
}

$scanned = [long]0
$regions = 0
$sw = [Diagnostics.Stopwatch]::StartNew()
$res = [BielsaScan]::ScanMany($proc.Id, $patternList, $Max, [ref]$scanned, [ref]$regions)
$sw.Stop()

$total = 0
foreach ($l in $res) { $total += $l.Count }

if ($PatternFile) {
  $byLabel = [ordered]@{}
  for ($i = 0; $i -lt $labels.Count; $i++) {
    $byLabel[$labels[$i]] = @($res[$i] | ForEach-Object { $_.ToString('X') })
  }
  $obj = [ordered]@{ count = $total; byLabel = $byLabel }
} else {
  $obj = [ordered]@{ pattern = $Pattern; count = $total
                     hits = @($res[0] | ForEach-Object { $_.ToString('X') }) }
}

if ($Out) {
  $obj | ConvertTo-Json -Compress -Depth 4 | Out-File -FilePath $Out -Encoding utf8
  "{0} pattern(s), {1} hit(s) in {2} regions, {3:N0} MB, {4:N1}s -> {5}" -f `
    $labels.Count, $total, $regions, ($scanned / 1MB), $sw.Elapsed.TotalSeconds, $Out
} else {
  "{0} pattern(s), {1} hit(s) in {2} regions, {3:N0} MB, {4:N1}s" -f `
    $labels.Count, $total, $regions, ($scanned / 1MB), $sw.Elapsed.TotalSeconds
  for ($i = 0; $i -lt $labels.Count; $i++) {
    if ($res[$i].Count) {
      "  [{0}] {1} hit(s)" -f $labels[$i], $res[$i].Count
      $res[$i] | Select-Object -First 12 | ForEach-Object { "     " + $_.ToString('X') }
    }
  }
}
