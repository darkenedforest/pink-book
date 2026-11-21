// Compile the existing reader's data into native, offline JSON resources.
// Books and chapter arrays are strictly parsed as JSON, never executed.
import { mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export function readAssignment(html, name) {
  const names = ['books', 'sentences'];
  if (!names.includes(name)) throw new Error('Unknown data assignment');
  const match = html.match(new RegExp(`^\\s*(?:var|let|const)\\s+${name}\\s*=\\s*`, 'm'));
  if (!match) throw new Error(`No ${name} data assignment found`);
  const source = html.slice(match.index + match[0].length);
  // Find a complete, strictly JSON array without assuming one element per line.
  if (!source.startsWith('[')) throw new SyntaxError(`Expected an array for ${name}`);
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let i = 0; i < source.length; i++) {
    const c = source[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (c === '\\') escaped = true;
      else if (c === '"') inString = false;
    } else if (c === '"') inString = true;
    else if (c === '[') depth++;
    else if (c === ']' && --depth === 0) {
      if (!/^\s*;/.test(source.slice(i + 1))) throw new SyntaxError('Expected semicolon after array');
      return JSON.parse(source.slice(0, i + 1));
    }
  }
  throw new SyntaxError(`Unterminated ${name} array`);
}

const entities = Object.freeze({ amp: '&', apos: "'", quot: '"', lt: '<', gt: '>', nbsp: '\u00a0' });
const htmlText = value => value.replace(/&(amp|apos|quot|lt|gt|nbsp|#\d+|#x[\da-f]+);/gi, (full, entity) => {
  if (entity[0] !== '#') return entities[entity.toLowerCase()] ?? full;
  const codePoint = entity[1].toLowerCase() === 'x' ? parseInt(entity.slice(2), 16) : Number(entity.slice(1));
  return codePoint > 0 && codePoint <= 0x10ffff ? String.fromCodePoint(codePoint) : full;
});

function normalizeSentence(source, sceneBreak) {
  if (!Array.isArray(source.parts) || source.parts.length === 0 || typeof source.hira !== 'string') {
    throw new Error('Malformed sentence data');
  }
  const sentence = {
    parts: source.parts.map(item => {
      if (typeof item.p === 'string') return { kind: 'plain', text: htmlText(item.p) };
      const kind = typeof item.g === 'string' ? 'grammar' : typeof item.w === 'string' ? 'word' : '';
      if (!kind || typeof item.r !== 'string') throw new Error('Malformed annotated word');
      const part = { kind, text: kind === 'word' ? item.w : item.g, reading: item.r };
      if (typeof item.m !== 'string') throw new Error('Malformed meaning');
      part.meaning = item.m;
      if (item.x !== undefined) part.explanation = item.x;
      if (item.core !== undefined) part.core = Boolean(item.core);
      return part;
    }),
    hiragana: source.hira
  };
  if (typeof source.trans !== 'string') throw new Error('Malformed translation');
  sentence.translation = source.trans;
  if (source.speaker) sentence.speaker = source.speaker;
  if (sceneBreak || source._scene_break_before) sentence.sceneBreak = true;
  return sentence;
}

export function exportContent(repoRoot, outputDirectory) {
  const read = (...path) => readFileSync(join(repoRoot, ...path), 'utf8');
  const bookshelf = readAssignment(read('bookshelf', 'index.html'), 'books');
  if (!Array.isArray(bookshelf) || !bookshelf.length) throw new Error('The bookshelf is empty');
  mkdirSync(outputDirectory, { recursive: true });
  const write = (file, data) => writeFileSync(join(outputDirectory, file), JSON.stringify(data) + '\n', 'utf8');
  const bookIds = new Set();
  const catalog = { books: [] };

  function checkIndex(folder, chapters, sourcePattern) {
    const indexed = chapters.map(chapter => chapter.id + '.html');
    const available = readdirSync(join(repoRoot, folder)).filter(file => sourcePattern.test(file)).sort();
    if (!indexed.length || new Set(indexed).size !== indexed.length ||
        [...indexed].sort().join('\n') !== available.join('\n')) {
      throw new Error(`The ${folder} contents index does not match its source chapters`);
    }
  }

  for (const book of bookshelf) {
    if (typeof book.id !== 'string' || !/^[a-z][a-z0-9-]*$/.test(book.id) || bookIds.has(book.id) ||
        book.url !== `../${book.id}/index.html` || !/^[a-z0-9-]+\.png$/i.test(book.cover) ||
        typeof book.title_jp !== 'string' || typeof book.title_en !== 'string') {
      throw new Error(`Invalid or duplicate book metadata: ${book.id}`);
    }
    bookIds.add(book.id);
    const chapterIndex = read(book.id, 'index.html');
    const chapters = [...chapterIndex.matchAll(/<a class="episode-link" href="(ep\d+)\.html">([\s\S]*?)<\/a>/g)]
      .map(([, id, link]) => {
        const title = link.match(/class="ep-title-jp">([^<]+)/)?.[1];
        const subtitle = link.match(/class="ep-title-en">([^<]+)/)?.[1];
        if (!title || !subtitle) throw new Error(`Missing chapter title for ${book.id}/${id}`);
        return { id, title: htmlText(title.trim()), subtitle: htmlText(subtitle.trim()), file: `${book.id}-${id}.json` };
      });
    checkIndex(book.id, chapters, /^ep\d+\.html$/);
    for (const chapter of chapters) {
      try {
        const sentences = readAssignment(read(book.id, `${chapter.id}.html`), 'sentences');
        if (sentences.length === 0) throw new Error('No sentences');
        chapter.sentenceCount = sentences.length;
        write(chapter.file, sentences.map((sentence, i) => normalizeSentence(sentence, sentences[i - 1]?._scene_break)));
      } catch (error) {
        throw new Error(`Cannot export ${book.id}/${chapter.id}: ${error.message}`, { cause: error });
      }
    }
    catalog.books.push({ id: book.id, title: book.title_jp, subtitle: book.title_en,
                         synopsis: book.synopsis, cover: book.cover, chapters });
  }

  write('catalog.json', catalog);
  return catalog;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const [repo, destination] = process.argv.slice(2);
  if (!repo || !destination) {
    console.error('Usage: node export-content.mjs <repo-root> <output-directory>');
    process.exitCode = 2;
  } else {
    exportContent(repo, destination);
  }
}
