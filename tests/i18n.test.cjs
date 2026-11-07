// Every text the plugin can show has an English entry and a Norwegian one with
// the same placeholders: literals passed to FoamyI18n (the plugin's and the
// synced kit components'), and the texts passed through as data (ticket
// statuses and priorities, day names, settings errors and the helper's errors).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const en = require('../i18n/en.json');
const no = require('../i18n/no.json');
const Schema = require('../Preferences.js');

const root = path.join(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const files = (dir, ext) => fs.readdirSync(path.join(root, dir)).filter(f => ext.some(e => f.endsWith(e))).map(f => path.join(dir, f));
const tokens = s => [...String(s).matchAll(/%[1-9][0-9]*|\{\w+\}/g)].map(m => m[0]).sort();
const forms = v => (typeof v === 'string' ? [v] : Object.values(v));
// Comments hold usage examples, not shown texts.
const code = source => source.split('\n').filter(line => !/^\s*(\/\/|\*|\/\*)/.test(line)).join('\n');

function literals() {
  const found = [];
  const sources = files('.', ['.qml', '.js']).concat(files('kit', ['.qml', '.js']));
  for (const file of sources) {
    for (const [, fn, key] of code(read(file)).matchAll(/FoamyI18n\.(tn?)\("((?:[^"\\]|\\.)*)"/g))
      found.push({ file, fn, key: JSON.parse(`"${key}"`) });
    // The kit's FoamyI18n calls its own t/tn.
    if (file.endsWith('FoamyI18n.qml'))
      for (const [, fn, key] of code(read(file)).matchAll(/\breturn (tn?)\("((?:[^"\\]|\\.)*)"/g)) found.push({ file, fn, key });
  }
  return found;
}

function helperKeys() {
  // Each file's test module (at its end) uses its own texts.
  const rust = files('native/src', ['.rs']).map(file => read(file).split(/#\[cfg\(test\)\]\s*mod tests/)[0]).join('\n');
  const keys = new Set();
  const patterns = [
    /Failure::coded\(\s*"[A-Z_]+",\s*"((?:[^"\\]|\\.)*)"/g,
    /text::message\(\s*"((?:[^"\\]|\\.)*)"/g,
    /invalid\(\s*"((?:[^"\\]|\\.)*)"/g,
  ];
  for (const pattern of patterns) for (const [, key] of rust.matchAll(pattern)) keys.add(JSON.parse(`"${key}"`));
  for (const [, key] of rust.matchAll(/"KEYRING_UNAVAILABLE",[\s\S]*?"((?:[^"\\]|\\.)*)"\.to_string\(\)/g)) keys.add(key);
  // Messages named by a constant, the plugin's own or the vendored kit's
  // (`tls::UNSUPPORTED`): the catalog must follow the kit's text.
  for (const [, modules, name] of rust.matchAll(/Failure::coded\(\s*"[A-Z_]+",\s*((?:[a-z_]+::)*)([A-Z][A-Z0-9_]*)\s*,?\s*\)/g)) {
    const text = messageConstant(modules, name);
    assert.ok(text !== undefined, `helper message constant not found: ${modules}${name}`);
    keys.add(text);
  }
  // The usage line answers only a wrong command line, never shown in the panel.
  return [...keys].filter(key => !key.startsWith('usage:'));
}

// `const NAME: &str = "…"` in the module its path names (`tls::` is the
// helper's own module of that name or the vendored kit's), else anywhere in
// the helper's sources.
function messageConstant(modules, name) {
  const module = modules.split('::').filter(m => m && m !== 'crate' && m !== 'foamy_helper').pop();
  const candidates = module
    ? [`native/src/${module}.rs`, `kit/rust/foamy-helper/src/${module}.rs`]
    : files('native/src', ['.rs']);
  for (const file of candidates.filter(f => fs.existsSync(path.join(root, f)))) {
    const found = read(file).match(new RegExp(`\\bconst ${name}: &str = "((?:[^"\\\\]|\\\\.)*)";`));
    if (found) return JSON.parse(`"${found[1]}"`);
  }
  return undefined;
}

function dataKeys() {
  const tickets = read('native/src/tickets.rs');
  const mapped = name => [...tickets.match(new RegExp(`fn ${name}\\([\\s\\S]*?\\n}`))[0].matchAll(/=> "([^"]+)"/g)].map(m => m[1]);
  const prefs = read('kit/FoamyPrefs.js');
  const queue = read('kit/FoamyPrefsQueue.qml');
  return [
    ...mapped('status'), ...mapped('priority'),
    ...Schema.dayLabels,
    read('kit/FoamyNative.js').match(/UNAVAILABLE_TEXT = "([^"]+)"/)[1],
    ...[...prefs.matchAll(/^var [A-Z_]+ = "([^"]+)"/gm)].map(m => m[1]),
    ...[...queue.matchAll(/error = "([^"]+)"/g)].map(m => m[1]),
  ];
}

test('the English catalog lists source keys; Norwegian has every entry with the same placeholders', () => {
  for (const [key, value] of Object.entries(en)) {
    if (typeof value === 'string') assert.equal(value, key, `English source key: ${key}`);
    else assert.ok(typeof value.one === 'string' && typeof value.other === 'string', `English plural: ${key}`);
    assert.ok(Object.hasOwn(no, key), `Norwegian entry: ${key}`);
    assert.equal(typeof no[key], typeof value, `same entry shape: ${key}`);
    for (const form of forms(no[key])) {
      assert.ok(form.length > 0, `Norwegian text: ${key}`);
      assert.deepEqual(tokens(form), tokens(key), `placeholders: ${key}`);
    }
  }
  assert.deepEqual(Object.keys(no).sort(), Object.keys(en).sort(), 'no extra Norwegian entries');
});

test('every literal shown through FoamyI18n has an entry; tn keys are plural entries', () => {
  const found = literals();
  assert.ok(found.length > 80, `literals found: ${found.length}`);
  for (const { file, fn, key } of found) {
    assert.ok(Object.hasOwn(en, key), `missing catalog key (${file}): ${key}`);
    if (fn === 'tn') assert.equal(typeof en[key], 'object', `tn key needs a plural entry: ${key}`);
  }
});

test('texts passed as data are catalog keys too', () => {
  const keys = dataKeys();
  assert.ok(keys.includes('On-hold') && keys.includes('Urgent') && keys.includes('Sunday'), keys.join(', '));
  for (const key of keys) assert.ok(Object.hasOwn(en, key), `missing data key: ${key}`);
});

test("the helper's errors are catalog keys", () => {
  const keys = helperKeys();
  assert.ok(keys.length >= 20, `helper keys found: ${keys.length}`);
  for (const key of keys) assert.ok(Object.hasOwn(en, key), `missing helper key: ${key}`);
});

test('every entry is used', () => {
  const used = new Set([...literals().map(l => l.key), ...dataKeys(), ...helperKeys()]);
  for (const key of Object.keys(en)) assert.ok(used.has(key), `unused catalog key: ${key}`);
});
