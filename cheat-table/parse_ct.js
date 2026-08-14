// One-off parser: walks fm.CT's XML and extracts a flat list of leaf data
// fields (Description breadcrumb, root symbol, offset chain, variable type)
// for each top-level record (Current Player / Current Club / Current Staff).
// Not part of the runtime pipeline -- used once to generate scripts/lua/dump_state.lua
// accurately from the vendored table instead of hand-transcribing offsets.

const fs = require('fs');
const path = require('path');

const ctPath = path.join(__dirname, 'FM21-Cheat-Table', 'Source', 'fm.CT');
const xml = fs.readFileSync(ctPath, 'utf8');

const tagRe = /<(\/?)(CheatEntry|Description|Address|VariableType|ShowAsHex|ShowAsSigned|Offset|Offsets|\/Offsets)\b[^>]*>([^<]*)/g;

// Stack of entry objects currently open. Each: {desc, address, varType, offsets:[], showAsHex, showAsSigned}
const stack = [];
const roots = []; // top-level CheatEntry objects (with children) in document order
let currentParentChildren = roots;
const parentStack = [currentParentChildren];
let inOffsets = false;
let m;

while ((m = tagRe.exec(xml)) !== null) {
  const closing = m[1] === '/';
  const tag = m[2];
  const text = m[3];

  if (tag === 'CheatEntry') {
    if (!closing) {
      const entry = { desc: null, address: null, varType: null, offsets: [], showAsHex: false, showAsSigned: false, children: [] };
      parentStack[parentStack.length - 1].push(entry);
      stack.push(entry);
      parentStack.push(entry.children);
    } else {
      stack.pop();
      parentStack.pop();
    }
  } else if (tag === 'Offsets') {
    inOffsets = !closing;
  } else if (tag === 'Description' && !closing) {
    const cur = stack[stack.length - 1];
    if (cur) cur.desc = text.replace(/^"|"$/g, '');
  } else if (tag === 'Address' && !closing) {
    const cur = stack[stack.length - 1];
    if (cur) cur.address = text.trim();
  } else if (tag === 'VariableType' && !closing) {
    const cur = stack[stack.length - 1];
    if (cur) cur.varType = text.trim();
  } else if (tag === 'ShowAsHex' && !closing) {
    const cur = stack[stack.length - 1];
    if (cur) cur.showAsHex = text.trim() === '1';
  } else if (tag === 'ShowAsSigned' && !closing) {
    const cur = stack[stack.length - 1];
    if (cur) cur.showAsSigned = text.trim() === '1';
  } else if (tag === 'Offset' && !closing && inOffsets) {
    const cur = stack[stack.length - 1];
    if (cur) cur.offsets.push(text.trim());
  }
}

// Flatten: walk the tree, collecting leaf entries (has address, varType != Auto Assembler Script, has offsets)
function flatten(entries, breadcrumb, out) {
  for (const e of entries) {
    const bc = e.desc ? [...breadcrumb, e.desc] : breadcrumb;
    const isLeaf = e.address && e.varType && e.varType !== 'Auto Assembler Script' && e.offsets.length > 0;
    if (isLeaf) {
      // Cheat Engine stores <Offsets> innermost-first -- the reverse of the
      // order they're applied in. For "Wage Per Week" the table lists
      // [18, 338], but the actual chain is [[pCurrentPlayer] + 338] + 18:
      // 338 locates the contract object on the player, 18 is the wage field
      // inside it. Emit them in application order so consumers can just walk
      // the array forwards. (Confirmed live 2026-08-14: with the raw order,
      // every multi-level chain -- all names, all contract fields -- resolved
      // to garbage and read back nil, while single-offset fields worked
      // because reversing a one-element list is a no-op.)
      const offsets = e.offsets.slice().reverse();
      out.push({ path: bc, address: e.address, offsets, varType: e.varType, showAsHex: e.showAsHex, showAsSigned: e.showAsSigned });
    }
    if (e.children && e.children.length) flatten(e.children, bc, out);
  }
}

// Find the three top-level record roots by description, wherever they are in the tree
function findByDesc(entries, desc) {
  for (const e of entries) {
    if (e.desc === desc) return e;
    if (e.children && e.children.length) {
      const found = findByDesc(e.children, desc);
      if (found) return found;
    }
  }
  return null;
}

const records = {};
for (const name of ['Current Player', 'Current Club', 'Current Staff']) {
  const root = findByDesc(roots, name);
  if (!root) { console.error('NOT FOUND:', name); continue; }
  const out = [];
  flatten(root.children, [], out);
  records[name] = out;
}

fs.writeFileSync(path.join(__dirname, 'fields.json'), JSON.stringify(records, null, 2));
for (const name of Object.keys(records)) {
  console.log(name, '->', records[name].length, 'leaf fields');
}
