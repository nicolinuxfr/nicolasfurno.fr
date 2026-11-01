import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const script = readFileSync(new URL("../../themes/nicolasfurno/assets/js/photo-maps.js", import.meta.url), "utf8");

function setup({ loadError = false } = {}) {
  const element = { dataset: { mapkitState: "loading" } };
  const scripts = [];
  const maps = [];
  const moduleLoads = [];
  const kit = Object.assign(new EventTarget(), {
    init(options) { this.options = options; },
    load(libraries) {
      moduleLoads.push(Array.from(libraries));
      return loadError ? Promise.reject(new Error("Module unavailable")) : Promise.resolve(kit);
    },
    Map: class {
      constructor(node, options) { Object.assign(this, { node, options }); maps.push(this); }
      showItems(items) { this.annotations = items; }
    },
    MapType: { Hybrid: "hybrid" },
    Coordinate: class {}, Padding: class {},
    MarkerAnnotation: class { constructor(coordinate, options) { this.options = options; } },
    FeatureVisibility: { Hidden: "hidden" },
  });
  let intersection;
  let disconnected = false;
  const window = { IntersectionObserver: true };
  const document = Object.assign(new EventTarget(), {
    getElementById: (id) => id === "map" ? element : {
      textContent: JSON.stringify({ token: "test-token", photos: [{ lat: 48, long: -4, photoIndex: 0 }] }),
    },
    createElement: () => new EventTarget(),
    head: { append(node) { scripts.push(node); } },
  });
  vm.runInNewContext(script, {
    window, document, Event,
    IntersectionObserver: class {
      constructor(callback) { intersection = callback; }
      observe() {}
      disconnect() { disconnected = true; }
    },
  });
  return {
    window, kit, element, scripts, maps, moduleLoads,
    get disconnected() { return disconnected; },
    approachMap() { intersection([{ isIntersecting: true }]); },
    coreLoaded() { window.mapkit = kit; scripts[0].dispatchEvent(new Event("load")); },
  };
}

test("loads no Apple SDK until needed, then shares one download and only two libraries", async () => {
  const view = setup();
  assert.equal(view.scripts.length, 0);
  const first = view.window.loadPhotoMapKit();
  assert.equal(first, view.window.loadPhotoMapKit());
  assert.equal(view.scripts.length, 1);
  assert.equal(view.scripts[0].src, "https://cdn.apple-mapkit.com/mk/6/mapkit.core.js");
  assert.equal(view.scripts[0].async, true);
  view.coreLoaded();
  assert.equal(await first, view.kit);
  assert.deepEqual(view.moduleLoads, [["map", "annotations"]]);
  assert.deepEqual(Array.from(view.kit.options.libraries), ["map", "annotations"]);
  assert.equal(view.maps.length, 0, "opening the gallery must not render the offscreen article map");
  view.approachMap();
  await first;
  await Promise.resolve();
  assert.equal(view.maps.length, 1);
  assert.equal(view.maps[0].options.mapType, "hybrid");
  assert.equal(view.maps[0].annotations.length, 1);
  assert.equal(view.disconnected, true);
  assert.equal(view.scripts.length, 1);
});

test("approaching the article map starts loading; failures do not create empty map instances", async () => {
  const view = setup({ loadError: true });
  view.approachMap();
  const pending = view.window.loadPhotoMapKit();
  view.coreLoaded();
  await assert.rejects(pending, /Module unavailable/);
  await Promise.resolve();
  assert.equal(view.element.dataset.mapkitState, "error");
  assert.equal(view.maps.length, 0);
  assert.equal(view.scripts.length, 1);
});

test("network failure is reported and does not start duplicate SDK requests", async () => {
  const view = setup();
  const pending = view.window.loadPhotoMapKit();
  view.scripts[0].dispatchEvent(new Event("error"));
  await assert.rejects(pending, /MapKit could not be loaded/);
  assert.equal(view.element.dataset.mapkitState, "error");
  assert.equal(view.window.loadPhotoMapKit(), pending);
  assert.equal(view.scripts.length, 1);
});

test("authorization events remain independent of module loading", async () => {
  const view = setup();
  const pending = view.window.loadPhotoMapKit();
  view.coreLoaded();
  await pending;
  view.kit.dispatchEvent(new Event("error"));
  assert.equal(view.element.dataset.mapkitState, "error");
  view.kit.dispatchEvent(new Event("configuration-change"));
  assert.equal(view.element.dataset.mapkitState, "ready");
});
