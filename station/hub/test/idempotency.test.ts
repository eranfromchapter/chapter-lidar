// F9 AC3: retrying a publication after a simulated failure does not duplicate any file.

import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { describe, it } from "node:test";
import { FakeHub } from "../src/fake/index.js";
import { harness, makeTestPackage, sortPairs, storedPairs } from "./helpers.js";

function assertNoDuplicates(hub: FakeHub): void {
  const pairs = sortPairs(storedPairs(hub));
  assert.equal(new Set(pairs).size, pairs.length, `duplicate HUB files: ${pairs.join(", ")}`);
}

describe("publication idempotency", () => {
  it("retries after 503s on upload and uploads every file exactly once", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    hub.failNext({ operation: "upload", status: 503, times: 2 });
    const { store, publisher, sleeps } = harness({ hub });
    const result = await publisher.publish(test.request());

    assert.equal(result.status, "published");
    assert.equal(result.attempts, 3);
    assert.deepEqual(sleeps, [2000, 4000]);
    assertNoDuplicates(hub);
    assert.deepEqual(sortPairs(storedPairs(hub)), sortPairs(test.expectedUploads()));
    assert.equal(store.get(test.pkg.packageId)?.attempts, 3);
  });

  it("does not upload again a file the HUB stored before the answer was lost", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    // The first upload is stored, but the station gets a 503 instead of the answer.
    hub.failNext({ operation: "upload", status: 503, times: 1, afterStore: true });
    const { store, publisher } = harness({ hub });
    const result = await publisher.publish(test.request());

    assert.equal(result.status, "published");
    assert.equal(result.attempts, 2);
    assertNoDuplicates(hub);
    assert.deepEqual(sortPairs(storedPairs(hub)), sortPairs(test.expectedUploads()));
    const recovered =
      store.get(test.pkg.packageId)?.files.filter((f) => f.foundBySearch === true) ?? [];
    assert.equal(recovered.length, 1);
    assert.equal(hub.storedUploads().length, 12);
  });

  it("a re-run after a failed publication uploads only what is missing", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    const first = harness({ hub });
    // Five files go through, then the HUB refuses (400 is not retried).
    let count = 0;
    const api = first.api;
    const counting = {
      getDeal: api.getDeal.bind(api),
      searchDocuments: api.searchDocuments.bind(api),
      uploadDocument: async (upload: Parameters<typeof api.uploadDocument>[0]) => {
        count += 1;
        if (count === 6) {
          hub.failNext({
            operation: "upload",
            status: 400,
            times: 1,
            message: "Folder not allowed",
          });
        }
        return api.uploadDocument(upload);
      },
    };
    const failing = harness({ hub, api: counting });
    const failed = await failing.publisher.publish(test.request());
    assert.equal(failed.status, "publish_failed");
    assert.equal(failing.store.get(test.pkg.packageId)?.error?.status, 400);
    assert.equal(hub.documents.length, 5);

    // Manual re-run with the same store (the hub_publications row).
    const rerun = harness({ hub, store: failing.store });
    const result = await rerun.publisher.publish(test.request());
    assert.equal(result.status, "published");
    assertNoDuplicates(hub);
    assert.deepEqual(sortPairs(storedPairs(hub)), sortPairs(test.expectedUploads()));
    // 5 + 1 refused + 7 remaining upload requests.
    assert.equal(hub.requestsOf("upload").length, 13);
  });

  it("a new verdict for the same package uploads only its new report", async () => {
    const test = makeTestPackage();
    const { hub, store, publisher } = harness();
    await publisher.publish(test.request());
    const before = hub.documents.length;

    const newVerdict = {
      ...test.verdict,
      verdictId: randomUUID(),
      evaluatedAt: "2026-10-17T16:00:00Z",
    };
    const result = await publisher.publish(test.request({ verdict: newVerdict }));
    assert.equal(result.status, "published");
    assert.equal(hub.documents.length, before + 1);
    assert.ok(hub.documents.some((d) => d.name === `verdict-report-${newVerdict.verdictId}.pdf`));
    assertNoDuplicates(hub);
    assert.equal(store.get(test.pkg.packageId)?.verdictId, newVerdict.verdictId);
  });

  it("a retry never re-reads or re-sends files already recorded", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    const { publisher } = harness({ hub });
    // Fail the verification searches of the first attempt only (after all uploads).
    let uploadsDone = false;
    const originalHandle = hub.handle.bind(hub);
    hub.handle = async (request: Request) => {
      if (
        uploadsDone &&
        request.method === "GET" &&
        new URL(request.url).pathname.endsWith("/documents")
      ) {
        uploadsDone = false;
        return new Response(JSON.stringify({ message: "busy" }), { status: 503 });
      }
      const response = await originalHandle(request);
      if (request.method === "POST" && hub.documents.length === 12) {
        uploadsDone = true;
      }
      return response;
    };
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "published");
    assert.equal(result.attempts, 2);
    assert.equal(test.reads.length, 10);
    assert.equal(hub.requestsOf("upload").length, 12);
    assertNoDuplicates(hub);
  });
});
