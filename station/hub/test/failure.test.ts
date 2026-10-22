// F9 AC4: after 5 failed attempts the HUB publication status is publish_failed with the HUB
// error stored.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { FakeHub } from "../src/fake/index.js";
import type { HubApi } from "../src/index.js";
import { harness, makeTestPackage } from "./helpers.js";

describe("publication failure", () => {
  it("stops after 5 attempts with exponential backoff and stores the HUB error", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    hub.failNext({
      operation: "upload",
      status: 503,
      times: 100,
      message: "HUB maintenance window",
    });
    const { store, publisher, sleeps } = harness({ hub });
    const result = await publisher.publish(test.request());

    assert.equal(result.status, "publish_failed");
    assert.equal(result.attempts, 5);
    assert.deepEqual(sleeps, [2000, 4000, 8000, 16000]);
    const row = store.get(test.pkg.packageId);
    assert.equal(row?.status, "publish_failed");
    assert.equal(row?.attempts, 5);
    assert.deepEqual(row?.error, {
      status: 503,
      message: "HUB answered 503: HUB maintenance window",
    });
    assert.equal(hub.documents.length, 0);
    assert.equal(hub.requestsOf("upload").length, 5);
  });

  it("caps the backoff and honours Retry-After on 429", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    hub.failNext({ operation: "upload", status: 429, times: 2, retryAfterSeconds: 7 });
    const { publisher, sleeps } = harness({ hub, maxDelayMs: 10_000 });
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "published");
    assert.deepEqual(sleeps, [7000, 7000]);
  });

  it("fails at once on a 4xx other than 429", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    hub.failNext({
      operation: "upload",
      status: 400,
      times: 1,
      message: "Folder name not allowed",
    });
    const { store, publisher, sleeps } = harness({ hub });
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "publish_failed");
    assert.equal(result.attempts, 1);
    assert.deepEqual(sleeps, []);
    assert.deepEqual(store.get(test.pkg.packageId)?.error, {
      status: 400,
      message: "HUB answered 400: Folder name not allowed",
    });
  });

  it("retries network errors and fails with status null after 5 attempts", async () => {
    const test = makeTestPackage();
    const { api } = harness();
    const broken: HubApi = {
      getDeal: api.getDeal.bind(api),
      searchDocuments: api.searchDocuments.bind(api),
      uploadDocument: async () => {
        const { HubError } = await import("../src/index.js");
        throw new HubError("network", "HUB request failed before an answer (network error)");
      },
    };
    const { store, publisher } = harness({ api: broken });
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "publish_failed");
    assert.equal(result.attempts, 5);
    assert.deepEqual(store.get(test.pkg.packageId)?.error, {
      status: null,
      message: "HUB request failed before an answer (network error)",
    });
  });

  it("fails after 5 attempts when the document search never finds an upload, without re-uploading", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    const { api } = harness({ hub });
    const blind: HubApi = {
      getDeal: api.getDeal.bind(api),
      uploadDocument: api.uploadDocument.bind(api),
      searchDocuments: async () => [],
    };
    const { store, publisher } = harness({ hub, api: blind });
    const result = await publisher.publish(test.request());
    assert.equal(result.status, "publish_failed");
    assert.equal(result.attempts, 5);
    const error = store.get(test.pkg.packageId)?.error;
    assert.equal(error?.status, null);
    assert.match(error?.message ?? "", /not found by the HUB document search/);
    assert.equal(hub.requestsOf("upload").length, 10, "each file uploaded once");
  });

  it("never stores the service credential in the error", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    hub.failNext({
      operation: "upload",
      status: 401,
      times: 1,
      message: `Bad token Bearer ${hub.credential} for ${hub.credential}`,
    });
    const { store, publisher } = harness({ hub });
    await publisher.publish(test.request());
    const error = store.get(test.pkg.packageId)?.error;
    assert.equal(error?.status, 401);
    assert.ok(!JSON.stringify(error).includes(hub.credential));
    assert.ok(!JSON.stringify(hub.requests).includes(hub.credential));
  });

  it("truncates long HUB messages", async () => {
    const test = makeTestPackage();
    const hub = new FakeHub();
    hub.failNext({ operation: "upload", status: 400, times: 1, message: "x".repeat(5000) });
    const { store, publisher } = harness({ hub });
    await publisher.publish(test.request());
    const message = store.get(test.pkg.packageId)?.error?.message ?? "";
    assert.ok(message.length <= 500);
  });

  it("fails without uploading when a package file no longer matches its SHA-256", async () => {
    const test = makeTestPackage();
    const { hub, store, publisher } = harness();
    const result = await publisher.publish(
      test.request({ readFile: async () => new TextEncoder().encode("tampered") }),
    );
    assert.equal(result.status, "publish_failed");
    assert.equal(result.attempts, 1);
    assert.match(store.get(test.pkg.packageId)?.error?.message ?? "", /SHA-256/);
    assert.ok(hub.documents.every((d) => !d.name.endsWith(".dxf")));
  });
});
