// build-ai-db.js
//
// One-time / re-runnable BUILD step (Node.js, run manually with
// `node scripts/ai/build-ai-db.js`). It is NOT shipped to the browser.
// It reads the three raw datasets below, cleans + normalizes + dedupes
// them, and writes the compact runtime file the app actually fetches:
//   data/ai/qa.json
//
// Raw sources expected (see scripts/ai/README.md for where to get them):
//   data/ai/raw/LDQuAd.parquet        (LocalDoc/LDQuAd, HF, 154,198 rows)
//   data/ai/raw/LDQuAd_v2.parquet     (LocalDoc/LDQuAd_v2, HF, 351,000 rows)
//   data/ai/raw/az_corpus-v1.0.json   (az_corpus v1.0, 4,983 rows)
//
// Parquet is read with a vendored copy of hyparquet (MIT, zero
// dependencies) since this sandbox has no network access to npm/PyPI
// registries to install pyarrow/parquetjs — see vendor/hyparquet-LICENSE.

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { parquetReadObjects } from './vendor/hyparquet/index.js';
import { normalizeAz, tokenizeAz } from './normalize-az.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..', '..'); // /root/work/sozlab
const RAW_DIR = path.join(ROOT, 'data', 'ai', 'raw');
const OUT_DIR = path.join(ROOT, 'data', 'ai');

const MAX_ANSWER_LEN = 600; // keep entries compact; longer answers get trimmed at a sentence boundary
const MIN_QUESTION_LEN = 4;

async function readParquetRows(filePath) {
  const buf = await readFile(filePath);
  const asyncBuf = {
    byteLength: buf.byteLength,
    slice: (start, end) => buf.buffer.slice(buf.byteOffset + start, buf.byteOffset + (end ?? buf.byteLength)),
  };
  return parquetReadObjects({ file: asyncBuf });
}

function trimAnswer(text) {
  if (!text) return text;
  let t = String(text).trim();
  if (t.length <= MAX_ANSWER_LEN) return t;
  const cut = t.slice(0, MAX_ANSWER_LEN);
  const lastDot = Math.max(cut.lastIndexOf('. '), cut.lastIndexOf('.'));
  return (lastDot > MAX_ANSWER_LEN * 0.5 ? cut.slice(0, lastDot + 1) : cut) + '…';
}

function buildKeywords(question, extra = []) {
  const toks = new Set(tokenizeAz(question));
  for (const e of extra) for (const t of tokenizeAz(e)) toks.add(t);
  return [...toks].slice(0, 12);
}

// ---- 1. az_corpus-v1.0 (highest quality: curated structured Q&A) ----
async function loadAzCorpus() {
  const raw = await readFile(path.join(RAW_DIR, 'az_corpus-v1.0.json'), 'utf-8');
  // The upstream dump has a recurring bug: a stray bare number is spliced
  // in between some records ("...}\n2,\n    {..."), which breaks JSON
  // parsing. Repair every occurrence before parsing.
  const fixed = raw.replace(/\}\s*\n\d+,\s*\n\s*\{/g, '},\n    {');
  const entries = JSON.parse(fixed);
  const out = [];
  for (const e of entries) {
    const qas = e?.structured_response?.questions_and_answers;
    if (!Array.isArray(qas)) continue;
    for (const qa of qas) {
      const question = qa.question?.trim();
      const answer = (qa.short_answer || qa.long_structured_answer || '').trim();
      if (!question || !answer) continue;
      out.push({
        question,
        answer: trimAnswer(answer),
        category: e.category || 'ümumi',
        topic: e.topic || '',
        keywordHints: e.keywords || [],
        source: 'az_corpus',
        confidence: 1,
      });
    }
  }
  return out;
}

// ---- 2. LDQuAd_v2 (full-sentence, AI-assisted answers) ----
// 351k rows cluster around only ~4.7k Wikipedia-style topics (median 39
// questions per topic, one topic has 1,891!). A static site can't ship
// that much redundancy, so we cap how many questions survive per topic —
// this is the single biggest lever on final file size.
const MAX_PER_TOPIC_V2 = 5;

async function loadLDQuAdV2() {
  const rows = await readParquetRows(path.join(RAW_DIR, 'LDQuAd_v2.parquet'));
  const perTopicCount = new Map();
  const out = [];
  for (const r of rows) {
    const question = r.question?.trim();
    const answer = r.answer?.trim();
    if (!question || !answer || question.length < MIN_QUESTION_LEN) continue;
    const topic = r.title || '';
    const n = perTopicCount.get(topic) || 0;
    if (n >= MAX_PER_TOPIC_V2) continue;
    perTopicCount.set(topic, n + 1);
    out.push({
      question,
      answer: trimAnswer(answer),
      category: 'ümumi',
      topic,
      keywordHints: topic ? [topic] : [],
      source: 'ldquad_v2',
      confidence: 0.9,
    });
  }
  return out;
}

// ---- 3. LDQuAd (SQuAD-style extractive spans; ~30% unanswerable, skip those) ----
async function loadLDQuAd() {
  const rows = await readParquetRows(path.join(RAW_DIR, 'LDQuAd.parquet'));
  const out = [];
  for (const r of rows) {
    const question = r.question?.trim();
    const answer = r.answer_text?.trim();
    const start = typeof r.answer_start === 'bigint' ? Number(r.answer_start) : r.answer_start;
    if (!question || !answer || answer === 'no_answer' || start < 0 || question.length < MIN_QUESTION_LEN) continue;
    out.push({
      question,
      answer: trimAnswer(answer),
      category: 'ümumi',
      topic: r.title || '',
      keywordHints: r.title ? [r.title] : [],
      source: 'ldquad',
      confidence: 0.7, // short extractive phrase, not always a full sentence
    });
  }
  return out;
}

async function main() {
  console.log('Reading az_corpus-v1.0 (curated structured QA)...');
  const azCorpus = await loadAzCorpus();
  console.log('  ->', azCorpus.length, 'QA pairs');

  console.log('Reading LDQuAd_v2 (351k parquet)...');
  const v2 = await loadLDQuAdV2();
  console.log('  ->', v2.length, 'QA pairs (after dropping null answers)');

  // LDQuAd (v1) is parsed and available (loadLDQuAd, below) but excluded
  // from the default build: its answers are short SQuAD-style extractive
  // spans copy-pasted out of a passage ("Şərqi Avropa və Qərbi Asiyanın"),
  // not full sentences — lower quality than LDQuAd_v2 for a chat-style
  // assistant, and it covers much the same Wikipedia topic space. Flip
  // INCLUDE_LDQUAD_V1 on if broader (lower-quality) coverage is wanted.
  const INCLUDE_LDQUAD_V1 = false;
  let v1 = [];
  if (INCLUDE_LDQUAD_V1) {
    console.log('Reading LDQuAd (154k parquet)...');
    v1 = await loadLDQuAd();
    console.log('  ->', v1.length, 'QA pairs (after dropping no_answer)');
  }

  // Priority order for de-duplication when the same question appears in
  // more than one source: curated az_corpus > full-sentence LDQuAd_v2 > span-only LDQuAd
  const all = [...azCorpus, ...v2, ...v1];
  console.log('Total before dedup:', all.length);

  const seen = new Map(); // normalized_question -> record
  for (const rec of all) {
    const norm = normalizeAz(rec.question);
    if (!norm || norm.length < MIN_QUESTION_LEN) continue;
    if (seen.has(norm)) continue; // first occurrence wins (priority order above)
    seen.set(norm, rec);
  }
  console.log('Total after dedup:', seen.size);

  const final = [];
  let i = 1;
  for (const [norm, rec] of seen) {
    // `tt` (topic tokens) exists to stop the runtime matcher confusing two
    // records that share a generic question template ("X hansı ölkələrlə
    // həmsərhəddir?" is asked about ~4,700 different places in LDQuAd_v2).
    // The runtime requires at least one of these to appear in the user's
    // message before it will accept a fuzzy (non-exact) match — otherwise
    // "Azərbaycanın paytaxtı nədir?" can match a Washington D.C. record
    // purely because both share the word "paytaxtı". See index.html's
    // qaSearch for the matching half of this contract.
    final.push({
      id: 'az-' + String(i++).padStart(6, '0'),
      question: rec.question,
      normalized_question: norm,
      answer: rec.answer,
      category: rec.category,
      topic: rec.topic,
      keywords: buildKeywords(rec.question, rec.keywordHints),
      tt: rec.topic ? tokenizeAz(rec.topic) : [],
      confidence: rec.confidence,
      src: rec.source,
    });
  }

  await mkdir(OUT_DIR, { recursive: true });
  const outPath = path.join(OUT_DIR, 'qa.json');
  const json = JSON.stringify(final);
  await writeFile(outPath, json, 'utf-8');
  console.log('Wrote', final.length, 'records to', outPath, '(', (json.length / 1024 / 1024).toFixed(2), 'MB )');

  // Small companion file: category/topic list, for potential future UI filters.
  const categories = [...new Set(final.map((r) => r.category).filter(Boolean))].sort();
  await writeFile(path.join(OUT_DIR, 'topics.json'), JSON.stringify({ categories }, null, 2), 'utf-8');
  console.log('Wrote topics.json (', categories.length, 'categories )');
}

main().catch((e) => {
  console.error('BUILD FAILED:', e.stack);
  process.exit(1);
});
