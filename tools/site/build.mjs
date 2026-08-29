/* ---------------------------------------------------------------------------
   Builds the site out of the tools.

   Each tool stays a single self-contained file that works on its own; the
   build only folds the shared touch layer and the app plumbing into a copy of
   it, so nothing here is needed for a tool to run from your own disk.

   Usage: node build.mjs [outdir]      (default: dist)
   --------------------------------------------------------------------------- */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const here = path.dirname(fileURLToPath(import.meta.url));
const tools = path.join(here, "..");

// `--bake` writes the layer back into the tools themselves, so a file someone
// downloads behaves the same as the site does.
const bake = process.argv.includes("--bake");
const out = path.resolve(here, process.argv.filter((arg) => arg !== "--bake")[2] || "dist");

const TOOLS = [
  "vslicechartconverter.html",
  "vslicecharactereditor.html",
  "vslicesheetpacker.html",
  "vsliceleveleditor.html",
  "vslicecutsceneeditor.html"
];

const mobileCss = fs.readFileSync(path.join(here, "mobile.css"), "utf8");
const mobileJs = fs.readFileSync(path.join(here, "mobile.js"), "utf8");

/** The head tags that make a page behave like an installed app. */
const APP_HEAD = `
<meta name="theme-color" content="#D5187A" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#14111F" media="(prefers-color-scheme: dark)">
<meta name="mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-status-bar-style" content="black-translucent">
<link rel="manifest" href="manifest.webmanifest">
<link rel="apple-touch-icon" href="icon-192.png">
<link rel="icon" href="icon-192.png">
`;

// The touch layer is fenced so it can be replaced rather than stacked up. A
// tool carries it in the file itself — people download these and open them
// straight off their phone, where nothing is around to inject anything.
const START = "<!-- touch-layer: built from tools/site, do not edit here -->";
const END = "<!-- end touch-layer -->";
const LAYER = new RegExp(START.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "[\\s\\S]*?" + END, "i");

/**
 * Fold the shared layer into a tool.
 * @param {boolean} pwa also add the tags that make it installable, which only
 *   mean anything when the file is served rather than opened off a disk.
 */
function appify(html, pwa) {
  // Safe areas need viewport-fit, which the tools do not ask for on their own.
  html = html.replace(
    /<meta name="viewport" content="[^"]*">/i,
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">'
  );

  if (pwa && !html.includes('rel="manifest"')) {
    html = html.replace(/<\/head>/i, APP_HEAD + "</head>");
  }

  const layer = `${START}\n<style>\n${mobileCss}\n</style>\n<script>\n${mobileJs}\n</script>\n${END}`;

  // Replace whatever is already there, so building never doubles it up.
  if (LAYER.test(html)) return html.replace(LAYER, layer);

  return html.includes("</body>")
    ? html.replace(/<\/body>/i, "\n" + layer + "\n</body>")
    : html + "\n" + layer + "\n";
}

/** The two embedded faces every tool carries, lifted for the hub to reuse. */
function fontsFrom(html) {
  const faces = html.match(/@font-face\s*\{[^}]*\}/g) || [];
  return faces.slice(0, 2).join("\n\n");
}

fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });

let fonts = "";

for (const name of TOOLS) {
  const from = path.join(tools, name);

  if (!fs.existsSync(from)) {
    console.warn(`  ! ${name} is missing, skipping`);
    continue;
  }

  const html = fs.readFileSync(from, "utf8");
  if (!fonts) fonts = fontsFrom(html);

  if (bake) {
    fs.writeFileSync(from, appify(html, false));
    console.log(`  ~ tools/${name}`);
  }

  fs.writeFileSync(path.join(out, name), appify(html, true));
  console.log(`  + ${name}`);
}

const hub = fs.readFileSync(path.join(here, "hub.html"), "utf8").replace("/*FONTS*/", fonts);
fs.writeFileSync(path.join(out, "index.html"), hub);
console.log("  + index.html");

for (const asset of [
  "manifest.webmanifest",
  "icon-192.png",
  "icon-512.png",
  "icon-maskable-512.png",
  "brand/made-with-claude.svg",
]) {
  const from = path.join(here, asset);

  if (!fs.existsSync(from)) {
    console.warn(`  ! ${asset} is missing`);
    continue;
  }

  const to = path.join(out, asset);
  fs.mkdirSync(path.dirname(to), { recursive: true });
  fs.copyFileSync(from, to);
  console.log(`  + ${asset}`);
}

// The worker is told what to keep and which build it belongs to, so a new
// build replaces the old cache instead of serving yesterday's tools.
function walk(dir, prefix = "") {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const name = prefix + entry.name;
    return entry.isDirectory() ? walk(path.join(dir, entry.name), name + "/") : [name];
  });
}

const shipped = walk(out).filter((name) => name !== "sw.js");
const files = ["./", ...shipped];
const version = new Date().toISOString().replace(/[-:T]/g, "").slice(0, 14);

const sw = fs.readFileSync(path.join(here, "sw.js"), "utf8")
  .replace("__VERSION__", version)
  .replace("__FILES__", JSON.stringify(files, null, 2));

fs.writeFileSync(path.join(out, "sw.js"), sw);
console.log("  + sw.js");

const total = shipped.reduce((sum, name) => sum + fs.statSync(path.join(out, name)).size, 0);
console.log(`\n${shipped.length + 1} files, ${(total / 1024 / 1024).toFixed(1)} MB -> ${out}`);
