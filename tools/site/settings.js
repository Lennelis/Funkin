/* ---------------------------------------------------------------------------
   One settings store for the hub and every tool.

   The tools are separate documents, so the store lives in localStorage on the
   shared origin and each page applies it to its own root element. Nothing here
   knows what a setting means -- it only writes the attribute, and the CSS in
   each tool decides what that looks like.
   --------------------------------------------------------------------------- */
(function () {
  "use strict";

  var KEY = "vslice-settings-v1";

  var DEFAULTS = {
    theme: "system",   // system | light | dark
    hints: true,       // the explanatory lines under the controls
    switcher: true,    // the tab that jumps between tools
    quality: "full",   // full | low
    music: false,
    autoSave: true
  };

  var listeners = [];
  var state = load();

  function load() {
    var saved = {};

    try {
      saved = JSON.parse(localStorage.getItem(KEY)) || {};
    } catch (error) {
      saved = {};
    }

    var out = {};
    for (var name in DEFAULTS) {
      out[name] = Object.prototype.hasOwnProperty.call(saved, name) ? saved[name] : DEFAULTS[name];
    }
    return out;
  }

  function save() {
    // A full storage box, or a browser refusing it outright, must not take the
    // page down with it -- the setting just does not survive the reload.
    try {
      localStorage.setItem(KEY, JSON.stringify(state));
    } catch (error) {
      /* nothing to do */
    }
  }

  function apply() {
    var root = document.documentElement;

    if (state.theme === "system") delete root.dataset.theme;
    else root.dataset.theme = state.theme;

    root.dataset.hints = state.hints ? "on" : "off";
    root.dataset.quality = state.quality;
    root.dataset.switcher = state.switcher ? "on" : "off";
  }

  function set(name, value) {
    if (!Object.prototype.hasOwnProperty.call(DEFAULTS, name) || state[name] === value) return;

    state[name] = value;
    save();
    apply();
    listeners.forEach(function (fn) { fn(name, value); });
  }

  apply();

  window.VSliceSettings = {
    defaults: DEFAULTS,
    get: function (name) { return state[name]; },
    all: function () { return JSON.parse(JSON.stringify(state)); },
    set: set,
    /** Called with (name, value) whenever a setting changes in this document. */
    subscribe: function (fn) { listeners.push(fn); }
  };

  // A tool open in another tab is the same person changing their own mind.
  window.addEventListener("storage", function (event) {
    if (event.key !== KEY) return;
    state = load();
    apply();
    listeners.forEach(function (fn) { fn(null, null); });
  });
})();
