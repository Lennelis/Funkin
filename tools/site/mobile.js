/* ---------------------------------------------------------------------------
   The app shell. Builds the pane switcher every tool shares, remembers where
   you were, and registers the worker that makes the site work offline.

   It reads the page rather than being told about it, so the same script suits
   all five tools without any of them knowing it is here.
   --------------------------------------------------------------------------- */
(function () {
  "use strict";

  var NARROW = 900;

  // Per tool: which panel you were on in the chart converter says nothing
  // about where you want to be in the character editor.
  var STORE = "vslice-pane:" + location.pathname;

  function narrow() { return window.innerWidth <= NARROW; }

  /** A short label for a panel: what it calls itself, or what it is. */
  function labelFor(section, fallback) {
    var named = (section.getAttribute("aria-label") || "").trim();
    if (named && named.length <= 16) return named;

    var eyebrow = section.querySelector(".eyebrow");
    var text = eyebrow ? eyebrow.textContent.trim() : "";

    if (text && text.length <= 16) return titleCase(text);

    return fallback;
  }

  /** Panel headings are shouted; a tab should not be. */
  function titleCase(text) {
    return text.toLowerCase().split(/\s+/).map(function (word, index) {
      var original = text.split(/\s+/)[index];

      // Initialisms stay as they were written: XML, JSON, BPM.
      if (original.length <= 4 && original === original.toUpperCase()) return original;

      return word.replace(/(^|[-'])([a-z])/g, function (all, before, letter) {
        return before + letter.toUpperCase();
      });
    }).join(" ");
  }

  function paneName(section) {
    if (section.classList.contains("rail")) return "rail";
    if (section.classList.contains("stage-col")) return "stage";
    if (section.classList.contains("inspector")) return "inspector";
    return null;
  }

  var drawer = document.querySelector(".drawer");
  var workspaces = [].slice.call(document.querySelectorAll(".workspace"));
  var bars = [];

  workspaces.forEach(function (workspace) {
    var bar = document.createElement("nav");
    bar.className = "pane-tabs";
    bar.setAttribute("role", "tablist");
    bar.setAttribute("aria-label", "Which panel to show");

    var buttons = [];

    [].slice.call(workspace.children).forEach(function (section) {
      var pane = paneName(section);
      if (!pane) return;

      var tab = document.createElement("button");
      tab.type = "button";
      tab.className = "pane-tab";
      tab.setAttribute("role", "tab");
      tab.dataset.pane = pane;
      tab.textContent = labelFor(section,
        pane === "rail" ? "Setup" : (pane === "stage" ? "Preview" : "Details"));

      tab.addEventListener("click", function () { show(pane); });

      buttons.push(tab);
      bar.appendChild(tab);
    });

    if (drawer) {
      var tab = document.createElement("button");
      tab.type = "button";
      tab.className = "pane-tab";
      tab.setAttribute("role", "tab");
      tab.dataset.pane = "drawer";
      tab.textContent = labelFor(drawer, "Files");

      tab.addEventListener("click", function () { show("drawer"); });

      buttons.push(tab);
      bar.appendChild(tab);
    }

    if (buttons.length < 2) return;

    workspace.parentNode.insertBefore(bar, workspace);
    bars.push({ bar: bar, workspace: workspace, buttons: buttons });
  });

  /**
   * A tool can hold more than one workspace and swap between them — the chart
   * converter has one for a single chart and another for a whole mod. Only the
   * one on screen should have tabs.
   */
  function syncBars() {
    bars.forEach(function (entry) { entry.bar.hidden = entry.workspace.hidden; });
  }

  if (window.MutationObserver) {
    bars.forEach(function (entry) {
      new MutationObserver(syncBars).observe(entry.workspace, {
        attributes: true,
        attributeFilter: ["hidden"]
      });
    });
  }

  syncBars();

  var current = "rail";

  function show(pane) {
    current = pane;

    document.body.dataset.pane = pane;

    bars.forEach(function (entry) {
      entry.workspace.dataset.pane = pane === "drawer" ? entry.workspace.dataset.pane || "rail" : pane;

      entry.buttons.forEach(function (button) {
        button.setAttribute("aria-selected", button.dataset.pane === pane ? "true" : "false");
      });
    });

    try { localStorage.setItem(STORE, pane); } catch (err) { /* private mode */ }

    // A canvas sized to a hidden panel comes back with no size of its own, so
    // the tool is nudged to measure itself again.
    window.dispatchEvent(new Event("resize"));
  }

  var remembered = null;
  try { remembered = localStorage.getItem(STORE); } catch (err) { /* ignore */ }

  show(remembered || "rail");

  // A tool that opens a dialog wants the whole screen for it.
  var overlays = [].slice.call(document.querySelectorAll(".overlay"));

  if (window.MutationObserver && overlays.length) {
    overlays.forEach(function (overlay) {
      new MutationObserver(function () {
        if (!overlay.hidden) document.body.classList.add("has-overlay");
        else if (!overlays.some(function (other) { return !other.hidden; })) {
          document.body.classList.remove("has-overlay");
        }
      }).observe(overlay, { attributes: true, attributeFilter: ["hidden"] });
    });
  }

  window.addEventListener("resize", function () {
    if (!narrow()) document.body.removeAttribute("data-pane");
    else document.body.dataset.pane = current;
  });

  if (!narrow()) document.body.removeAttribute("data-pane");

  /**
   * How tall the control strip is, so a toast can sit above it. Tools differ,
   * and the character editor's grows a row when you switch control groups.
   */
  function measureTransport() {
    var strip = document.querySelector(".transport");
    var tabs = document.querySelector(".transport-tabs");

    var height = (strip ? strip.getBoundingClientRect().height : 0)
      + (tabs && tabs.offsetParent ? tabs.getBoundingClientRect().height : 0);

    document.documentElement.style.setProperty("--transport-h", Math.round(height) + "px");
  }

  measureTransport();
  window.addEventListener("resize", measureTransport);
  document.addEventListener("click", function () { setTimeout(measureTransport, 60); });

  // ----------------------------------------------------------- offline use

  if ("serviceWorker" in navigator && location.protocol.indexOf("http") === 0) {
    window.addEventListener("load", function () {
      navigator.serviceWorker.register("sw.js").catch(function () {
        // Opened from somewhere that cannot register one; the tool still works.
      });
    });
  }
})();
