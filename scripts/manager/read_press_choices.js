#!/usr/bin/env node
// Read the active FM21 press-conference response choices from process memory.
// Observation is memory-only; screenshots are not used. UI geometry is read from
// the live response widgets so a caller can apply a chosen answer via SendInput.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const RTTI = path.join(REPO, 'scripts', 'win', 'rtti_index.js');
const SCAN = path.join(REPO, 'scripts', 'win', 'scan_mem.ps1');
const DUMP = path.join(REPO, 'scripts', 'win', 'dump_many.ps1');
const TMP = path.join(REPO, 'data', 'snapshots');
const NAME = '.?AVINTERACTION_RESPONSE_WIDGET@@';

function pattern(v) {
  const b = Buffer.alloc(8); b.writeBigUInt64LE(BigInt(v));
  return [...b].map(x => x.toString(16).padStart(2, '0').toUpperCase()).join(' ');
}
function ps(script, args) {
  return execFileSync(PS, ['-NoProfile','-ExecutionPolicy','Bypass','-File',script,...args],
    { encoding:'utf8', maxBuffer:64*1024*1024 });
}
function jsonFile(p) {
  return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
}
function writeSpec(p, rows) { fs.writeFileSync(p, JSON.stringify(rows, null, 2)); }
function bytes(row) { return Buffer.from(row.bytes.value || row.bytes); }

function qword(buf, off) { return buf.readBigUInt64LE(off); }
function finiteFloat(buf, off) {
  const v = buf.readFloatLE(off);
  return Number.isFinite(v) ? v : NaN;
}
function validHeapPtr(v) { return v >= 0x10000n && v <= 0xffffffffn; }
function hex(v) { return v.toString(16).toUpperCase(); }
function cString(buf) {
  let end = buf.indexOf(0);
  if (end < 0) end = buf.length;
  const text = buf.subarray(0, end).toString('utf8').trim();
  return /^[\x20-\x7E\u00A0-\u024F]/u.test(text) ? text : '';
}
function exactPrimary(index, name) {
  const rows = index.rows.filter(r => r.name === name && r.object_offset === 0);
  if (rows.length !== 1) throw new Error(`expected one primary vtable for ${name}, got ${rows.length}`);
  return rows[0];
}

function main() {
  const widgetIndex = JSON.parse(execFileSync(process.execPath,
    [RTTI, '--contains', 'INTERACTION_RESPONSE_WIDGET'], { encoding:'utf8' }));
  const buttonIndex = JSON.parse(execFileSync(process.execPath,
    [RTTI, '--contains', '?AVBUTTON@@'], { encoding:'utf8' }));
  const widgetVt = exactPrimary(widgetIndex, NAME);
  const buttonVt = exactPrimary(buttonIndex, '.?AVBUTTON@@');

  const scanSpec = path.join(TMP, 'press-choice-widget-pattern.json');
  const scanOut = path.join(TMP, 'press-choice-widget-hits.json');
  writeSpec(scanSpec, [{ label:'widget', pattern:pattern(widgetVt.vtable) }]);
  ps(SCAN, ['-PatternFile', scanSpec, '-Out', scanOut, '-Max', '32']);
  const hits = (jsonFile(scanOut).byLabel || {}).widget || [];
  if (!hits.length) throw new Error('no live INTERACTION_RESPONSE_WIDGET objects found');

  const widgetSpec = path.join(TMP, 'press-choice-widgets.json');
  const widgetDump = path.join(TMP, 'press-choice-widgets-dump.json');
  writeSpec(widgetSpec, hits.map((addr, i) => ({ label:`w${i}`, addr })));
  ps(DUMP, ['-Spec', widgetSpec, '-Length', '448', '-Out', widgetDump]);

  const widgets = [];
  for (const row of jsonFile(widgetDump).rows) {
    if (!row.ok) continue;
    const b = bytes(row);
    if (qword(b, 0) !== BigInt(widgetVt.vtable)) continue;
    const x = finiteFloat(b, 0x5c), y = finiteFloat(b, 0x60);
    const width = finiteFloat(b, 0x64), height = finiteFloat(b, 0x68);
    const button = qword(b, 0x1a0);
    if (![x,y,width,height].every(Number.isFinite)) continue;
    if (x < 0 || y < 0 || width < 40 || width > 1200 || height < 15 || height > 300) continue;
    if (!validHeapPtr(button)) continue;
    widgets.push({ widget: row.addr.toUpperCase(), x, y, width, height, button });
  }
  if (widgets.length < 2 || widgets.length > 12)
    throw new Error(`implausible active response-widget count: ${widgets.length}`);

  const buttonSpec = path.join(TMP, 'press-choice-buttons.json');
  const buttonDump = path.join(TMP, 'press-choice-buttons-dump.json');
  writeSpec(buttonSpec, widgets.map((w, i) => ({ label:`b${i}`, addr:hex(w.button) })));
  ps(DUMP, ['-Spec', buttonSpec, '-Length', '448', '-Out', buttonDump]);
  const buttonRows = jsonFile(buttonDump).rows;

  const textReads = [];
  for (let i = 0; i < widgets.length; i++) {
    const row = buttonRows[i];
    if (!row || !row.ok) continue;
    const b = bytes(row);
    if (qword(b, 0) !== BigInt(buttonVt.vtable)) continue;
    const handle = qword(b, 0x1b0);
    if (!validHeapPtr(handle)) continue;
    textReads.push({ index:i, handle, addr:handle + 4n });
  }
  if (textReads.length !== widgets.length)
    throw new Error(`validated ${textReads.length}/${widgets.length} response buttons`);

  const textSpec = path.join(TMP, 'press-choice-text.json');
  const textDump = path.join(TMP, 'press-choice-text-dump.json');
  writeSpec(textSpec, textReads.map((t, i) => ({ label:`t${i}`, addr:hex(t.addr) })));
  ps(DUMP, ['-Spec', textSpec, '-Length', '512', '-Out', textDump]);
  const textRows = jsonFile(textDump).rows;

  const choices = [];
  for (let i = 0; i < widgets.length; i++) {
    const row = textRows[i];
    if (!row || !row.ok) throw new Error(`response text ${i} unreadable`);
    const text = cString(bytes(row));
    if (text.length < 2) throw new Error(`response text ${i} empty/invalid`);
    const w = widgets[i];
    choices.push({
      text,
      widget: `0x${w.widget}`,
      button: `0x${hex(w.button)}`,
      text_handle: `0x${hex(textReads[i].handle)}`,
      rect: { x:w.x, y:w.y, width:w.width, height:w.height },
      click: { x:Math.round(w.x + w.width / 2), y:Math.round(w.y + w.height / 2) },
    });
  }
  choices.sort((a, b) => a.rect.x - b.rect.x || a.rect.y - b.rect.y);
  const result = {
    source: 'fm.exe memory',
    widget_class: NAME,
    widget_vtable: widgetVt.vtable,
    button_vtable: buttonVt.vtable,
    count: choices.length,
    choices,
  };
  if (process.argv.includes('--json')) console.log(JSON.stringify(result));
  else {
    console.log(`read_press_choices: ${choices.length} live choice(s)`);
    choices.forEach((c, i) => console.log(`${i}: (${c.click.x},${c.click.y}) ${c.text}`));
  }
}

try { main(); }
catch (e) { console.error(`read_press_choices: ${e.message}`); process.exit(1); }
