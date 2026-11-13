// Pure logic for finding the formatted text of the CURRENT press-conference question.
//
// No process access here, so it can be unit-tested anywhere. The live reader
// (read_press_question.js) walks a bounded pointer graph out of fm.exe memory and
// hands the nodes to `selectQuestion()`.
//
// Status (2026-11-13): written without live access. The seam for the question text
// is NOT decoded yet. This module encodes how we expect to recognise it, and it is
// deliberately strict: it returns a question only when exactly one candidate
// survives every filter, and otherwise fails closed with the candidates listed so
// the next live session can pin the real offset path.
//
// Why a graph walk and not a fixed offset: response text was found at
// BUTTON+0x1B0 -> handle, UTF-8 at handle+4. The question text is expected to sit
// behind a similar handle, but which object owns it (the PRESS_CONFERENCE_QUESTION,
// a sibling UI text widget, or the interaction panel) is unknown. The walk records
// the offset path of every candidate so a live run turns it into a pinned path.

const MIN_LEN = 15;
const MAX_LEN = 600;

// Valid pointer range used by every other reader in this repo (FM's heap sits low).
function validPtr(v) {
  return typeof v === 'bigint' && v >= 0x10000n && v <= 0xffffffffn;
}

// Decode maximal runs of printable UTF-8 from a raw buffer. Covers both the
// handle+4 seam (the run starts 4 bytes into the node) and inline strings.
// Accents matter: player and journalist names (Martínez, Traoré) must not split.
function extractStrings(buf, minLen = MIN_LEN) {
  const out = [];
  let i = 0;
  while (i < buf.length) {
    let j = i;
    while (j < buf.length) {
      const c = buf[j];
      if (c >= 0x20 && c <= 0x7e) { j++; continue; }
      // 2-byte UTF-8 sequence (covers Latin-1 supplement / Latin Extended-A/B)
      if (c >= 0xc2 && c <= 0xdf && j + 1 < buf.length && (buf[j + 1] & 0xc0) === 0x80) { j += 2; continue; }
      // 3-byte sequence for typographic quotes / dashes (U+2018..U+201D, U+2013/2014, U+2026)
      if (c === 0xe2 && j + 2 < buf.length && buf[j + 1] === 0x80 && (buf[j + 2] & 0xc0) === 0x80) { j += 3; continue; }
      break;
    }
    if (j > i) {
      const text = buf.subarray(i, j).toString('utf8').trim();
      if (text.length >= minLen) out.push({ offset: i, text });
      i = j;
    } else {
      i++;
    }
  }
  return out;
}

function normalise(text) {
  return text.replace(/\s+/g, ' ').replace(/[‘’]/g, "'").replace(/[“”]/g, '"').trim();
}

// Does this look like the formatted, human-visible text of a journalist's question?
// Returns null when it does, or the reason it was rejected.
function rejectReason(text) {
  const t = normalise(text);
  if (t.length < MIN_LEN) return 'too_short';
  if (t.length > MAX_LEN) return 'too_long';
  // Unformatted templates still carry FM's substitution tokens. They are not what
  // the human sees, so they must never be passed to the model as the question.
  if (/\[%|%[a-z_]+#|\{\w+\}/i.test(t)) return 'template_tokens';
  if (!/\s/.test(t)) return 'no_spaces';
  if (/^[A-Z0-9_\.\-:\\\/]+$/.test(t)) return 'identifier';
  if (/^[a-z]:\\|\.(dll|exe|fmf|png|xml|ttf)\b/i.test(t)) return 'path';
  const words = t.split(' ').filter(w => /[A-Za-zÀ-ɏ]/.test(w));
  if (words.length < 4) return 'too_few_words';
  if (!t.includes('?')) return 'no_question_mark';
  return null;
}

// nodes: [{ root, path, address, bytes:Buffer }]
// responses: array of the live response texts (these must never be returned as the question)
// options.preferRoot: name of the root whose subgraph is semantically tied to the
//   current question (the PRESS_CONFERENCE_QUESTION object). Used only to break ties.
function selectQuestion(nodes, responses = [], options = {}) {
  const responseSet = new Set(responses.map(normalise));
  const byText = new Map();
  const rejected = [];
  for (const node of nodes) {
    for (const s of extractStrings(node.bytes)) {
      const text = normalise(s.text);
      if (responseSet.has(text)) { rejected.push({ text, reason: 'is_response' }); continue; }
      const reason = rejectReason(text);
      if (reason) { rejected.push({ text, reason }); continue; }
      if (!byText.has(text)) byText.set(text, { text, sightings: [] });
      byText.get(text).sightings.push({
        root: node.root,
        path: `${node.path}@+0x${s.offset.toString(16).toUpperCase()}`,
        address: node.address,
      });
    }
  }
  const candidates = [...byText.values()];
  const base = { candidates, rejected_count: rejected.length };
  if (candidates.length === 1) {
    return { ok: true, text: candidates[0].text, provenance: candidates[0].sightings, method: 'unique', ...base };
  }
  if (candidates.length > 1 && options.preferRoot) {
    const tied = candidates.filter(c => c.sightings.some(s => s.root === options.preferRoot));
    if (tied.length === 1) {
      return { ok: true, text: tied[0].text, provenance: tied[0].sightings, method: `unique_under_${options.preferRoot}`, ...base };
    }
  }
  return {
    ok: false,
    reason: candidates.length === 0 ? 'no_candidate' : 'ambiguous',
    ...base,
  };
}

module.exports = { extractStrings, rejectReason, selectQuestion, normalise, validPtr };
