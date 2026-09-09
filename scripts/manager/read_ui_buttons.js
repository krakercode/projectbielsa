#!/usr/bin/env node
// Read visible FM21 BUTTON / ICON_BUTTON labels and geometry from process memory.
// This is a narrow UI-write helper: observation comes from memory; callers may
// use the returned centre coordinates with SendInput. No screenshot input.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const RTTI = path.join(REPO, 'scripts', 'win', 'rtti_index.js');
const SCAN = path.join(REPO, 'scripts', 'win', 'scan_mem.ps1');
const DUMP = path.join(REPO, 'scripts', 'win', 'dump_many.ps1');
const TMP = path.join(REPO, 'data', 'snapshots');
const CLASSES = ['.?AVBUTTON@@', '.?AVICON_BUTTON@@'];

function run(cmd,args) { return execFileSync(cmd,args,{encoding:'utf8',maxBuffer:64*1024*1024}); }
function ps(script,args) { return run(PS,['-NoProfile','-ExecutionPolicy','Bypass','-File',script,...args]); }
function readJson(p) { return JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'')); }
function writeJson(p,v) { fs.writeFileSync(p,JSON.stringify(v,null,2)); }
function bytes(row) { return Buffer.from(row.bytes.value || row.bytes); }
function hex(v) { return v.toString(16).toUpperCase(); }
function pattern(v) {
  const b=Buffer.alloc(8); b.writeBigUInt64LE(BigInt(v));
  return [...b].map(x=>x.toString(16).padStart(2,'0').toUpperCase()).join(' ');
}
function cString(buf) {
  let end=buf.indexOf(0); if(end<0) end=buf.length;
  const s=buf.subarray(0,end).toString('utf8').trim();
  return /^[\x20-\x7E\u00A0-\u024F]/u.test(s) ? s : '';
}
function validPtr(v) { return v>=0x10000n && v<=0xffffffffn; }
function exactPrimary(rows,name) {
  const r=rows.filter(x=>x.name===name && x.object_offset===0);
  if(r.length!==1) throw new Error(`expected one primary ${name} vtable, got ${r.length}`);
  return r[0];
}

function main() {
  const index=JSON.parse(run(process.execPath,[RTTI,'--contains','BUTTON@@']));
  const classes=CLASSES.map(name=>exactPrimary(index.rows,name));
  const pat=path.join(TMP,'ui-button-patterns.json');
  const hit=path.join(TMP,'ui-button-hits.json');
  writeJson(pat,classes.map((r,i)=>({label:`c${i}`,pattern:pattern(r.vtable)})));
  ps(SCAN,['-PatternFile',pat,'-Out',hit,'-Max','256']);
  const hitJson=readJson(hit).byLabel || {};
  const objects=[];
  classes.forEach((r,i)=>((hitJson[`c${i}`]||[]).forEach(addr=>objects.push({className:r.name,vtable:r.vtable,addr}))));
  const spec=path.join(TMP,'ui-button-objects.json');
  const dump=path.join(TMP,'ui-button-objects-dump.json');
  writeJson(spec,objects.map((o,i)=>({label:`o${i}`,addr:o.addr})));
  if(objects.length) ps(DUMP,['-Spec',spec,'-Length','448','-Out',dump]);
  const rows=objects.length ? readJson(dump).rows : [];
  const candidates=[];
  for(let i=0;i<objects.length;i++) {
    const row=rows[i]; if(!row?.ok) continue;
    const b=bytes(row), o=objects[i];
    if(b.readBigUInt64LE(0)!==BigInt(o.vtable)) continue;
    const x=b.readFloatLE(0x5c), y=b.readFloatLE(0x60), width=b.readFloatLE(0x64), height=b.readFloatLE(0x68);
    const handle=b.readBigUInt64LE(0x1b0);
    if(![x,y,width,height].every(Number.isFinite) || x<0 || y<0 || width<=0 || height<=0 || width>2500 || height>1000) continue;
    if(!validPtr(handle)) continue;
    candidates.push({...o,x,y,width,height,handle});
  }

  const textSpec=path.join(TMP,'ui-button-text.json');
  const textDump=path.join(TMP,'ui-button-text-dump.json');
  writeJson(textSpec,candidates.map((o,i)=>({label:`t${i}`,addr:hex(o.handle+4n)})));
  if(candidates.length) ps(DUMP,['-Spec',textSpec,'-Length','512','-Out',textDump]);
  const textRows=candidates.length ? readJson(textDump).rows : [];
  const buttons=[];
  for(let i=0;i<candidates.length;i++) {
    const row=textRows[i]; if(!row?.ok) continue;
    const text=cString(bytes(row)); if(!text) continue;
    const o=candidates[i];
    buttons.push({class:o.className,object:`0x${o.addr.toUpperCase()}`,text,
      rect:{x:o.x,y:o.y,width:o.width,height:o.height},
      click:{x:Math.round(o.x+o.width/2),y:Math.round(o.y+o.height/2)}});
  }
  buttons.sort((a,b)=>a.rect.y-b.rect.y || a.rect.x-b.rect.x);
  const result={source:'fm.exe memory',count:buttons.length,buttons};
  if(process.argv.includes('--json')) console.log(JSON.stringify(result));
  else {
    console.log(`read_ui_buttons: ${buttons.length} visible labelled button(s)`);
    buttons.forEach(b=>console.log(`${b.class} (${b.click.x},${b.click.y}) ${b.text}`));
  }
}
try { main(); }
catch(e) { console.error(`read_ui_buttons: ${e.message}`); process.exit(1); }
