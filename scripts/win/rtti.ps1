# Resolve an MSVC x64 vtable pointer in fm.exe to its RTTI class name.
# Read-only: PROCESS_VM_READ + QUERY_INFORMATION only.
# Examples:
#   rtti.ps1 -Vtable 0x14690BE28
#   & .\rtti.ps1 -Vtable @('0x14690BE28','0x146904430')
param(
  [Parameter(Mandatory=$true)][string[]]$Vtable,
  [string]$ProcessName='fm'
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BielsaRtti {
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)]
  public static extern bool ReadProcessMemory(IntPtr h, IntPtr a, byte[] b, int n, out IntPtr got);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
"@

$p=Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if(-not $p){Write-Error "process '$ProcessName' not running"; exit 1}
$mod=$p.Modules | Where-Object {$_.ModuleName -eq 'fm.exe'} | Select-Object -First 1
$base=$mod.BaseAddress.ToInt64()
$h=[BielsaRtti]::OpenProcess(0x0010 -bor 0x0400,$false,$p.Id)
if($h -eq [IntPtr]::Zero){Write-Error 'OpenProcess failed'; exit 1}
function Read-At([long]$addr,[int]$n) {
  $b=New-Object byte[] $n; $got=[IntPtr]::Zero
  if(-not [BielsaRtti]::ReadProcessMemory($h,[IntPtr]$addr,$b,$n,[ref]$got) -or [int]$got -lt $n){ return $null }
  return ,$b
}
function Parse-Hex([string]$s) {
  $t=$s.Trim(); if($t -match '^0[xX]'){ $t=$t.Substring(2) }
  return [Convert]::ToInt64($t,16)
}
$results=@()
foreach($s in $Vtable){
  $vt=Parse-Hex $s; $name=$null; $col=0; $td=0; $err=$null
  try {
    $pre=Read-At ($vt-8) 8; if(-not $pre){ throw 'cannot read vtable[-8]' }
    $col=[BitConverter]::ToInt64($pre,0)
    if($col -lt $base -or $col -ge ($base+$mod.ModuleMemorySize)){ throw 'COL outside fm.exe' }
    $cb=Read-At $col 24; if(-not $cb){ throw 'cannot read COL' }
    $sig=[BitConverter]::ToUInt32($cb,0); if($sig -ne 1){ throw "unexpected COL signature $sig" }
    $rva=[BitConverter]::ToUInt32($cb,12); $td=$base+$rva
    $tb=Read-At ($td+16) 240; if(-not $tb){ throw 'cannot read TypeDescriptor name' }
    $z=[Array]::IndexOf($tb,[byte]0); if($z -lt 0){$z=$tb.Length}
    $name=[Text.Encoding]::ASCII.GetString($tb,0,$z)
  } catch { $err=$_.Exception.Message }
  $results += [pscustomobject]@{vtable=('0x{0:X}' -f $vt); col=$(if($col){'0x{0:X}' -f $col}else{$null}); typeDescriptor=$(if($td){'0x{0:X}' -f $td}else{$null}); name=$name; error=$err}
}
[BielsaRtti]::CloseHandle($h)|Out-Null
if($env:BIELSA_RTTI_JSON -eq '1'){ $results | ConvertTo-Json -Depth 3 } else { $results | Format-Table -AutoSize }
