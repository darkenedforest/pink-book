import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { exportContent, readAssignment } from '../tools/export-content.mjs';

const repo = fileURLToPath(new URL('../../', import.meta.url));
const html = (...path) => readFileSync(join(repo, ...path), 'utf8');

test('exports every book and preserves all story annotations', t => {
  const dest = mkdtempSync(join(tmpdir(), 'pink-book-export-'));
  t.after(() => rmSync(dest, { recursive: true, force: true }));
  const catalog = exportContent(repo, dest);
  const read = file => JSON.parse(readFileSync(join(dest, file), 'utf8'));

  assert.deepEqual(read('catalog.json'), catalog);
  const stories = catalog.books;
  const [kirihama] = stories;
  assert.deepEqual(catalog.books.map(b => b.id), ['kirihama', 'shadow-shop', 'last-train']);
  assert.deepEqual(stories.map(b => b.title), ['霧浜の秘密', '影の店', '最終電車']);
  assert.match(kirihama.synopsis, /Kirihama/);
  assert.equal(kirihama.chapters[0].title, '霧の中の民宿');
  assert.equal(kirihama.chapters[0].subtitle, 'The Guesthouse in the Mist');
  assert.deepEqual(
    readdirSync(dest).sort(),
    ['catalog.json', ...catalog.books.flatMap(b => b.chapters.map(c => c.file))].sort()
  );
  const expectedCounts = { kirihama: 12388, 'shadow-shop': 13730, 'last-train': 9942 };
  for (const story of stories) {
    assert.equal(story.cover, story.id + '-cover.png');
    assert.ok(readdirSync(join(repo, 'bookshelf')).includes(story.cover));
    assert.deepEqual(story.chapters.map(c => c.id), Array.from({ length: 20 }, (_, i) =>
      'ep' + String(i + 1).padStart(2, '0')));
    assert.deepEqual(
      readdirSync(join(repo, story.id)).filter(file => /^ep\d+\.html$/.test(file)).sort(),
      story.chapters.map(c => c.id + '.html').sort()
    );

    let sum = 0;
    for (const chapter of story.chapters) {
      assert.equal(chapter.file, `${story.id}-${chapter.id}.json`);
      const original = JSON.parse(html(story.id, chapter.id + '.html')
        .match(/^var sentences = (\[[\s\S]*?\]);$/m)[1]);
      const output = read(chapter.file);
      assert.equal(output.length, original.length, chapter.id);
      assert.equal(chapter.sentenceCount, output.length, chapter.id);
      for (const [index, sentence] of original.entries()) {
        const actual = output[index];
        assert.equal(actual.translation, sentence.trans);
        assert.equal(actual.hiragana, sentence.hira);
        assert.equal(actual.speaker, sentence.speaker || undefined);
        assert.equal(Boolean(actual.sceneBreak), Boolean(sentence._scene_break_before || original[index - 1]?._scene_break));
        assert.deepEqual(actual.parts, sentence.parts.map(item => {
          if ('p' in item) return { kind: 'plain', text: item.p };
          const isGrammar = 'g' in item;
          return {
            kind: isGrammar ? 'grammar' : 'word',
            text: isGrammar ? item.g : item.w,
            reading: item.r,
            meaning: item.m,
            ...('x' in item ? { explanation: item.x } : {}),
            ...('core' in item ? { core: item.core } : {})
          };
        }));
      }
      sum += output.length;
    }
    assert.equal(sum, expectedCounts[story.id]);
  }

});

test('extraction handles escaped quotes, JSON brackets, and rejects non-JSON data', () => {
  const source = `var books = ${JSON.stringify([{ title: 'A quote: " and a ]' }])};`;
  assert.deepEqual(readAssignment(source, 'books'), [{ title: 'A quote: " and a ]' }]);
  assert.throws(() => readAssignment('var books = [W("run")];', 'books'), SyntaxError);
  assert.throws(() => readAssignment('var books = [] + [];', 'books'), /semicolon/);
});
