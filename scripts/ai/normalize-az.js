// normalize-az.js
// Azerbaijani-aware text normalization shared by the build pipeline (Node)
// and the runtime search inside index.html (browser). Keep this file's
// logic in sync with the copy embedded in index.html's <script type="module">
// (search for "AZ_FOLD_MAP" there) if you ever change it here.

// Azerbaijani-specific letters folded to their closest ASCII/Latin base,
// so that a user typing without Azerbaijani keys ("nedir" / "sagird")
// still matches text written correctly ("nədir" / "şagird").
const AZ_FOLD_MAP = {
  'ə': 'e', 'Ə': 'e',
  'ı': 'i', 'I': 'i', 'İ': 'i',
  'ö': 'o', 'Ö': 'o',
  'ü': 'u', 'Ü': 'u',
  'ş': 's', 'Ş': 's',
  'ç': 'c', 'Ç': 'c',
  'ğ': 'g', 'Ğ': 'g',
};

const STOPWORDS = new Set([
  've', 'ile', 'ya', 'da', 'de', 'ki', 'bu', 'o', 'bir', 'ne', 'nece',
  'haqqinda', 'ucun', 'kimi', 'amma', 'lakin', 'cunki', 'ise', 'hem',
  'artiq', 'daha', 'cox', 'az', 'yalniz', 'ancaq', 'yeni', 'her', 'butun',
  'olan', 'olub', 'olur', 'edir', 'idi', 'var', 'yox', 'nedir', 'kimdir',
  'haradadir', 'haradir', 'nedendir', 'nezaman', 'necedir',
]);

/**
 * Fold Azerbaijani-specific letters to plain ASCII equivalents.
 * @param {string} str
 * @returns {string}
 */
function foldAzChars(str) {
  let out = '';
  for (const ch of str) out += AZ_FOLD_MAP[ch] ?? ch;
  return out;
}

/**
 * Normalize a string for matching: fold AZ letters, lowercase, strip
 * punctuation, collapse whitespace. Deterministic and locale-independent
 * (does not rely on Node/browser ICU locale casing, which varies).
 * @param {string} str
 * @returns {string}
 */
function normalizeAz(str) {
  if (!str) return '';
  let s = foldAzChars(String(str));
  s = s.toLowerCase();
  s = s.replace(/['’"`]/g, '');
  s = s.replace(/[^a-z0-9\s]/g, ' ');
  s = s.replace(/\s+/g, ' ').trim();
  return s;
}

/**
 * Tokenize a normalized (or raw) string into meaningful keyword tokens,
 * dropping short filler words and common Azerbaijani stopwords.
 * @param {string} str
 * @returns {string[]}
 */
function tokenizeAz(str) {
  const norm = normalizeAz(str);
  if (!norm) return [];
  return norm
    .split(' ')
    .filter((w) => w.length >= 3 && !STOPWORDS.has(w));
}

/**
 * Jaccard-style overlap score between two token sets (0..1).
 * @param {string[]} a
 * @param {string[]} b
 * @returns {number}
 */
function tokenOverlapScore(a, b) {
  if (!a.length || !b.length) return 0;
  const setA = new Set(a);
  const setB = new Set(b);
  let inter = 0;
  for (const t of setA) if (setB.has(t)) inter++;
  const union = setA.size + setB.size - inter;
  return union === 0 ? 0 : inter / union;
}

export { AZ_FOLD_MAP, foldAzChars, normalizeAz, tokenizeAz, tokenOverlapScore, STOPWORDS };
