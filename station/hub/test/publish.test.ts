// F9 AC1: publishing a verdict uploads exactly the listed files to the right folder using the
// dealId.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { FakeHub, FAKE_PROJECT_RECORD_ID, startFakeHubServer } from "../src/fake/index.js";
import { HubPublisher, LiveHubApi, MemoryPublicationStore } from "../src/index.js";
import {
  REVIEW_BASE_URL,
  harness,
  makeTestPackage,
  sha256,
  sortPairs,
  storedPairs,
} from "./helpers.js";

describe("HubPublisher publish", () => {
  it("uploads exactly the report, the manifest and the plan files into their folders", async () => {
    const test = makeTestPackage();
    const { hub, store, publisher } = harness();
    const result = await publisher.publish(test.request());

    assert.equal(result.status, "published");
    assert.equal(result.attempts, 1);
    assert.deepEqual(sortPairs(storedPairs(hub)), sortPairs(test.expectedUploads()));
    // 2 visit-wide files + 5 plan files per capture.
    assert.equal(hub.documents.length, 12);

    const uploads = hub.requestsOf("upload");
    assert.equal(uploads.length, 12);
    for (const upload of uploads) {
      assert.equal(upload.status, 201);
      assert.equal(upload.dealId, test.pkg.dealId);
      assert.equal(
        upload.path,
        `/api/projects/${encodeURIComponent(test.pkg.dealId)}/document-media/upload`,
      );
      assert.equal(upload.fileNames?.length, 1);
    }

    // Visit-wide files in Capture/<visitId>/r<revision>, plan files per capture.
    const visit = `Capture/${test.pkg.visitId}/r1`;
    const byName = (folder: string, name: string) =>
      hub.documents.find((doc) => doc.folder === folder && doc.name === name);
    assert.ok(byName(visit, "manifest.json"));
    assert.ok(byName(visit, `verdict-report-${test.verdict.verdictId}.pdf`));
    for (const file of test.pkg.files.filter((f) => f.role === "plan_dxf")) {
      assert.ok(byName(`Capture/${file.areaKey}/${file.captureId}/r1`, "plan.dxf"));
    }

    // Bytes in the HUB are the package bytes.
    const manifest = byName(visit, "manifest.json");
    assert.equal(manifest?.sha256, test.pkg.manifestSha256);
    assert.equal(manifest?.contentType.startsWith("application/json"), true);
    for (const file of test.pkg.files) {
      const doc = hub.documents.find(
        (d) => d.name === file.path.split("/").pop() && d.folder.includes(file.captureId ?? "-"),
      );
      if (doc !== undefined) {
        assert.equal(doc.sha256, file.sha256, file.path);
      }
    }

    // Meshes, LAS, photos, capture record and field controls are never uploaded: linked.
    const row = store.get(test.pkg.packageId);
    assert.equal(row?.status, "published");
    assert.equal(row?.error, null);
    const uploaded = row?.files.filter((f) => f.kind === "uploaded") ?? [];
    const linked = row?.files.filter((f) => f.kind === "linked") ?? [];
    assert.equal(uploaded.length, 12);
    assert.deepEqual(linked.map((f) => f.role).sort(), [
      "capture_record",
      "field_controls",
      "mesh_glb",
      "mesh_glb",
      "photo",
      "photo",
      "point_cloud_las",
      "point_cloud_las",
    ]);
    for (const file of linked) {
      assert.equal(
        file.url,
        `${REVIEW_BASE_URL}/packages/${test.pkg.packageId}?file=${encodeURIComponent(file.path ?? "")}`,
      );
    }
    for (const file of uploaded) {
      assert.match(file.sha256, /^[0-9a-f]{64}$/);
      assert.ok(file.documentId, "HUB document id recorded");
    }
    // Only the plan files were read from storage.
    assert.equal(test.reads.length, 10);
  });

  it("verifies every upload through the document search", async () => {
    const test = makeTestPackage();
    const { hub, publisher } = harness();
    await publisher.publish(test.request());
    const searched = new Set(hub.requestsOf("search").map((r) => r.search));
    for (const expected of test.expectedUploads()) {
      assert.ok(searched.has(expected.name), `searched for ${expected.name}`);
    }
  });

  it("does nothing more when the same verdict is already published", async () => {
    const test = makeTestPackage();
    const { hub, publisher } = harness();
    await publisher.publish(test.request());
    const before = hub.requests.length;
    const again = await publisher.publish(test.request());
    assert.equal(again.status, "published");
    assert.equal(again.alreadyPublished, true);
    assert.equal(hub.requests.length, before);
  });

  it("publishes over HTTP to the fake HUB server with the service credential", async () => {
    const server = await startFakeHubServer();
    try {
      const test = makeTestPackage();
      const api = new LiveHubApi({ baseUrl: server.url, credential: server.hub.credential });
      const store = new MemoryPublicationStore();
      const publisher = new HubPublisher({ hub: api, store, reviewBaseUrl: REVIEW_BASE_URL });
      const result = await publisher.publish(test.request());
      assert.equal(result.status, "published");
      assert.deepEqual(sortPairs(storedPairs(server.hub)), sortPairs(test.expectedUploads()));
      assert.ok(server.hub.requests.every((r) => r.authorized));
      const report = server.hub.documents.find((d) => d.name.startsWith("verdict-report-"));
      assert.ok(report);
      assert.equal(report.sha256, sha256(report.data));
    } finally {
      await server.close();
    }
  });

  it("is refused by the HUB for a project record id instead of a dealId", async () => {
    const test = makeTestPackage({ dealId: FAKE_PROJECT_RECORD_ID });
    const hub = new FakeHub({
      deals: [{ dealId: FAKE_PROJECT_RECORD_ID, address: "x", addressConfirmed: true }],
    });
    const { store, publisher } = harness({ hub });
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "publish_failed");
    assert.equal(result.attempts, 1);
    assert.equal(store.get(test.pkg.packageId)?.error?.status, 400);
    assert.equal(hub.documents.length, 0);
  });

  it("never sends a dealId that breaks the DealId rule", async () => {
    const test = makeTestPackage({ dealId: "d".repeat(65) });
    const { hub, store, publisher } = harness();
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "publish_failed");
    assert.equal(hub.requests.length, 0);
    assert.match(store.get(test.pkg.packageId)?.error?.message ?? "", /dealId/);
  });

  it("the fake HUB rejects dealIds outside 1 to 64 characters", async () => {
    const hub = new FakeHub();
    const long = encodeURIComponent("d".repeat(65));
    const response = await hub.fetch(`http://hub.test/api/projects/${long}/documents?search=x`, {
      headers: { authorization: `Bearer ${hub.credential}` },
    });
    assert.equal(response.status, 400);
    const unknown = await hub.fetch(
      "http://hub.test/api/projects/no-such-deal/documents?search=x",
      {
        headers: { authorization: `Bearer ${hub.credential}` },
      },
    );
    assert.equal(unknown.status, 404);
    const unauthorized = await hub.fetch("http://hub.test/api/sales/deals");
    assert.equal(unauthorized.status, 401);
  });
});
