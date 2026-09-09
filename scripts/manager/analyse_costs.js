#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const DEFAULT_LOG = path.resolve('data/logs/decisions.jsonl');
const logPath = path.resolve(process.argv[2] || DEFAULT_LOG);

function readRows(file) {
  return fs.readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line, index) => {
      try { return JSON.parse(line); }
      catch (error) { throw new Error(`${file}:${index + 1}: ${error.message}`); }
    });
}

function percentile(sorted, p) {
  if (!sorted.length) return null;
  const i = Math.min(sorted.length - 1, Math.max(0, Math.ceil(p * sorted.length) - 1));
  return sorted[i];
}

function mean(values) {
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
}

function fmtMs(ms) {
  return ms == null ? '-' : `${(ms / 1000).toFixed(2)}s`;
}
function keyFor(row) {
  return `${row.model || 'unknown'} / ${row.strategy || 'unknown'}`;
}

function usable(row) {
  return !row.provider_error && !(row.validation_errors || []).length && !!row.decision;
}

const rows = readRows(logPath);
const modelRows = rows.filter((row) => row.model && !String(row.model).startsWith('baseline:'));
const groups = new Map();

for (const row of modelRows) {
  const key = keyFor(row);
  if (!groups.has(key)) groups.set(key, []);
  groups.get(key).push(row);
}

console.log(`Decision cost summary: ${path.relative(process.cwd(), logPath)}`);
console.log(`Model decisions: ${modelRows.length} (${rows.length} total log rows)`);
console.log('');

for (const [key, group] of groups) {
  const successes = group.filter(usable);
  const input = successes.map((r) => r.tokens?.input || 0);
  const output = successes.map((r) => r.tokens?.output || 0);
  const decide = successes.map((r) => r.decide_ms ?? r.wall_clock_ms).filter(Number.isFinite);
  const total = successes.map((r) => r.total_ms).filter(Number.isFinite);
  const sortedDecide = [...decide].sort((a, b) => a - b);
  const firstTry = successes.filter((r) => (r.attempts || 1) === 1).length;

  console.log(key);
  console.log(`  usable: ${successes.length}/${group.length}`);
  console.log(`  first-try usable: ${firstTry}/${group.length}`);
  console.log(`  avg tokens: ${mean(input)?.toFixed(0) || '-'} in / ${mean(output)?.toFixed(0) || '-'} out`);
  console.log(`  decision latency: avg ${fmtMs(mean(decide))}, p95 ${fmtMs(percentile(sortedDecide, 0.95))}`);
  if (total.length) console.log(`  full loop latency: avg ${fmtMs(mean(total))}`);

  const failures = group.filter((r) => !usable(r));
  if (failures.length) {
    const reasons = failures.map((r) => r.provider_error || (r.validation_errors || []).join('; '));
    console.log(`  failures: ${reasons.join(' | ')}`);
  }
  console.log('');
}

const latest = modelRows.at(-1);
if (latest) {
  console.log('Latest model decision:');
  console.log(`  ${latest.logged_at || 'unknown time'} — ${keyFor(latest)}`);
  console.log(`  tokens: ${latest.tokens?.input || 0} in / ${latest.tokens?.output || 0} out`);
  console.log(`  decision latency: ${fmtMs(latest.decide_ms ?? latest.wall_clock_ms)}`);
  if (latest.total_ms != null) console.log(`  full loop latency: ${fmtMs(latest.total_ms)}`);
}
