# Read-only bounded pointer graph walk for live fm.exe objects.
# Emits printable inline strings and pointer paths; intended for RE of opaque UI/state objects.
param(
  [Parameter(Mandatory=$true)][string]$Address,
  [int]$Depth = 3,
  [int]$BytesPerNode = 768,
  [int]$MaxNodes = 400,
  [int]$MinString = 16,
  [long]$MaxPointer = 4294967295,
  [string]$ProcessName = 'fm',
  [switch]$AsJson
)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class BielsaWalk {
 [DllImport("kernel32.dll", SetLastError=true)] public static extern IntPtr OpenProcess(int a,bool i,int p);
 [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadProcessMemory(IntPtr h,IntPtr a,byte[] b,int s,out IntPtr r);
 [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
"@
$p=Get-Process -Name $ProcessName -ErrorAction SilentlyContinue | Select-Object -First 1
if(-not $p){ Write-Error "process '$ProcessName' not running"; exit 1 }
$h=[BielsaWalk]::OpenProcess(0x0010 -bor 0x0400,$false,$p.Id)
if($h -eq [IntPtr]::Zero){ Write-Error 'OpenProcess failed'; exit 1 }
function Hex([long]$v){ '0x{0:X}' -f $v }
function ReadBlock([long]$a,[int]$n){
 $b=New-Object byte[] $n; $r=[IntPtr]::Zero
 if([BielsaWalk]::ReadProcessMemory($h,[IntPtr]$a,$b,$n,[ref]$r) -and [int64]$r -gt 0){ return ,$b[0..([int64]$r-1)] }
 return $null
}function InlineStrings([byte[]]$b){
 $out=@(); $start=-1
 for($i=0;$i -le $b.Length;$i++){
   $ok=($i -lt $b.Length -and $b[$i] -ge 32 -and $b[$i] -le 126)
   if($ok -and $start -lt 0){$start=$i}
   if((-not $ok) -and $start -ge 0){
     $len=$i-$start
     if($len -ge $MinString){
       $txt=[Text.Encoding]::ASCII.GetString($b,$start,$len)
       $out += [ordered]@{offset=('0x{0:X}' -f $start); text=$txt}
     }
     $start=-1
   }
 }
 return $out
}
$root=[Convert]::ToInt64(($Address -replace '^0x',''),16)
$q=New-Object System.Collections.Queue
$q.Enqueue([ordered]@{addr=$root; depth=0; path='root'})
$seen=@{}; $rows=New-Object System.Collections.ArrayList
while($q.Count -gt 0 -and $seen.Count -lt $MaxNodes){
 $cur=$q.Dequeue(); $key=Hex $cur.addr
 if($seen.ContainsKey($key)){continue}; $seen[$key]=$true
 $buf=ReadBlock $cur.addr $BytesPerNode
 if(-not $buf){continue}
 $str=InlineStrings $buf
 $ptrs=New-Object System.Collections.ArrayList
 for($off=0;$off+8 -le $buf.Length;$off+=8){
   $v=[BitConverter]::ToInt64($buf,$off)
   if($v -lt 0x10000 -or $v -gt $MaxPointer){continue}
   $probe=ReadBlock $v 8; if(-not $probe){continue}
   [void]$ptrs.Add([ordered]@{offset=('0x{0:X}' -f $off); addr=(Hex $v)})
   if($cur.depth -lt $Depth){$q.Enqueue([ordered]@{addr=$v;depth=$cur.depth+1;path=($cur.path+'+0x{0:X}' -f $off)})}
 }
 [void]$rows.Add([ordered]@{address=$key;depth=$cur.depth;path=$cur.path;strings=$str;pointers=$ptrs})
}[BielsaWalk]::CloseHandle($h)|Out-Null
$result=[ordered]@{root=(Hex $root);depth=$Depth;nodes=$rows.Count;rows=$rows}
if($AsJson){$result|ConvertTo-Json -Compress -Depth 8}
else{
 "walk_ptrs: $($rows.Count) node(s) from $(Hex $root)"
 foreach($r in $rows){
   if($r.strings.Count -eq 0){continue}
   foreach($s in $r.strings){"$($r.path) $($r.address)+$($s.offset): $($s.text)"}
 }
}

