// Per-rule behaviour on synthetic single-change variants, plus the address, path and package
// loading helpers.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { addressesMatch, normalizeAddress } from "../src/address.js";
import { resolveRelative } from "../src/context.js";
import { PackageLoadError, packageFromFiles } from "../src/package.js";
import { runChecks } from "../src/verdict.js";
import {
  HUB_ADDRESS,
  loadBroken,
  loadGood,
  nonInfo,
  pathOf,
  rewriteGlbJson,
  withFile,
} from "./helpers.js";
import { variants } from "./variants.js";

/** Exactly these [ruleId, severity] blocker/limitation findings, in any order. */
const EXPECTED: Record<string, Array<[string, "blocker" | "limitation"]>> = {
  "fingerprint mismatch": [["manifest.fingerprints", "blocker"]],
  "listed file missing": [["manifest.fingerprints", "blocker"]],
  "unlisted file": [],
  "capture model not valid": [["files.parseable", "blocker"]],
  "truncated pdf": [["files.parseable", "blocker"]],
  "csv ragged row": [["files.parseable", "blocker"]],
  "photo not an image": [["files.parseable", "blocker"]],
  "hub address empty": [["property.address", "blocker"]],
  "capture model of another capture": [["property.address", "blocker"]],
  "no field controls file": [["units.scale", "limitation"]],
  "no distance controls": [["units.scale", "limitation"]],
  "distance 2% off": [["units.scale", "limitation"]],
  "dxf in inches": [["orientation.up", "limitation"]],
  "las z extent too tall": [
    ["orientation.up", "limitation"],
    ["las.header", "limitation"],
  ],
  "glb rotated z-up by its node": [["orientation.up", "limitation"]],
  "obj material library missing": [["companions.resolve", "limitation"]],
  "mtl texture missing": [["companions.resolve", "limitation"]],
  "gltf image missing": [["companions.resolve", "limitation"]],
  "dxf with mesh and points": [["dxf.content", "limitation"]],
  "room photo missing": [["coverage.rooms", "limitation"]],
  "omitted and inaccessible rooms": [
    ["coverage.rooms", "limitation"],
    ["coverage.rooms", "limitation"],
  ],
  "implausible ceiling and door": [
    ["geometry.plausibility", "limitation"],
    ["geometry.plausibility", "limitation"],
  ],
  "house with one shared landmark": [["floors.registration", "limitation"]],
  "field controls derived from the scan": [["evidence.independence", "limitation"]],
};

const sortPairs = (pairs: Array<[string, string]>) =>
  [...pairs].sort((a, b) => (a.join() < b.join() ? -1 : a.join() > b.join() ? 1 : 0));

describe("rules on single-change variants", () => {
  const all = variants();
  it("every variant has an expectation", () => {
    assert.deepEqual(all.map((variant) => variant.name).sort(), Object.keys(EXPECTED).sort());
  });
  for (const variant of all) {
    it(variant.name, () => {
      const verdict = runChecks(variant.pkg, variant.hubAddress ?? HUB_ADDRESS);
      const actual = nonInfo(verdict).map(
        (item) => [item.ruleId, item.severity] as [string, string],
      );
      assert.deepEqual(
        sortPairs(actual),
        sortPairs(EXPECTED[variant.name] ?? []),
        JSON.stringify(nonInfo(verdict), null, 2),
      );
    });
  }

  it("names floor alignment as not established when floors share fewer than two landmarks", () => {
    const variant = all.find((item) => item.name === "house with one shared landmark");
    assert.ok(variant !== undefined);
    const verdict = runChecks(variant.pkg, HUB_ADDRESS);
    assert.match(nonInfo(verdict)[0]?.message ?? "", /Floor alignment not established/);
    assert.match(nonInfo(verdict)[0]?.measured ?? "", /1 shared landmark/);
  });

  it("a Z-up mesh corrected by its node rotation is +Y up", () => {
    const pkg = loadBroken("z-up-mesh");
    const path = pathOf(pkg, "mesh_glb");
    const fixed = withFile(
      pkg,
      path,
      rewriteGlbJson(pkg.files.get(path) as Uint8Array, (json) => {
        const nodes = json.nodes as Array<Record<string, unknown>>;
        (nodes[0] as Record<string, unknown>).rotation = [-Math.SQRT1_2, 0, 0, Math.SQRT1_2];
      }),
    );
    const verdict = runChecks(fixed, HUB_ADDRESS);
    assert.deepEqual(nonInfo(verdict), []);
    assert.equal(verdict.outcome, "ready");
  });

  it("marks floor registration not applicable for a one-capture visit", () => {
    const verdict = runChecks(loadGood("box-room"), HUB_ADDRESS);
    const status = verdict.checks.find((check) => check.ruleId === "floors.registration")?.status;
    assert.equal(status, "not_applicable");
  });
});

describe("address normalization", () => {
  it("matches the same address written differently", () => {
    assert.ok(addressesMatch("100 Example St., Testville NY 00000", HUB_ADDRESS));
    assert.ok(addressesMatch("  100   EXAMPLE STREET, testville, ny 00000 ", HUB_ADDRESS));
    assert.equal(normalizeAddress("12 West 3rd Avenue, Apt 4"), "12 w 3rd ave apt 4");
  });

  it("does not match a different number, street or empty address", () => {
    assert.equal(addressesMatch("101 Example Street, Testville, NY 00000", HUB_ADDRESS), false);
    assert.equal(addressesMatch("200 Sample Avenue, Testville, NY 00000", HUB_ADDRESS), false);
    assert.equal(addressesMatch("", ""), false);
  });
});

describe("relative companion paths", () => {
  it("resolves next to the referring file and through ..", () => {
    assert.equal(resolveRelative("A/B/mesh.obj", "mesh.mtl"), "A/B/mesh.mtl");
    assert.equal(resolveRelative("A/B/mesh.obj", "./tex/t.png"), "A/B/tex/t.png");
    assert.equal(resolveRelative("A/B/mesh.obj", "..\\t.png"), "A/t.png");
  });

  it("refuses absolute paths, URLs and paths that leave the package", () => {
    assert.equal(resolveRelative("A/mesh.obj", "/etc/passwd"), undefined);
    assert.equal(resolveRelative("A/mesh.obj", "https://example.com/t.png"), undefined);
    assert.equal(resolveRelative("A/mesh.obj", "../../t.png"), undefined);
  });
});

describe("packageFromFiles", () => {
  const good = loadGood("box-room");

  it("refuses files without a Chapter manifest", () => {
    const files = new Map(good.files);
    files.delete(good.manifestPath);
    assert.throws(() => packageFromFiles(files), PackageLoadError);
  });

  it("refuses an invalid manifest", () => {
    const files = new Map(good.files);
    files.set(good.manifestPath, new TextEncoder().encode('{"schemaVersion":"1.0.0"}'));
    assert.throws(() => packageFromFiles(files), PackageLoadError);
  });

  it("refuses two manifests", () => {
    const files = new Map(good.files);
    files.set(
      "Source Register/00000000-0000-4000-8000-000000000000/manifest.json",
      good.files.get(good.manifestPath) as Uint8Array,
    );
    assert.throws(() => packageFromFiles(files), PackageLoadError);
  });

  it("parses the capture record and field controls", () => {
    assert.equal(good.captureRecord?.visitId, good.manifest.visitId);
    assert.equal(good.fieldControls?.visitId, good.manifest.visitId);
  });
});
