#!/usr/bin/env node
/**
 * meanings-*.json (ƏL İLƏ yazılmış mənalar)  +  shortlist.json (korpusdan gələn
 * ƏSL nümunə cümlələr)  →  data/corpus/words.json
 *
 * Bölgü aydındır:
 *   • MƏNA  — insan tərəfindən yazılır. Korpusdan avtomatik məna çıxarılmır,
 *             çünki korpus lüğət deyil; uydurma məna SözLab-ın "əminlik
 *             aşağıdırsa cavab uydurma" qaydasını pozardı.
 *   • NÜMUNƏ — korpusdan gəlir, dəyişdirilmir. Yəni şagird sözü əsl
 *             Azərbaycan mətnində gördüyü kimi görür.
 *
 * Təkrarlanmanın qarşısı iki yerdə alınır:
 *   1) burada — mövcud WORDS siyahısı ilə üst-üstə düşən sözlər atılır;
 *   2) index.html-də loadCorpusWords() daxilində — çünki community_words
 *      cədvəli də eyni sözü gətirə bilər.
 */
const fs = require('fs');
const path = require('path');
const DIR = __dirname;
const OUT = path.join(DIR, '../../data/corpus/words.json');

const AZ_LOWER = { 'İ': 'i', 'I': 'ı', 'Ə': 'ə', 'Ö': 'ö', 'Ü': 'ü', 'Ş': 'ş', 'Ç': 'ç', 'Ğ': 'ğ' };
const low = s => s.replace(/[İIƏÖÜŞÇĞ]/g, c => AZ_LOWER[c]).toLowerCase();

const shortlist = JSON.parse(fs.readFileSync(path.join(DIR, 'shortlist.json'), 'utf8'));
const exOf = new Map(shortlist.map(x => [low(x.w), x]));
const existing = new Set(
  JSON.parse(fs.readFileSync(path.join(DIR, 'existing-words.json'), 'utf8')).map(low)
);

const meanings = {};
for (const f of fs.readdirSync(DIR).filter(f => /^meanings-\d+\.json$/.test(f)).sort()) {
  const part = JSON.parse(fs.readFileSync(path.join(DIR, f), 'utf8'));
  let dup = 0;
  for (const [w, v] of Object.entries(part)) {
    if (meanings[w]) dup++;
    meanings[w] = v;
  }
  console.log('  ', f, Object.keys(part).length, 'söz', dup ? `(${dup} təkrar)` : '');
}

const out = [];
const seen = new Set();
const noExample = [];
const alreadyIn = [];

for (const [w, v] of Object.entries(meanings)) {
  const key = low(w);
  if (existing.has(key)) { alreadyIn.push(w); continue; }   // SözLab-da artıq var
  if (seen.has(key)) continue;                               // fayllar arası təkrar
  const src = exOf.get(key);
  if (!src) { noExample.push(w); continue; }                 // korpusda nümunə yoxdur
  seen.add(key);
  const [az, tag, difficulty] = v;
  out.push({
    en: w,
    az,
    ex: src.ex,
    exAz: '',
    tags: ['Korpus', tag],
    difficulty: difficulty || 2
  });
}

out.sort((a, b) => a.en.localeCompare(b.en, 'az'));
fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, JSON.stringify(out));

console.log('\n── LÜĞƏT ──');
console.log('yazılmış məna      :', Object.keys(meanings).length);
console.log('artıq lüğətdə var  :', alreadyIn.length, alreadyIn.slice(0, 12).join(', '));
console.log('korpusda nümunə yox:', noExample.length, noExample.slice(0, 20).join(', '));
console.log('→ words.json       :', out.length, 'söz,',
  (fs.statSync(OUT).size / 1024).toFixed(0) + ' KB');
