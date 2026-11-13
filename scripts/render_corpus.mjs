/* Render a directory of Markdown documents with the library compiled to
   JavaScript, and print what it made of each: the HTML, the Markdown it writes
   back, and the HTML with typographic punctuation on. Used by
   scripts/compare_cmark.py, which puts those next to what the reference
   implementation makes of the same file.

   Usage: node scripts/render_corpus.mjs <engine.js> <directory> */

import { readFileSync, readdirSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [enginePath, directory] = process.argv.slice(2);
if (!enginePath || !directory) {
  console.error("usage: node scripts/render_corpus.mjs <engine.js> <directory>");
  process.exit(2);
}

const engine = await import(pathToFileURL(enginePath).href);
const rendered = {};
for (const name of readdirSync(directory).sort()) {
  if (!name.endsWith(".md")) continue;
  const text = readFileSync(join(directory, name), "utf8");
  rendered[name] = {
    html: engine.html(text, "gfm", false),
    markdown: engine.markdown(text, "gfm"),
    smart: engine.html(text, "smart", false)
  };
}
process.stdout.write(JSON.stringify(rendered));
