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
  pdfText,
  sha256,
  sortPairs,
  squash,
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
    // 2 visit-wide files (spatial report, manifest) + 4 plan files per capture.
    assert.equal(hub.documents.length, 10);

    const uploads = hub.requestsOf("upload");
    assert.equal(uploads.length, 10);
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
    assert.ok(byName(visit, `spatial-report-${test.verdict.verdictId}.pdf`));
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
    assert.equal(uploaded.length, 10);
    // The report is recorded with role spatial_report and its verdict.
    const reportEntry = uploaded.find((f) => f.name.startsWith("spatial-report-"));
    assert.equal(reportEntry?.role, "spatial_report");
    assert.equal(reportEntry?.verdictId, test.verdict.verdictId);
    assert.equal(reportEntry?.path, null);
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
    // Read from storage: the 8 plan files, and the report's sources (field controls, 2 photos;
    // the test package has no capture model). Meshes and LAS are never read.
    assert.equal(test.reads.length, 11);
    assert.deepEqual(
      test.pkg.files
        .filter((f) => ["field_controls", "photo"].includes(f.role))
        .map((f) => f.path)
        .filter((path) => !test.reads.includes(path)),
      [],
    );
    assert.ok(!test.reads.some((path) => /mesh\.glb$|points\.las$/.test(path)));
  });

  it("links the phone's retired spatial report of a legacy package and never uploads it", async () => {
    const test = makeTestPackage({ legacyPhoneReport: true });
    const { hub, store, publisher } = harness();
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "published");
    assert.equal(hub.documents.length, 10);
    assert.ok(!hub.documents.some((doc) => doc.name === "spatial-report.pdf"));
    const legacy = store
      .get(test.pkg.packageId)
      ?.files.filter((f) => f.role === "spatial_report_pdf");
    assert.equal(legacy?.length, 2);
    for (const entry of legacy ?? []) {
      assert.equal(entry.kind, "linked");
      assert.equal(entry.reason, "not_published");
      assert.ok(entry.url?.startsWith(`${REVIEW_BASE_URL}/packages/${test.pkg.packageId}?file=`));
    }
    // The station's report lists them with their station links.
    const report = hub.documents.find((d) => d.name.startsWith("spatial-report-"));
    assert.ok(report);
    const text = squash(await pdfText(report.data));
    for (const entry of legacy ?? []) {
      assert.ok(text.includes(squash(entry.url ?? "")), entry.path ?? "");
    }
  });

  it("hands the rendered report to onReportRendered before uploading it", async () => {
    const test = makeTestPackage();
    const seen: Array<{ sha256: string; uploadsBefore: number; verdictId: string }> = [];
    const { hub, publisher } = harness({
      onReportRendered: async (report, verdict) => {
        seen.push({
          sha256: report.sha256,
          uploadsBefore: hub.requestsOf("upload").length,
          verdictId: verdict.verdictId,
        });
        assert.equal(report.name, `spatial-report-${verdict.verdictId}.pdf`);
        assert.ok(report.pages >= 5);
        assert.ok(report.checksPage >= 2 && report.checksPage <= report.pages);
      },
    });
    await publisher.publish(test.request());
    assert.equal(seen.length, 1);
    assert.equal(seen[0]?.uploadsBefore, 0);
    assert.equal(seen[0]?.verdictId, test.verdict.verdictId);
    const report = hub.documents.find((d) => d.name.startsWith("spatial-report-"));
    assert.equal(report?.sha256, seen[0]?.sha256);
  });

  it("leaves publish() when onReportRendered fails, before any upload", async () => {
    const test = makeTestPackage();
    const { hub, store, publisher } = harness({
      onReportRendered: async () => {
        throw new Error("reports container unavailable");
      },
    });
    await assert.rejects(publisher.publish(test.request()), /reports container unavailable/);
    assert.equal(hub.requestsOf("upload").length, 0);
    assert.notEqual(store.get(test.pkg.packageId)?.status, "publish_failed");
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
      const report = server.hub.documents.find((d) => d.name.startsWith("spatial-report-"));
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
