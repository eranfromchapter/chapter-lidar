// The 10-minute HUB cache: hits, misses, expiry, failures and concurrency.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { CachedHubClient, HUB_CACHE_TTL_MS } from "../../src/hub/cache.js";
import { createHubClient } from "../../src/hub/service.js";
import { HubError, type HubProject } from "../../src/hub/types.js";
import { testConfig } from "../core/helpers.js";
import { CountingHubClient, TestClock } from "./helpers.js";

const PROJECTS: readonly HubProject[] = [
  { dealId: "deal-1", address: { formatted: "1 Main Street" }, updatedAtMs: 2 },
  { dealId: "deal-2", address: { formatted: "2 Main Street" }, updatedAtMs: 1 },
];

function setup(): { inner: CountingHubClient; clock: TestClock; cache: CachedHubClient } {
  const inner = new CountingHubClient(PROJECTS);
  const clock = new TestClock();
  return { inner, clock, cache: new CachedHubClient(inner, { now: clock.now }) };
}

describe("CachedHubClient", () => {
  it("uses a 10-minute TTL", () => {
    assert.equal(HUB_CACHE_TTL_MS, 600_000);
  });

  it("asks the HUB on a miss and answers from the cache on a hit", async () => {
    const { inner, clock, cache } = setup();
    assert.deepEqual(await cache.listProjects(), PROJECTS);
    assert.equal(inner.listCalls, 1);
    clock.advance(HUB_CACHE_TTL_MS - 1);
    assert.deepEqual(await cache.listProjects(), PROJECTS);
    assert.equal(inner.listCalls, 1, "a fresh list must not call the HUB again");
  });

  it("asks the HUB again once 10 minutes have passed", async () => {
    const { inner, clock, cache } = setup();
    await cache.listProjects();
    clock.advance(HUB_CACHE_TTL_MS);
    inner.projects = [PROJECTS[1] as HubProject];
    assert.deepEqual(
      (await cache.listProjects()).map((project) => project.dealId),
      ["deal-2"],
    );
    assert.equal(inner.listCalls, 2);
  });

  it("treats an entry from the future (clock moved back) as stale", async () => {
    const { inner, clock, cache } = setup();
    await cache.listProjects();
    clock.advance(-1);
    await cache.listProjects();
    assert.equal(inner.listCalls, 2);
  });

  it("never caches a failure", async () => {
    const { inner, cache } = setup();
    inner.fail = true;
    await assert.rejects(cache.listProjects(), HubError);
    await assert.rejects(cache.getProject("deal-1"), HubError);
    inner.fail = false;
    assert.deepEqual(await cache.listProjects(), PROJECTS);
    assert.equal((await cache.getProject("deal-1"))?.dealId, "deal-1");
    assert.equal(inner.listCalls, 2);
  });

  it("shares one HUB call between concurrent callers", async () => {
    const { inner, cache } = setup();
    const results = await Promise.all([cache.listProjects(), cache.listProjects()]);
    assert.equal(inner.listCalls, 1);
    assert.deepEqual(results[0], results[1]);
    await Promise.all([cache.getProject("deal-9"), cache.getProject("deal-9")]);
    assert.equal(inner.getCalls, 1);
  });

  it("answers single-deal lookups from a fresh list", async () => {
    const { inner, cache } = setup();
    await cache.listProjects();
    assert.equal((await cache.getProject("deal-2"))?.dealId, "deal-2");
    assert.equal(inner.getCalls, 0);
  });

  it("caches single-deal lookups, including unknown deals, for 10 minutes", async () => {
    const { inner, clock, cache } = setup();
    assert.equal((await cache.getProject("deal-1"))?.dealId, "deal-1");
    assert.equal(await cache.getProject("missing"), null);
    clock.advance(HUB_CACHE_TTL_MS - 1);
    assert.equal((await cache.getProject("deal-1"))?.dealId, "deal-1");
    assert.equal(await cache.getProject("missing"), null);
    assert.equal(inner.getCalls, 2);
    clock.advance(1);
    await cache.getProject("deal-1");
    await cache.getProject("missing");
    assert.equal(inner.getCalls, 4);
  });

  it("looks up a deal the fresh list does not contain", async () => {
    const { inner, cache } = setup();
    await cache.listProjects();
    inner.projects = [...PROJECTS, { dealId: "deal-3", address: { formatted: "3 Main Street" } }];
    assert.equal((await cache.getProject("deal-3"))?.dealId, "deal-3");
    assert.equal(inner.getCalls, 1);
  });

  it("keeps at most maxDeals single-deal entries", async () => {
    const inner = new CountingHubClient(PROJECTS);
    const clock = new TestClock();
    const cache = new CachedHubClient(inner, { now: clock.now, maxDeals: 2 });
    await cache.getProject("a");
    await cache.getProject("b");
    await cache.getProject("c");
    assert.equal(inner.getCalls, 3);
    await cache.getProject("c");
    await cache.getProject("b");
    assert.equal(inner.getCalls, 3, "the two newest entries stay cached");
    await cache.getProject("a");
    assert.equal(inner.getCalls, 4, "the oldest entry was dropped");
  });
});

describe("createHubClient", () => {
  it("builds a cached fake client in fake mode", async () => {
    const hub = createHubClient(testConfig({ HUB_MODE: "fake" }).hub);
    assert.ok(hub instanceof CachedHubClient);
    assert.equal((await hub.getProject("fixture-deal-0001"))?.dealId, "fixture-deal-0001");
  });

  it("builds a cached live client that uses the configured URL and credential", async () => {
    const config = testConfig({
      HUB_MODE: "live",
      HUB_BASE_URL: "https://hub.example.test/",
      HUB_SERVICE_CREDENTIAL: "test-hub-credential-value",
    });
    const seen: { url: string; authorization: string | null }[] = [];
    const hub = createHubClient(config.hub, {
      fetch: async (input, init) => {
        seen.push({
          url: String(input),
          authorization: new Headers(init?.headers).get("authorization"),
        });
        return Response.json([]);
      },
    });
    assert.ok(hub instanceof CachedHubClient);
    assert.deepEqual(await hub.listProjects(), []);
    await hub.listProjects();
    assert.deepEqual(seen, [
      {
        url: "https://hub.example.test/api/sales/deals",
        authorization: "Bearer test-hub-credential-value",
      },
    ]);
  });
});
