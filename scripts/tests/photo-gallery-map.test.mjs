import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

const script = readFileSync(new URL("../../themes/nicolasfurno/assets/js/photo-gallery-map.js", import.meta.url), "utf8");

function setup({ mobile = false, state = "ready", unavailable = false, broken = false, preview = false,
  points = [{ lat: "48.1", long: "-3.9" }, { lat: "48.11", long: "-3.91" }, {}] } = {}) {
  const container = { hidden: true, clientWidth: mobile ? 288 : 500, dataset: { preview: String(preview) },
    getBoundingClientRect: () => ({ left: 940, top: 0 }) };
  const stage = { right: 1190, top: 44 };
  const lightbox = Object.assign(new EventTarget(), {
    open: false, querySelector: (selector) => selector === ".photo-lightbox-stage"
      ? { getBoundingClientRect: () => stage } : container,
    getBoundingClientRect: () => ({ right: 1440, top: 0 }),
  });
  const pageMap = { dataset: { mapkitState: state } };
  const document = Object.assign(new EventTarget(), {
    querySelector: () => lightbox,
    querySelectorAll: () => points.map((dataset) => ({ dataset })),
    getElementById: () => pageMap,
  });
  const reducedMotion = Object.assign(new EventTarget(), { matches: false });
  const compact = Object.assign(new EventTarget(), { matches: mobile });
  const maps = [];
  const markers = [];
  class Coordinate {
    constructor(latitude, longitude) { Object.assign(this, { latitude, longitude }); }
  }
  class Map {
    static MapTypes = { MutedStandard: "mutedStandard" };
    static ColorSchemes = { Dark: "dark" };
    constructor(element, options) {
      if (broken) throw new Error("Map unavailable");
      Object.assign(this, { element, options, pans: [], point: { x: 1320, y: 140 } });
      maps.push(this);
    }
    addAnnotation(marker) { markers.push(marker); }
    showItems(items, options) { this.region = { center: items[0].coordinate, span: options.minimumSpan }; }
    convertCoordinateToPointOnPage() { return this.point; }
    setCenterAnimated(coordinate, animated) { this.pans.push({ coordinate, animated }); }
  }
  const mapkit = unavailable ? undefined : {
    Map, Coordinate, FeatureVisibility: { Hidden: "hidden" },
    CoordinateSpan: class { constructor(latitudeDelta, longitudeDelta) { Object.assign(this, { latitudeDelta, longitudeDelta }); } },
    Padding: class { constructor(top, right, bottom, left) { Object.assign(this, { top, right, bottom, left }); } },
    MarkerAnnotation: class { constructor(coordinate) { this.coordinate = coordinate; } },
  };
  let resize;
  vm.runInNewContext(script, {
    document, window: { mapkit, scrollX: 0, scrollY: 0 },
    matchMedia: (query) => query.includes("max-width") ? compact : reducedMotion,
    requestAnimationFrame: (callback) => callback(),
    ResizeObserver: class { constructor(callback) { resize = callback; } observe() {} },
  });
  return { container, lightbox, reducedMotion, compact, maps, markers, pageMap, stage,
    resize: () => resize(),
    state(value) {
      pageMap.dataset.mapkitState = value;
      document.dispatchEvent(new Event("photo-map-statechange"));
    },
    show(index) {
      lightbox.open = true;
      const event = new Event("photochange");
      event.detail = { index };
      lightbox.dispatchEvent(event);
    },
  };
}

test("creates one desktop map on demand and moves its only marker without panning unnecessarily", () => {
  const view = setup();
  assert.equal(view.maps.length, 0);
  view.show(0);
  assert.equal(view.container.hidden, false);
  assert.equal(view.maps.length, 1);
  assert.equal(view.maps[0].options.mapType, "mutedStandard");
  assert.equal(view.maps[0].options.colorScheme, "dark");
  assert.equal(view.markers.length, 1);
  view.show(1);
  assert.equal(view.maps.length, 1);
  assert.equal(view.markers[0].coordinate.latitude, 48.11);
  assert.equal(view.markers[0].coordinate.longitude, -3.91);
  assert.equal(view.maps[0].pans.length, 0);
  view.show(2);
  assert.equal(view.container.hidden, true);
  view.show(0);
  assert.equal(view.container.hidden, false);
  view.lightbox.open = false;
  view.lightbox.dispatchEvent(new Event("close"));
  assert.equal(view.container.hidden, true);
});

test("keeps the map visible on narrow screens and after resizing", () => {
  const view = setup({ mobile: true });
  view.show(0);
  assert.equal(view.maps.length, 1);
  assert.equal(view.container.hidden, false);
  view.container.clientWidth = 500;
  view.resize();
  assert.equal(view.maps.length, 1);
  assert.equal(view.container.hidden, false);
  view.container.clientWidth = 288;
  view.resize();
  assert.equal(view.container.hidden, false);
});

test("centers the active pin on compact screens after navigation and resizing", () => {
  const view = setup({ mobile: true });
  view.show(0);
  assert.equal(view.maps[0].padding.top, view.maps[0].padding.bottom);
  assert.equal(view.maps[0].padding.left, view.maps[0].padding.right);
  view.show(1);
  assert.equal(view.maps[0].pans.at(-1).coordinate.latitude, 48.11);
  assert.equal(view.maps[0].pans.at(-1).animated, false);
  view.resize();
  assert.equal(view.maps[0].pans.at(-1).coordinate.latitude, 48.11);
  view.compact.matches = false;
  view.compact.dispatchEvent(new Event("change"));
  assert.notEqual(view.maps[0].padding.top, view.maps[0].padding.bottom);
});

test("waits for MapKit authorization and hides the map after asynchronous failure", () => {
  const view = setup({ state: "loading" });
  view.show(0);
  assert.equal(view.maps.length, 0);
  view.show(1);
  view.state("ready");
  assert.equal(view.maps.length, 1);
  assert.equal(view.markers[0].coordinate.latitude, 48.11);
  view.state("error");
  assert.equal(view.container.hidden, true);
});

test("the local preview keeps the grid and marker visible without authorized tiles", () => {
  const view = setup({ preview: true, state: "error" });
  view.show(0);
  assert.equal(view.container.hidden, false);
  assert.equal(view.maps.length, 1);
  view.show(1);
  assert.equal(view.markers[0].coordinate.latitude, 48.11);
  view.state("error");
  assert.equal(view.container.hidden, false);
});

test("recenters only when needed and respects reduced motion", () => {
  const view = setup();
  view.show(0);
  view.maps[0].point = { x: 490, y: 510 };
  view.reducedMotion.matches = true;
  view.show(1);
  assert.equal(view.maps[0].pans.length, 1);
  assert.equal(view.maps[0].pans[0].animated, false);
  assert.equal(view.maps[0].pans[0].coordinate.latitude, 48.11);
});

test("missing library, invalid coordinates, and constructor errors leave the viewer usable", () => {
  for (const options of [
    { unavailable: true }, { broken: true },
    { points: [{ lat: "NaN", long: "0" }] },
    { points: [{ lat: "91", long: "0" }] },
    { points: [{ lat: "0", long: "0" }] },
  ]) {
    const view = setup(options);
    assert.doesNotThrow(() => view.show(0));
    assert.equal(view.container.hidden, true);
  }
});

test("frames nearby photos across the date line without zooming out to the whole world", () => {
  const view = setup({ points: [{ lat: "40", long: "179.99" }, { lat: "40", long: "-179.99" }] });
  view.show(0);
  assert.ok(view.maps[0].region.span.longitudeDelta < 0.04);
});

test("keeps the same map beneath the photo when the foreground overlaps it", () => {
  const view = setup();
  view.stage.right = 1390;
  view.show(0);
  assert.equal(view.container.hidden, false);
  assert.equal(view.maps.length, 1);
  view.stage.right = 1190;
  view.resize();
  assert.equal(view.container.hidden, false);
  assert.equal(view.maps.length, 1);
  view.stage.right = 1390;
  view.stage.top = 300;
  view.resize();
  assert.equal(view.container.hidden, false);
});
