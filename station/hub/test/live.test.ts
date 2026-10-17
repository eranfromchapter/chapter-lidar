// LiveHubApi: credential handling, fail-closed parsing, redirects and the deal lookup.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { FAKE_DEAL_ADDRESS, FAKE_DEAL_ID, FakeHub, startFakeHubServer } from "../src/fake/index.js";
import { HubError, LiveHubApi, scrub } from "../src/index.js";

const CREDENTIAL = "s3cr3t-credential-value";

function stubFetch(handler: (url: URL, init: RequestInit) => Response): {
  fetch: typeof fetch;
  calls: Array<{ url: URL; init: RequestInit }>;
} {
  const calls: Array<{ url: URL; init: RequestInit }> = [];
  return {
    calls,
    fetch: (async (input: string | URL | Request, init?: RequestInit) => {
      const url = new URL(input instanceof Request ? input.url : input.toString());
      calls.push({ url, init: init ?? {} });
      return handler(url, init ?? {});
    }) as typeof fetch,
  };
}

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

describe("LiveHubApi", () => {
  it("reads the deal's confirmed address from the deals list", async () => {
    const server = await startFakeHubServer();
    try {
      const api = new LiveHubApi({ baseUrl: server.url, credential: server.hub.credential });
      const deal = await api.getDeal(FAKE_DEAL_ID);
      assert.deepEqual(deal, {
        dealId: FAKE_DEAL_ID,
        address: FAKE_DEAL_ADDRESS,
        projectName: "Fixture project",
      });
      assert.equal(await api.getDeal("fixture-deal-0003"), null, "unconfirmed address");
      assert.equal(await api.getDeal("no-such-deal"), null);
    } finally {
      await server.close();
    }
  });

  it("sends the credential only in the mapped header", async () => {
    const stub = stubFetch(() => jsonResponse([]));
    const api = new LiveHubApi({
      baseUrl: "https://hub.example.test/base",
      credential: CREDENTIAL,
      fetch: stub.fetch,
    });
    await api.searchDocuments("deal-1", "plan.dxf");
    const call = stub.calls[0];
    assert.ok(call);
    assert.equal(new Headers(call.init.headers).get("authorization"), `Bearer ${CREDENTIAL}`);
    assert.equal(
      call.url.toString(),
      "https://hub.example.test/base/api/projects/deal-1/documents?search=plan.dxf",
    );
    assert.ok(!call.url.toString().includes(CREDENTIAL));
    assert.equal(call.init.redirect, "manual");
  });

  it("fails closed on unexpected shapes", async () => {
    const stub = stubFetch((url) =>
      url.pathname.endsWith("/deals") ? jsonResponse({ deals: [] }) : jsonResponse({ items: [] }),
    );
    const api = new LiveHubApi({
      baseUrl: "https://hub.example.test",
      credential: CREDENTIAL,
      fetch: stub.fetch,
    });
    await assert.rejects(
      api.getDeal("deal-1"),
      (e: unknown) => e instanceof HubError && e.failure === "unexpected_shape" && !e.retryable,
    );
    await assert.rejects(
      api.searchDocuments("deal-1", "x"),
      (e: unknown) => e instanceof HubError && e.failure === "unexpected_shape",
    );
    const nameless = stubFetch(() => jsonResponse([{ id: 1 }]));
    const api2 = new LiveHubApi({
      baseUrl: "https://hub.example.test",
      credential: CREDENTIAL,
      fetch: nameless.fetch,
    });
    await assert.rejects(
      api2.searchDocuments("deal-1", "x"),
      (e: unknown) => e instanceof HubError && e.failure === "unexpected_shape",
    );
  });

  it("refuses redirects and keeps errors free of the credential", async () => {
    const stub = stubFetch(
      () =>
        new Response(null, {
          status: 302,
          headers: { location: `https://evil.test/?k=${CREDENTIAL}` },
        }),
    );
    const api = new LiveHubApi({
      baseUrl: "https://hub.example.test",
      credential: CREDENTIAL,
      fetch: stub.fetch,
    });
    await assert.rejects(api.getDeal("deal-1"), (e: unknown) => {
      assert.ok(e instanceof HubError);
      assert.equal(e.failure, "redirect");
      assert.ok(
        !JSON.stringify({ m: e.message, h: e.hubMessage, s: e.stack }).includes(CREDENTIAL),
      );
      return true;
    });
    const echo = stubFetch(() =>
      jsonResponse({ message: `token ${CREDENTIAL} is not valid; Bearer ${CREDENTIAL}` }, 403),
    );
    const api2 = new LiveHubApi({
      baseUrl: "https://hub.example.test",
      credential: CREDENTIAL,
      fetch: echo.fetch,
    });
    await assert.rejects(api2.getDeal("deal-1"), (e: unknown) => {
      assert.ok(e instanceof HubError);
      assert.equal(e.status, 403);
      assert.ok(!`${e.message} ${e.hubMessage}`.includes(CREDENTIAL));
      return true;
    });
  });

  it("classifies network failures as retryable without leaking details", async () => {
    const api = new LiveHubApi({
      baseUrl: "https://hub.example.test",
      credential: CREDENTIAL,
      fetch: (async () => {
        throw new TypeError(`fetch failed ${CREDENTIAL}`);
      }) as typeof fetch,
    });
    await assert.rejects(api.getDeal("deal-1"), (e: unknown) => {
      assert.ok(e instanceof HubError);
      assert.equal(e.failure, "network");
      assert.ok(e.retryable);
      assert.ok(!e.message.includes(CREDENTIAL));
      return true;
    });
  });

  it("rejects an unusable credential with a fixed message", () => {
    assert.throws(
      () => new LiveHubApi({ baseUrl: "https://hub.example.test", credential: "has space" }),
      (e: unknown) => e instanceof Error && !e.message.includes("has space"),
    );
    assert.throws(
      () => new LiveHubApi({ baseUrl: "https://user:pw@hub.example.test", credential: CREDENTIAL }),
    );
  });

  it("reads an optional document id from the upload answer", async () => {
    const hub = new FakeHub();
    const api = new LiveHubApi({
      baseUrl: "http://hub.test",
      credential: hub.credential,
      fetch: hub.fetch,
    });
    const result = await api.uploadDocument({
      dealId: FAKE_DEAL_ID,
      folder: "Capture/a/r1",
      name: "a.txt",
      contentType: "text/plain",
      data: new TextEncoder().encode("hello"),
    });
    assert.equal(result.documentId, hub.documents[0]?.documentId);
    assert.equal(hub.documents[0]?.folder, "Capture/a/r1");
  });

  it("scrub removes secrets, tokens and query strings", () => {
    const text = scrub(
      `x ${CREDENTIAL} Bearer abc.def https://h.test/p?sig=1&x=2 AccountKey=zzz; eyJhbGciOiJIUzI1.eyJzdWIiOiIx.c2ln`,
      [CREDENTIAL],
    );
    assert.ok(!text.includes(CREDENTIAL));
    assert.ok(!text.includes("abc.def"));
    assert.ok(!text.includes("sig=1"));
    assert.ok(!text.includes("zzz"));
    assert.ok(!text.includes("eyJhbGciOiJIUzI1"));
  });
});
