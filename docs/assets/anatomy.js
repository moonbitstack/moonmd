/* The anatomy page: every panel is drawn from what the library returns. The
   script picks which call to make and where to put the answer; it parses
   nothing itself. */

(function () {
  "use strict";

  var sourceList = document.getElementById("source");
  if (!sourceList) return;

  var treeBox = document.getElementById("tree");
  var treeNote = document.getElementById("tree-note");
  var sourceNote = document.getElementById("source-note");
  var outBox = document.getElementById("out");
  var outLabel = document.getElementById("out-label");
  var outNote = document.getElementById("out-note");
  var gfmBox = document.getElementById("as-gfm");
  var commonmarkBox = document.getElementById("as-commonmark");
  var flavorNote = document.getElementById("flavor-note");
  var ruler = document.getElementById("ruler");
  var scrub = document.getElementById("scrub");
  var settleNote = document.getElementById("settle-note");
  var settleCount = document.getElementById("settle-count");
  var settled = document.getElementById("settled");
  var chips = document.querySelectorAll(".chip[data-specimen]");

  var SPECIMENS = {
    prose: [
      "# A specimen",
      "",
      "A *paragraph* with **weight**, a [link](/a \"title\"), `code`,",
      "and an entity: &amp;. Two lines make one block.",
      "",
      "> A quote holds blocks.",
      ">",
      "> - and a list",
      "> - inside it",
      ""
    ].join("\n"),
    list: [
      "- [x] read the block phase",
      "- [ ] read the inline phase",
      "",
      "  a paragraph inside the second item",
      "",
      "1. ordered",
      "2. again",
      "   - nested",
      ""
    ].join("\n"),
    table: [
      "| mark | what it holds |",
      "|:-----|--------------:|",
      "| `**` | strong |",
      "| `[]` | a link |",
      ""
    ].join("\n"),
    notes: [
      "A claim that wants a source[^paper], and another[^book].",
      "",
      "[^paper]: The tree is the document.",
      "[^book]: Read a chunk at a time.",
      ""
    ].join("\n"),
    edges: [
      "Setext heading",
      "==============",
      "",
      "    indented code",
      "",
      "<div>raw html</div>",
      "",
      "~~struck~~ and https://example.com and \\*escaped\\*",
      ""
    ].join("\n")
  };

  // A block that points somewhere else in the document cannot show what it
  // points at once it is read on its own; say so rather than look wrong.
  var BLOCK_NOTES = {
    notes:
      "A reference points at a definition elsewhere in the document, so a paragraph shown on its own keeps the reference as text."
  };

  var asked = new URLSearchParams(location.search).get("s");
  var engine = null;
  var specimen = asked && SPECIMENS[asked] ? asked : "prose";
  var blocks = [];
  var picked = -1;
  var steps = [];

  function text(source) {
    return source;
  }

  /* ---------- the source, with its numbers ---------- */

  function paintSource() {
    var lines = text(SPECIMENS[specimen]).split("\n");
    if (lines.length && lines[lines.length - 1] === "") lines.pop();
    sourceList.textContent = "";
    for (var i = 0; i < lines.length; i++) {
      var row = document.createElement("li");
      row.dataset.line = String(i + 1);
      var n = document.createElement("span");
      n.className = "n";
      n.textContent = String(i + 1);
      var t = document.createElement("span");
      t.className = "t";
      t.textContent = lines[i] === "" ? " " : lines[i];
      row.appendChild(n);
      row.appendChild(t);
      row.addEventListener("click", pickLine);
      sourceList.appendChild(row);
    }
    sourceNote.textContent =
      lines.length + (lines.length === 1 ? " line" : " lines") +
      (blocks.length ? " · " + blocks.length + (blocks.length === 1 ? " block" : " blocks") : "");
  }

  function pickLine(event) {
    var line = Number(event.currentTarget.dataset.line);
    for (var i = 0; i < blocks.length; i++) {
      if (blocks[i].lines && line >= blocks[i].lines[0] && line <= blocks[i].lines[1]) {
        select(i);
        return;
      }
    }
    select(-1);
  }

  function markLines(first, last) {
    var rows = sourceList.querySelectorAll("li");
    for (var i = 0; i < rows.length; i++) {
      var line = i + 1;
      rows[i].classList.toggle("on", first > 0 && line >= first && line <= last);
    }
  }

  /* ---------- the tree ---------- */

  function buildNode(item, index) {
    var li = document.createElement("li");
    var label = document.createElement("span");
    label.className = "type";
    label.textContent = item.type;
    li.appendChild(label);
    if (item.detail) {
      var detail = document.createElement("span");
      detail.className = "detail";
      detail.textContent = "  " + item.detail;
      li.appendChild(detail);
    }
    if (item.children && item.children.length) {
      var count = document.createElement("span");
      count.className = "count";
      count.textContent = String(item.children.length);
      li.appendChild(count);
      var ul = document.createElement("ul");
      for (var i = 0; i < item.children.length; i++) {
        ul.appendChild(buildNode(item.children[i], -1));
      }
      li.appendChild(ul);
    }
    if (index >= 0) {
      li.dataset.index = String(index);
      li.classList.add("pick");
      li.setAttribute("role", "button");
      li.setAttribute("tabindex", "0");
      li.addEventListener("click", function (event) {
        event.stopPropagation();
        select(index);
      });
      li.addEventListener("keydown", function (event) {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          select(index);
        }
      });
    }
    return li;
  }

  function paintTree() {
    var tree = JSON.parse(engine.tree(SPECIMENS[specimen], "gfm"));
    blocks = tree.children || [];
    var top = document.createElement("ul");
    for (var i = 0; i < blocks.length; i++) {
      top.appendChild(buildNode(blocks[i], i));
    }
    treeBox.textContent = "";
    treeBox.appendChild(top);
    var inlines = 0;
    var walk = function (item) {
      (item.children || []).forEach(function (child) {
        if (child.type !== "Item" && child.type !== "Row" && child.type !== "Cell") inlines += 1;
        walk(child);
      });
    };
    walk(tree);
    treeNote.textContent = blocks.length + " at the top · " + inlines + " below";
  }

  function markTree() {
    var items = treeBox.querySelectorAll("li.pick");
    for (var i = 0; i < items.length; i++) {
      items[i].classList.toggle("sel", Number(items[i].dataset.index) === picked);
    }
  }

  /* ---------- what a block becomes ---------- */

  function htmlOf(flavor, index) {
    var source = SPECIMENS[specimen];
    if (index < 0) return engine.html(source, flavor, false);
    return engine.block(source, flavor, index);
  }

  function paintOut() {
    var html = htmlOf("gfm", picked);
    outBox.innerHTML = window.moonmdColor("html", html.replace(/\n$/, ""));
    if (picked < 0) {
      outLabel.textContent = "the whole document";
      outNote.textContent = "as html";
    } else {
      var span = blocks[picked].lines;
      outLabel.textContent = blocks[picked].type + " · block " + (picked + 1);
      outNote.textContent = span ? "lines " + span[0] + "–" + span[1] + ", as html" : "as html";
    }
  }

  function paintFlavors() {
    var gfm = htmlOf("gfm", picked);
    var plain = htmlOf("commonmark", picked);
    gfmBox.innerHTML = window.moonmdColor("html", gfm.replace(/\n$/, ""));
    commonmarkBox.innerHTML = window.moonmdColor("html", plain.replace(/\n$/, ""));
    var same = gfm === plain;
    if (same && picked >= 0 && BLOCK_NOTES[specimen]) {
      flavorNote.textContent = BLOCK_NOTES[specimen];
      return;
    }
    flavorNote.textContent = same
      ? "This block reads the same in both flavors: nothing here is an extension."
      : "The two differ: what this block uses is an extension, and commonmark leaves it as text.";
  }

  /* ---------- when a block settles ---------- */

  function paintTimeline() {
    steps = JSON.parse(engine.stream(SPECIMENS[specimen], "gfm", 3));
    ruler.textContent = "";
    var total = SPECIMENS[specimen].length || 1;
    var last = 0;
    for (var i = 0; i < steps.length; i++) {
      var mark = document.createElement("span");
      mark.className = "tick";
      mark.style.left = Math.min(100, (steps[i].at / total) * 100) + "%";
      mark.style.height = 8 + Math.min(22, steps[i].blocks * 4) + "px";
      mark.title = steps[i].blocks + " block(s) settle here";
      ruler.appendChild(mark);
      last = steps[i].at;
    }
    var end = document.createElement("span");
    end.className = "tick end";
    end.style.left = "100%";
    ruler.appendChild(end);
    scrub.max = String(steps.length);
    scrub.value = String(steps.length);
    paintSettled(steps.length);
    return last;
  }

  function paintSettled(count) {
    var source = SPECIMENS[specimen];
    settled.textContent = "";
    var html = "";
    var at = 0;
    var blocksSettled = 0;
    for (var i = 0; i < count && i < steps.length; i++) {
      html += steps[i].html;
      at = steps[i].at;
      blocksSettled += steps[i].blocks;
    }
    settled.innerHTML = html;
    var lines = source.slice(0, at).split("\n").length - 1;
    if (count === 0) lines = 0;
    if (count >= steps.length) lines = source.split("\n").length;
    settleNote.textContent =
      count === 0
        ? "nothing arrived yet"
        : "after " + at + " of " + source.length + " characters, " + lines + " lines in";
    settleCount.textContent =
      blocksSettled + (blocksSettled === 1 ? " block settled" : " blocks settled");
    var rows = sourceList.querySelectorAll("li");
    for (var j = 0; j < rows.length; j++) {
      rows[j].classList.toggle("done", j < lines);
    }
  }

  /* ---------- selection ---------- */

  function select(index) {
    picked = index;
    markTree();
    if (index < 0) {
      markLines(0, 0);
    } else if (blocks[index] && blocks[index].lines) {
      markLines(blocks[index].lines[0], blocks[index].lines[1]);
    } else {
      markLines(0, 0);
    }
    paintOut();
    paintFlavors();
  }

  function load(name) {
    specimen = name;
    for (var i = 0; i < chips.length; i++) {
      chips[i].setAttribute("aria-pressed", chips[i].dataset.specimen === name ? "true" : "false");
    }
    paintTree();
    paintSource();
    var match = /^#b(\d+)$/.exec(location.hash);
    var wanted = match ? Number(match[1]) - 1 : -1;
    select(wanted >= 0 && wanted < blocks.length ? wanted : -1);
    paintTimeline();
  }

  for (var c = 0; c < chips.length; c++) {
    chips[c].setAttribute(
      "aria-pressed",
      chips[c].dataset.specimen === specimen ? "true" : "false"
    );
    chips[c].addEventListener("click", function () {
      load(this.dataset.specimen);
    });
  }

  scrub.addEventListener("input", function () {
    paintSettled(Number(scrub.value));
  });

  if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
    document.documentElement.classList.add("still");
  }

  var url = new URL("engine/moonmd.js", document.baseURI).href;
  sourceNote.textContent = "loading the engine";
  import(url).then(
    function (module) {
      engine = module;
      load(specimen);
    },
    function () {
      sourceNote.textContent = "the engine did not load";
      outBox.textContent =
        "The parser is built to JavaScript by the docs workflow. Run " +
        "`moon build --target js --release src/examples/browser` and copy the " +
        "output to docs/engine/moonmd.js to try it locally.";
    }
  );
})();
