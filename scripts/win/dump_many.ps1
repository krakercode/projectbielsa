# Dump many addresses from fm.exe in ONE process, into one JSON file.
#
# read_mem.ps1 handles a single address, which is fine interactively but means one
# PowerShell start-up per read -- unusable when sweeping ~200 candidate structures.
# This takes a spec file of {label, addr} pairs and dumps them all in a single
# pass, so a whole sweep is one command.
#
# Read-only by design, same as read_mem.ps1: PROCESS_VM_READ only.
#
# Spec file is JSON: [{"label":"DF7A/Leicester","addr":"DF7A4EB0"}, ...]
#
#   powershell -File dump_many.ps1 -Spec spec.json -Length 2048 -Out dump.json

param(
  [Parameter(Mandatory = $true)][string]$Spec,
  [int]$Length = 2048,
  [Parameter(Mandatory = $true)][string]$Out,
  [string]$ProcessName = "fm"
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class MemReadMany {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool ReadProcessMemory(IntPtr h, IntPtr addr, byte[] buf, int size, out IntPtr read);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool CloseHandle(IntPtr h);
}
"@

$proc = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $proc) { Write-Error "process '$ProcessName' not running"; exit 1 }

$h = [MemReadMany]::OpenProcess(0x0010 -bor 0x0400, $false, $proc.Id)
if ($h -eq [IntPtr]::Zero) { Write-Error "OpenProcess failed"; exit 1 }

$items = Get-Content $Spec -Raw | ConvertFrom-Json
$results = New-Object System.Collections.ArrayList
$ok = 0

# Read page by page. A single large read fails outright as soon as the range
# touches one unmapped page, which is common when a window is centred on a scan
# hit near an allocation boundary -- and it silently returned EMPTY buffers, which
# made a locator look like it had found nothing. Unreadable pages stay zero.
$page = 4096
foreach ($it in $items) {
  $addr = [Convert]::ToInt64($it.addr, 16)
  $buf = New-Object byte[] $Length
  $okPages = 0; $badPages = 0
  for ($off = 0; $off -lt $Length; $off += $page) {
    $want = [Math]::Min($page, $Length - $off)
    $tmp = New-Object byte[] $want
    $read = [IntPtr]::Zero
    if ([MemReadMany]::ReadProcessMemory($h, [IntPtr]($addr + $off), $tmp, $want, [ref]$read) -and [int]$read -gt 0) {
      [Array]::Copy($tmp, 0, $buf, $off, [int]$read)
      $okPages++
    } else {
      $badPages++
    }
  }
  if ($okPages -gt 0) { $ok++ }
  [void]$results.Add([ordered]@{
    label = $it.label
    addr  = $it.addr
    ok    = ($okPages -gt 0)
    pagesUnreadable = $badPages
    bytes = $buf
  })
}

[MemReadMany]::CloseHandle($h) | Out-Null

$json = [ordered]@{ length = $Length; count = $results.Count; rows = $results }
$json | ConvertTo-Json -Compress -Depth 5 | Out-File -FilePath $Out -Encoding utf8
"dumped $ok / $($results.Count) regions at $Length bytes -> $Out"
