// F9 AC2: files over 45 MB are never uploaded and appear in the report as authenticated links.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { FAKE_HUB_MAX_UPLOAD_BYTES, startFakeHubServer } from "../src/fake/index.js";
import { HubError, LiveHubApi, MAX_HUB_UPLOAD_BYTES, pdfSafeText } from "../src/index.js";
import { MIB, REVIEW_BASE_URL, harness, makeTestPackage, pdfText, squash } from "./helpers.js";

describe("large files", () => {
  it("the upload limit is 45 MiB", () => {
    assert.equal(MAX_HUB_UPLOAD_BYTES, 45 * 1024 * 1024);
  });

  it("links a plan file over 45 MiB in the report instead of uploading it", async () => {
    const test = makeTestPackage({ planPdfBytes: 45 * MIB + 1 });
    const { hub, store, publisher } = harness();
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "published");

    const big = test.pkg.files.find((f) => f.role === "plan_pdf" && f.areaKey === "floor-1");
    assert.ok(big);
    const bigFolder = `Capture/floor-1/${big.captureId}/r1`;
    // Never uploaded, never even read.
    assert.equal(
      hub
        .requestsOf("upload")
        .some((r) => r.folder === bigFolder && r.fileNames?.includes("plan.pdf")),
      false,
    );
    assert.equal(
      hub.documents.some((d) => d.folder === bigFolder && d.name === "plan.pdf"),
      false,
    );
    assert.equal(test.reads.includes(big.path), false);
    assert.ok(hub.documents.every((d) => d.bytes <= MAX_HUB_UPLOAD_BYTES));

    // Recorded as a linked file with an authenticated station link (no public link).
    const url = `${REVIEW_BASE_URL}/packages/${test.pkg.packageId}?file=${encodeURIComponent(big.path)}`;
    const entry = store.get(test.pkg.packageId)?.files.find((f) => f.path === big.path);
    assert.equal(entry?.kind, "linked");
    assert.equal(entry?.reason, "too_large");
    assert.equal(entry?.url, url);
    assert.ok(!url.includes("sig="), "not a SAS link");

    // The report lists it with that link and says sign-in is required.
    const report = hub.documents.find((d) => d.name.startsWith("spatial-report-"));
    assert.ok(report);
    const text = squash(await pdfText(report.data));
    assert.ok(text.includes(squash(url)), "report holds the station link");
    assert.ok(text.includes(squash(big.path)), "report names the file");
    assert.ok(text.includes(big.sha256), "report holds the SHA-256");
    assert.ok(text.includes(squash(pdfSafeText("Not uploaded (over 45.0 MiB"))));
    assert.ok(text.includes(squash("Entra sign-in required")));
  });

  it("uploads a plan file of exactly 45 MiB", async () => {
    const test = makeTestPackage({ planPdfBytes: 45 * MIB });
    const { hub, publisher } = harness();
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "published");
    const big = test.pkg.files.find((f) => f.role === "plan_pdf" && f.areaKey === "floor-1");
    const stored = hub.documents.find(
      (d) => d.folder === `Capture/floor-1/${big?.captureId}/r1` && d.name === "plan.pdf",
    );
    assert.equal(stored?.bytes, 45 * MIB);
  });

  it("links meshes, LAS and photos in the report with authenticated links", async () => {
    const test = makeTestPackage();
    const { hub, publisher } = harness();
    await publisher.publish(test.request());
    const report = hub.documents.find((d) => d.name.startsWith("spatial-report-"));
    assert.ok(report);
    const text = squash(await pdfText(report.data));
    for (const file of test.pkg.files.filter((f) =>
      ["mesh_glb", "point_cloud_las", "photo"].includes(f.role),
    )) {
      const url = `${REVIEW_BASE_URL}/packages/${test.pkg.packageId}?file=${encodeURIComponent(file.path)}`;
      assert.ok(text.includes(squash(url)), file.path);
    }
  });

  it("the fake HUB server refuses an upload over 50 MB with 413 and stores nothing", async () => {
    const server = await startFakeHubServer();
    try {
      const api = new LiveHubApi({ baseUrl: server.url, credential: server.hub.credential });
      await assert.rejects(
        api.uploadDocument({
          dealId: "fixture-deal-0001",
          folder: "Capture/test/r1",
          name: "too-big.bin",
          contentType: "application/octet-stream",
          data: new Uint8Array(FAKE_HUB_MAX_UPLOAD_BYTES + 1),
        }),
        (error: unknown) =>
          error instanceof HubError && (error.status === 413 || error.failure === "network"),
      );
      assert.equal(server.hub.documents.length, 0);
      assert.equal(server.hub.requests.at(-1)?.status, 413);
    } finally {
      await server.close();
    }
  });

  it("the in-process fake refuses a file over 50 MB with 413", async () => {
    const { api, hub } = harness();
    await assert.rejects(
      api.uploadDocument({
        dealId: "fixture-deal-0001",
        folder: "Capture/test/r1",
        name: "too-big.bin",
        contentType: "application/octet-stream",
        data: new Uint8Array(FAKE_HUB_MAX_UPLOAD_BYTES + 1),
      }),
      (error: unknown) => error instanceof HubError && error.status === 413 && !error.retryable,
    );
    assert.equal(hub.documents.length, 0);
  });
});
