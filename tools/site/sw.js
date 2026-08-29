/* ---------------------------------------------------------------------------
   Keeps the whole set on the device. The tools are single files with their
   fonts inside them, so once they are cached there is nothing left to fetch
   and they work with no signal at all.

   VERSION is rewritten by the build, so a new build replaces the old cache
   rather than serving yesterday's tool forever.
   --------------------------------------------------------------------------- */
var VERSION = "__VERSION__";
var CACHE = "vslice-tools-" + VERSION;
var FILES = __FILES__;

self.addEventListener("install", function (event) {
  event.waitUntil(
    caches.open(CACHE).then(function (cache) {
      // One missing file should not stop the rest being cached.
      return Promise.all(FILES.map(function (file) {
        return cache.add(new Request(file, { cache: "reload" })).catch(function () {});
      }));
    }).then(function () { return self.skipWaiting(); })
  );
});

self.addEventListener("activate", function (event) {
  event.waitUntil(
    caches.keys().then(function (names) {
      return Promise.all(names.map(function (name) {
        return name === CACHE ? null : caches.delete(name);
      }));
    }).then(function () { return self.clients.claim(); })
  );
});

self.addEventListener("fetch", function (event) {
  var request = event.request;

  if (request.method !== "GET") return;
  if (new URL(request.url).origin !== self.location.origin) return;

  // Cache first: these files only change when a new build lands, and being
  // able to open a tool on a train matters more than being a minute fresh.
  event.respondWith(
    caches.match(request).then(function (hit) {
      if (hit) return hit;

      return fetch(request).then(function (response) {
        if (!response || response.status !== 200 || response.type !== "basic") return response;

        var copy = response.clone();
        caches.open(CACHE).then(function (cache) { cache.put(request, copy); });

        return response;
      }).catch(function () {
        // Offline and never seen: the hub is the most useful thing to show.
        return caches.match("./") || caches.match("index.html");
      });
    })
  );
});
