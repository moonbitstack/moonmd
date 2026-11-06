/* The page furniture: the theme, the margin, the rail, and the colour in the
   code blocks. Nothing here parses Markdown; that is the engine's work. */

(function () {
  "use strict";

  var root = document.documentElement;

  /* ---------- theme ---------- */

  var toggle = document.querySelector(".theme-switch");

  function currentTheme() {
    var set = root.getAttribute("data-theme");
    if (set === "ink" || set === "paper") return set;
    return window.matchMedia("(prefers-color-scheme: dark)").matches ? "ink" : "paper";
  }

  function paintSwitch() {
    if (!toggle) return;
    var ink = currentTheme() === "ink";
    toggle.setAttribute("aria-pressed", ink ? "true" : "false");
    toggle.setAttribute("title", ink ? "Switch to paper" : "Switch to ink");
    var label = toggle.querySelector(".label");
    if (label) label.textContent = ink ? "ink" : "paper";
  }

  if (toggle) {
    paintSwitch();
    toggle.addEventListener("click", function () {
      var next = currentTheme() === "ink" ? "paper" : "ink";
      root.setAttribute("data-theme", next);
      try {
        localStorage.setItem("moonmd-theme", next);
      } catch (e) {
        /* a browser with storage off still gets the theme for this visit */
      }
      paintSwitch();
    });
  }

  /* ---------- scroll position ---------- */

  var atTop = true;

  function markScroll() {
    if (atTop !== (scrollY === 0)) {
      atTop = scrollY === 0;
      root.classList.toggle("at-top", atTop);
    }
    var spine = document.querySelector(".spine");
    var doc = document.querySelector(".doc");
    if (spine && doc) {
      var box = doc.getBoundingClientRect();
      var read = -box.top + innerHeight * 0.55;
      read = Math.max(0, Math.min(box.height, read));
      spine.style.setProperty("--read", read + "px");
    }
    var marks = document.querySelectorAll(".mark-list li");
    if (marks.length) {
      for (var i = 0; i < marks.length; i++) {
        var target = document.getElementById(marks[i].dataset.for);
        if (!target) continue;
        var top = target.getBoundingClientRect().top;
        marks[i].classList.toggle("on", top < innerHeight * 0.55);
      }
    }
  }

  addEventListener("scroll", markScroll, { passive: true });
  addEventListener("resize", markScroll);
  markScroll();

  /* ---------- the margin marks ---------- */

  function placeMarks() {
    var margin = document.querySelector(".margin");
    var list = document.querySelector(".mark-list");
    if (!margin || !list) return;
    var origin = margin.getBoundingClientRect().top;
    var items = list.querySelectorAll("li");
    for (var i = 0; i < items.length; i++) {
      var target = document.getElementById(items[i].dataset.for);
      if (!target) continue;
      var anchor = target.querySelector(".kicker, h1, h2") || target;
      var top = anchor.getBoundingClientRect().top - origin;
      items[i].style.top = Math.max(0, top) + "px";
    }
  }

  placeMarks();
  addEventListener("resize", placeMarks);
  if (document.fonts && document.fonts.ready) document.fonts.ready.then(placeMarks);

  /* ---------- the guide rail ---------- */

  var railLinks = document.querySelectorAll(".rail a[href^='#']");
  if (railLinks.length) {
    var watched = [];
    for (var j = 0; j < railLinks.length; j++) {
      var section = document.getElementById(railLinks[j].getAttribute("href").slice(1));
      if (section) watched.push({ link: railLinks[j], section: section });
    }
    var pick = function () {
      var line = innerHeight * 0.32;
      var best = watched[0];
      for (var k = 0; k < watched.length; k++) {
        if (watched[k].section.getBoundingClientRect().top <= line) best = watched[k];
      }
      for (var m = 0; m < watched.length; m++) {
        watched[m].link.classList.toggle("on", watched[m] === best);
      }
    };
    addEventListener("scroll", pick, { passive: true });
    pick();
  }

  /* ---------- colour in the code blocks ---------- */

  function esc(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");
  }

  var MOONBIT =
    /(\/\/[^\n]*)|("(?:[^"\\\n]|\\.)*")|\b(pub|fn|let|mut|match|if|else|while|for|in|return|raise|import|test|as|guard|type|struct|enum|impl|derive|true|false|abort|self)\b|\b([A-Z][A-Za-z0-9_]*)\b|\b(\d+)\b/g;

  function moonbit(text) {
    var out = "";
    var last = 0;
    var m;
    while ((m = MOONBIT.exec(text))) {
      out += esc(text.slice(last, m.index));
      if (m[1]) out += '<span class="tok-com">' + esc(m[1]) + "</span>";
      else if (m[2]) out += '<span class="tok-str">' + esc(m[2]) + "</span>";
      else if (m[3]) out += '<span class="tok-key">' + esc(m[3]) + "</span>";
      else if (m[4]) out += '<span class="tok-attr">' + esc(m[4]) + "</span>";
      else out += '<span class="tok-num">' + esc(m[5]) + "</span>";
      last = m.index + m[0].length;
    }
    return out + esc(text.slice(last));
  }

  function html(text) {
    var out = "";
    var last = 0;
    var tag = /<(\/?)([a-zA-Z][a-zA-Z0-9-]*)([^>]*)>/g;
    var m;
    while ((m = tag.exec(text))) {
      out += esc(text.slice(last, m.index));
      var body = m[3].replace(
        /([a-zA-Z-]+)(=)("[^"]*")?/g,
        function (_, name, eq, value) {
          return (
            '<span class="tok-attr">' +
            name +
            "</span>" +
            eq +
            (value ? '<span class="tok-str">' + esc(value) + "</span>" : "")
          );
        }
      );
      out +=
        "&lt;" +
        '<span class="tok-tag">' +
        m[1] +
        m[2] +
        "</span>" +
        body +
        "&gt;";
      last = m.index + m[0].length;
    }
    return out + esc(text.slice(last));
  }

  function json(text) {
    var out = "";
    var last = 0;
    var tok = /("(?:[^"\\]|\\.)*")(\s*:)?|\b(true|false|null)\b|(-?\d+(?:\.\d+)?)/g;
    var m;
    while ((m = tok.exec(text))) {
      out += esc(text.slice(last, m.index));
      if (m[1] && m[2]) {
        out += '<span class="tok-attr">' + esc(m[1]) + "</span>" + m[2];
      } else if (m[1]) {
        out += '<span class="tok-str">' + esc(m[1]) + "</span>";
      } else if (m[3]) {
        out += '<span class="tok-key">' + m[3] + "</span>";
      } else {
        out += '<span class="tok-num">' + m[4] + "</span>";
      }
      last = m.index + m[0].length;
    }
    return out + esc(text.slice(last));
  }

  window.moonmdColor = function (lang, text) {
    if (lang === "html") return html(text);
    if (lang === "json") return json(text);
    if (lang === "markdown" || lang === "text") return esc(text);
    return moonbit(text);
  };

  var blocks = document.querySelectorAll(".code[data-lang]");
  for (var b = 0; b < blocks.length; b++) {
    var code = blocks[b].querySelector("code");
    if (!code) continue;
    var lang = blocks[b].getAttribute("data-lang");
    code.innerHTML = window.moonmdColor(lang, code.textContent);
  }

  /* ---------- copy ---------- */

  var copies = document.querySelectorAll("[data-copy]");
  for (var c = 0; c < copies.length; c++) {
    copies[c].addEventListener("click", function () {
      var button = this;
      var source = document.getElementById(button.getAttribute("data-copy"));
      if (!source) return;
      var text = source.textContent;
      var done = function () {
        var was = button.textContent;
        button.textContent = "copied";
        setTimeout(function () {
          button.textContent = was;
        }, 1400);
      };
      if (navigator.clipboard) {
        navigator.clipboard.writeText(text).then(done, function () {});
      }
    });
  }
})();
