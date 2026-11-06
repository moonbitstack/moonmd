/* The workbench. Every byte it prints comes from the library compiled to
   JavaScript: the page never parses Markdown itself. */

(function () {
  "use strict";

  var source = document.getElementById("source");
  if (!source) return;

  var out = document.getElementById("out");
  var stats = document.getElementById("stats");
  var flavorSelect = document.getElementById("flavor");
  var tabs = document.querySelectorAll(".tab[data-mode]");
  var chips = document.querySelectorAll(".chip[data-sample]");
  var playButton = document.getElementById("play");
  var liveTag = document.querySelector(".live-tag");

  var engine = null;
  var mode = "html";
  var flavor = "gfm";
  var timer = 0;
  var run = 0;

  var SAMPLES = {
    notes: [
      "# Marginalia",
      "",
      "A *document* is a tree before it is a page. This one is read by",
      "moonmd in the browser, so you can type anywhere, even mid-sentence.",
      "",
      "- [x] blocks first, then inlines",
      "- [ ] every rule of 0.31.2",
      "",
      "> The margin is the tree.",
      ""
    ].join("\n"),
    table: [
      "| step | call | where |",
      "|:--|:-:|--:|",
      "| read | `parse` | a tree |",
      "| write | `html` | a page |",
      "| write | `markdown` | a file |",
      "",
      "A row wider than the header is cut to the header's width.",
      ""
    ].join("\n"),
    edges: [
      "A paragraph with *one* and **two** and ~~three~~ marks,",
      "a [link](/url \"title\") and a bare https://example.com.",
      "",
      "```moonbit",
      "let doc = @moonmd.parse(source[:])",
      "println(doc.html(safe=false))",
      "```",
      "",
      "<!-- raw html survives because this renderer allows it -->",
      ""
    ].join("\n"),
    stream: [
      "# Written while you watch",
      "",
      "The first paragraph settles when the blank line after it arrives.",
      "",
      "```",
      "a fenced block settles at its closing fence",
      "```",
      "",
      "- a list",
      "- settles as a whole",
      ""
    ].join("\n")
  };

  function setStatus(text) {
    if (stats) stats.textContent = text;
  }

  function countTree(node) {
    var blocks = 0;
    var inlines = 0;
    var blockNames = [
      "Heading", "Paragraph", "Code", "Quote", "List", "Item", "Table",
      "Row", "Cell", "Html", "Break"
    ];
    var walk = function (item, isRoot) {
      var isBlock = blockNames.indexOf(item.type) !== -1;
      if (!isRoot) {
        if (isBlock) blocks += 1;
        else inlines += 1;
      }
      (item.children || []).forEach(function (child) {
        walk(child, false);
      });
    };
    walk(node, true);
    return { blocks: blocks, inlines: inlines };
  }

  function treeView(root) {
    var top = document.createElement("ul");
    var build = function (item, parent) {
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
        var n = document.createElement("span");
        n.className = "count";
        n.textContent = String(item.children.length);
        li.appendChild(n);
        var ul = document.createElement("ul");
        item.children.forEach(function (child) {
          build(child, ul);
        });
        li.appendChild(ul);
      }
      parent.appendChild(li);
    };
    (root.children || []).forEach(function (child) {
      build(child, top);
    });
    return top;
  }

  function paint() {
    if (!engine) return;
    var text = source.value;
    out.className = "out scroll";
    if (mode === "tree") {
      var tree = JSON.parse(engine.tree(text, flavor));
      out.classList.add("tree");
      out.textContent = "";
      out.appendChild(treeView(tree));
      var counts = countTree(tree);
      setStatus(counts.blocks + " blocks · " + counts.inlines + " inlines");
      return;
    }
    if (mode === "markdown") {
      out.textContent = engine.markdown(text, flavor);
      setStatus("written back as markdown");
      return;
    }
    var html = engine.html(text, flavor, false);
    out.innerHTML = window.moonmdColor("html", html);
    try {
      var parsed = JSON.parse(engine.tree(text, flavor));
      var numbers = countTree(parsed);
      setStatus(numbers.blocks + " blocks · " + numbers.inlines + " inlines");
    } catch (e) {
      setStatus("");
    }
  }

  function schedule() {
    clearTimeout(timer);
    timer = setTimeout(paint, 90);
  }

  function setMode(next) {
    mode = next;
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].setAttribute("aria-selected", tabs[i].dataset.mode === next ? "true" : "false");
    }
    paint();
  }

  for (var t = 0; t < tabs.length; t++) {
    tabs[t].addEventListener("click", function () {
      stop();
      setMode(this.dataset.mode);
    });
  }

  source.addEventListener("input", function () {
    stop();
    schedule();
  });

  if (flavorSelect) {
    flavorSelect.addEventListener("change", function () {
      flavor = this.value;
      stop();
      schedule();
    });
  }

  for (var c = 0; c < chips.length; c++) {
    chips[c].addEventListener("click", function () {
      stop();
      var name = this.dataset.sample;
      if (!SAMPLES[name]) return;
      source.value = SAMPLES[name];
      for (var k = 0; k < chips.length; k++) {
        chips[k].setAttribute("aria-pressed", chips[k] === this ? "true" : "false");
      }
      setMode("html");
    });
  }

  function sleep(ms) {
    return new Promise(function (resolve) {
      setTimeout(resolve, ms);
    });
  }

  function stop() {
    run += 1;
    if (liveTag) liveTag.classList.remove("on");
  }

  async function play() {
    if (!engine) return;
    stop();
    var token = run;
    var text = source.value;
    if (!text) return;
    var steps = JSON.parse(engine.stream(text, flavor, 3));
    if (!steps.length) {
      setMode("html");
      return;
    }
    mode = "live";
    out.className = "out rendered scroll";
    out.textContent = "";
    if (liveTag) liveTag.classList.add("on");
    for (var i = 0; i < tabs.length; i++) {
      tabs[i].setAttribute("aria-selected", "false");
    }
    var shown = 0;
    for (var step = 0; step < steps.length; step++) {
      if (token !== run) return;
      var target = Math.min(text.length, steps[step].at);
      while (shown < target) {
        if (token !== run) return;
        shown = Math.min(target, shown + 2);
        source.value = text.slice(0, shown);
        source.scrollTop = source.scrollHeight;
        await sleep(10);
      }
      out.insertAdjacentHTML("beforeend", steps[step].html);
      out.scrollTop = out.scrollHeight;
      setStatus(step + 1 + " of " + steps.length + " blocks settled");
      await sleep(280);
    }
    if (token !== run) return;
    while (shown < text.length) {
      shown = Math.min(text.length, shown + 4);
      source.value = text.slice(0, shown);
      await sleep(8);
    }
    source.value = text;
    source.scrollTop = source.scrollHeight;
    if (liveTag) liveTag.classList.remove("on");
    setStatus("settled in " + steps.length + " blocks");
  }

  if (playButton) {
    playButton.addEventListener("click", function () {
      if (mode === "live") {
        stop();
        setMode("html");
      } else {
        play();
      }
    });
  }

  source.value = SAMPLES.notes;

  var url = new URL("engine/moonmd.js", document.baseURI).href;
  setStatus("loading the engine");
  import(url).then(
    function (module) {
      engine = module;
      setStatus("");
      paint();
    },
    function () {
      setStatus("the engine did not load");
      if (out) {
        out.textContent =
          "The parser is built to JavaScript by the docs workflow. Run " +
          "`moon build --target js --release src/engine` and copy the output to " +
          "docs/engine/moonmd.js to try it locally.";
      }
    }
  );
})();
