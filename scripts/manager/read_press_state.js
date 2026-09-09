#!/usr/bin/env node
// Read authoritative live press-conference progress/current question from fm.exe memory.
// Observation is memory-only. PRESS_CONFERENCE_EDIT_SESSION owns the question vector;
// +0xE0 is a verified answered-response/progress counter. While a question is active,`r`n// questions[counter] identifies it; at terminal state the counter can exceed vector length.
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const PS = 'powershell.exe';
const RTTI = path.join(REPO, 'scripts', 'win', 'rtti_index.js');
const SCAN = path.join(REPO, 'scripts', 'win', 'scan_mem.ps1');
const DUMP = path.join(REPO, 'scripts', 'win', 'dump_many.ps1');
const TMP = path.join(REPO, 'data', 'snapshots');
const NAME = '.?AVPRESS_CONFERENCE_EDIT_SESSION@@';

function run(cmd, args) {
  return execFileSync(cmd, args, { encoding:'utf8', maxBuffer:64*1024*1024 });
}
function ps(script, args) {
  return run(PS, ['-NoProfile','-ExecutionPolicy','Bypass','-File',script,...args]);
}
function readJson(p) { return JSON.parse(fs.readFileSync(p,'utf8').replace(/^\uFEFF/,'')); }
function writeJson(p, v) { fs.writeFileSync(p, JSON.stringify(v, null, 2)); }
function bytes(row) { return Buffer.from(row.bytes.value || row.bytes); }
function hex(v) { return '0x' + BigInt(v).toString(16).toUpperCase(); }
function pattern(v) {
  const b=Buffer.alloc(8); b.writeBigUInt64LE(BigInt(v));
  return [...b].map(x=>x.toString(16).padStart(2,'0').toUpperCase()).join(' ');
}
function main() {
  const idx = JSON.parse(run(process.execPath,[RTTI,'--contains','PRESS_CONFERENCE_EDIT_SESSION']));
  const vt = idx.rows.find(r => r.name === NAME && r.object_offset === 0);
  if (!vt) throw new Error('primary PRESS_CONFERENCE_EDIT_SESSION vtable not found');

  const patFile=path.join(TMP,'press-state-pattern.json');
  const hitFile=path.join(TMP,'press-state-hit.json');
  writeJson(patFile,[{label:'session',pattern:pattern(vt.vtable)}]);
  ps(SCAN,['-PatternFile',patFile,'-Out',hitFile,'-Max','8']);
  const hits=(readJson(hitFile).byLabel||{}).session||[];
  if (hits.length !== 1) throw new Error(`expected one live edit session, got ${hits.length}`);

  const session=hits[0];
  const spec=path.join(TMP,'press-state-session-spec.json');
  const dump=path.join(TMP,'press-state-session-dump.json');
  writeJson(spec,[{label:'session',addr:session}]);
  ps(DUMP,['-Spec',spec,'-Length','512','-Out',dump]);
  const sb=bytes(readJson(dump).rows[0]);
  if (sb.readBigUInt64LE(0) !== BigInt(vt.vtable)) throw new Error('edit-session vtable changed during read');

  const begin=sb.readBigUInt64LE(0x28), end=sb.readBigUInt64LE(0x30);
  const answered=sb.readUInt32LE(0xe0);
  if (end < begin || (end-begin)%8n) throw new Error('invalid question vector');
  const count=Number((end-begin)/8n);
  if (count < 1 || count > 64) throw new Error(`implausible question count ${count}`);

  const vecSpec=path.join(TMP,'press-state-qvec-spec.json');
  const vecDump=path.join(TMP,'press-state-qvec-dump.json');
  writeJson(vecSpec,Array.from({length:count},(_,i)=>({label:`q${i}`,addr:(begin+BigInt(i*8)).toString(16)})));
  ps(DUMP,['-Spec',vecSpec,'-Length','8','-Out',vecDump]);
  const questions=readJson(vecDump).rows.map(r=>bytes(r).readBigUInt64LE(0));
  let current=null;
  if (answered < questions.length) {
    const q=questions[answered];
    const qSpec=path.join(TMP,'press-state-current-spec.json');
    const qDump=path.join(TMP,'press-state-current-dump.json');
    writeJson(qSpec,[{label:'current',addr:q.toString(16)}]);
    ps(DUMP,['-Spec',qSpec,'-Length','192','-Out',qDump]);
    const qb=bytes(readJson(qDump).rows[0]);
    current={
      address:hex(q),
      id:hex(qb.readUInt32LE(0x98)),
      media_source:hex(qb.readBigUInt64LE(0x20)),
      journalist:hex(qb.readBigUInt64LE(0x28)),
      parameter_begin:hex(qb.readBigUInt64LE(0x08)),
      parameter_end:hex(qb.readBigUInt64LE(0x10)),
    };
  }
  const result={
    source:'fm.exe memory',
    session:hex(BigInt('0x'+session)),
    session_vtable:vt.vtable,
    answered_count:answered,
    question_count:questions.length,
    phase:current ? 'question' : 'terminal_or_inactive',
    current_question:current,
    questions:questions.map(hex),
  };
  if (process.argv.includes('--json')) console.log(JSON.stringify(result));
  else {
    console.log(`press state: answered ${answered}/${questions.length}`);
    if (current) console.log(`current ${current.address} id=${current.id} journalist=${current.journalist}`);
    else console.log('no unanswered question in vector');
  }
}
try { main(); }
catch(e) { console.error(`read_press_state: ${e.message}`); process.exit(1); }
