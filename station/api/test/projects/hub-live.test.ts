// The live HubClient: request shape, field mapping, the confirmed-address filter, every
// failure mapped to HubError, and the credential never leaving the Authorization header.

import assert from "node:assert/strict";
import { createServer, type IncomingHttpHeaders, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { after, before, describe, it } from "node:test";
import { inspect } from "node:util";
import { LiveHubClient } from "../../src/hub/live.js";
import { HUB_API_MAPPING, type HubApiMapping } from "../../src/hub/mapping.js";
import { HubError } from "../../src/hub/types.js";

const CREDENTIAL = "live-test-credential-0123456789";
const BASE_URL = "https://hub.example.test/base";

interface Call {
  url: string;
  init: RequestInit | undefined;
}

function stubFetch(answer: (call: Call) => Response | Promise<Response>): {
  fetch: typeof fetch;
  calls: Call[];
} {
  const calls: Call[] = [];
  return {
    calls,
    fetch: async (input, init) => {
      const call = { url: String(input), init };
      calls.push(call);
      return answer(call);
    },
  };
}

function deal(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    dealId: "D-100",
    id: "project-record-7",
    name: "Smith kitchen",
    address: "12 Example Lane, Brooklyn, NY 11201",
    addressConfirmed: true,
    updatedAt: "2026-10-10T10:00:00Z",
    ...overrides,
  };
}

function client(fetchImpl: typeof fetch, extra: Partial<HubApiMapping> = {}): LiveHubClient {
  return new LiveHubClient({
    baseUrl: BASE_URL,
    credential: CREDENTIAL,
    fetch: fetchImpl,
    mapping: { ...HUB_API_MAPPING, ...extra },
  });
}

async function hubFailure(promise: Promise<unknown>): Promise<HubError> {
  try {
    await promise;
  } catch (error) {
    assert.ok(error instanceof HubError, `expected HubError, got ${String(error)}`);
    assert.ok(!error.message.includes(CREDENTIAL));
    assert.ok(!error.reason.includes(CREDENTIAL));
    assert.ok(!inspect(error, { depth: 5 }).includes(CREDENTIAL));
    return error;
  }
  assert.fail("expected the call to fail");
}

describe("LiveHubClient requests", () => {
  it("GETs the sales deals path under the base URL with the credential as a bearer token", async () => {
    const stub = stubFetch(() => Response.json([deal()]));
    await client(stub.fetch).listProjects();
    assert.equal(stub.calls.length, 1);
    const call = stub.calls[0];
    assert.ok(call);
    assert.equal(call.url, "https://hub.example.test/base/api/sales/deals");
    assert.equal(call.init?.method, "GET");
    assert.equal(
      call.init?.redirect,
      "manual",
      "redirects must not be followed with the credential",
    );
    assert.ok(call.init?.signal instanceof AbortSignal);
    const headers = new Headers(call.init?.headers);
    assert.equal(headers.get("authorization"), `Bearer ${CREDENTIAL}`);
    assert.equal(headers.get("accept"), "application/json");
  });

  it("uses the mapping's header and scheme", async () => {
    const stub = stubFetch(() => Response.json([]));
    await client(stub.fetch, { auth: { header: "x-api-key", scheme: null } }).listProjects();
    const headers = new Headers(stub.calls[0]?.init?.headers);
    assert.equal(headers.get("x-api-key"), CREDENTIAL);
    assert.equal(headers.get("authorization"), null);
  });

  it("refuses a list path that leaves the HUB host", () => {
    assert.throws(
      () =>
        client(fetch, { listDeals: { path: "https://elsewhere.example/deals", itemsPath: null } }),
      /must stay on the HUB base URL's host/,
    );
  });

  it("refuses an unusable credential without echoing it", () => {
    for (const credential of ["", "has space", "line\nbreak"]) {
      assert.throws(
        () => new LiveHubClient({ baseUrl: BASE_URL, credential }),
        (error: Error) =>
          /credential must be/.test(error.message) &&
          (credential === "" || !error.message.includes(credential)),
      );
    }
  });

  it("refuses a base URL with credentials or a query", () => {
    for (const baseUrl of ["https://user:pw@hub.example.test", "https://hub.example.test/?k=v"]) {
      assert.throws(() => new LiveHubClient({ baseUrl, credential: CREDENTIAL }), /must not carry/);
    }
  });

  it("keeps the credential out of the client's inspectable state", () => {
    const hub = new LiveHubClient({ baseUrl: BASE_URL, credential: CREDENTIAL });
    assert.ok(!inspect(hub, { depth: 5, showHidden: true }).includes(CREDENTIAL));
    assert.ok(!JSON.stringify(hub).includes(CREDENTIAL));
  });
});

describe("LiveHubClient mapping", () => {
  it("maps deals to projects keyed by the sales dealId, confirmed addresses only", async () => {
    const warnings: { details: Record<string, unknown>; message: string }[] = [];
    const stub = stubFetch(() =>
      Response.json([
        deal({ dealId: "D-1", updatedAt: "2026-09-01T00:00:00Z" }),
        deal({ dealId: "D-2", addressConfirmed: false }),
        deal({ dealId: "D-3", addressConfirmed: undefined }),
        deal({ dealId: 4, name: undefined, updatedAt: "2026-10-01T00:00:00Z" }),
        "not an object",
      ]),
    );
    const hub = new LiveHubClient({
      baseUrl: BASE_URL,
      credential: CREDENTIAL,
      fetch: stub.fetch,
      logger: { warn: (details, message) => warnings.push({ details, message }) },
    });
    assert.deepEqual(await hub.listProjects(), [
      {
        dealId: "4",
        address: { formatted: "12 Example Lane, Brooklyn, NY 11201" },
        updatedAtMs: Date.UTC(2026, 9, 1),
      },
      {
        dealId: "D-1",
        projectName: "Smith kitchen",
        address: { formatted: "12 Example Lane, Brooklyn, NY 11201" },
        updatedAtMs: Date.UTC(2026, 8, 1),
      },
    ]);
    assert.equal(warnings.length, 1);
    assert.deepEqual(warnings[0]?.details, {
      hub: {
        deals: 5,
        projects: 2,
        skipped: { address_not_confirmed: 1, confirmation_missing: 1, invalid_deal_id: 1 },
        duplicates: 0,
      },
    });
    assert.ok(!JSON.stringify(warnings).includes("Example Lane"), "no addresses in logs");
  });

  it("reads nested fields and an enveloped list through the mapping", async () => {
    const stub = stubFetch(() =>
      Response.json({
        data: {
          items: [
            {
              sales: { dealId: "S-9" },
              title: "Loft",
              property: { formatted: "9 Loft Street", confirmed: true },
            },
          ],
        },
      }),
    );
    const hub = client(stub.fetch, {
      listDeals: { path: "/v2/deals", itemsPath: "data.items" },
      fields: {
        dealId: "sales.dealId",
        projectName: "title",
        address: "property.formatted",
        addressConfirmed: "property.confirmed",
        updatedAt: "modified",
      },
    });
    assert.deepEqual(await hub.listProjects(), [
      { dealId: "S-9", projectName: "Loft", address: { formatted: "9 Loft Street" } },
    ]);
    assert.equal(stub.calls[0]?.url, "https://hub.example.test/base/v2/deals");
  });

  it("never uses the all-projects record id as the dealId", async () => {
    const stub = stubFetch(() => Response.json([deal({ dealId: undefined })]));
    assert.deepEqual(await client(stub.fetch).listProjects(), []);
  });

  it("finds one project by dealId in the deals list", async () => {
    const stub = stubFetch(() => Response.json([deal({ dealId: "D-1" }), deal({ dealId: "D-2" })]));
    const hub = client(stub.fetch);
    assert.equal((await hub.getProject("D-2"))?.dealId, "D-2");
    assert.equal(await hub.getProject("project-record-7"), null);
  });
});

describe("LiveHubClient failures", () => {
  it("maps a non-2xx answer to http_status without reading the body into the error", async () => {
    for (const status of [401, 403, 404, 500, 503]) {
      const stub = stubFetch(
        () => new Response(`secret body ${CREDENTIAL}`, { status, headers: { "x-a": "b" } }),
      );
      const error = await hubFailure(client(stub.fetch).listProjects());
      assert.equal(error.failure, "http_status");
      assert.equal(error.status, status);
      assert.ok(!error.reason.includes("secret body"));
    }
  });

  it("maps a redirect to a redirect failure", async () => {
    const stub = stubFetch(
      () =>
        new Response(null, { status: 302, headers: { location: "https://elsewhere.example/" } }),
    );
    const error = await hubFailure(client(stub.fetch).listProjects());
    assert.equal(error.failure, "redirect");
  });

  it("maps a network error without chaining its message", async () => {
    const stub = stubFetch(() => {
      throw new TypeError(`fetch failed: header value ${CREDENTIAL} is invalid`);
    });
    const error = await hubFailure(client(stub.fetch).listProjects());
    assert.equal(error.failure, "network");
    assert.equal(error.cause, undefined);
  });

  it("maps a timeout to a timeout failure", async () => {
    const hub = new LiveHubClient({
      baseUrl: BASE_URL,
      credential: CREDENTIAL,
      timeoutMs: 20,
      fetch: (_input, init) =>
        new Promise<Response>((_resolve, reject) => {
          // AbortSignal.timeout's timer does not keep the process alive (a real socket does).
          const keepAlive = setTimeout(() => reject(new Error("timeout never fired")), 5000);
          init?.signal?.addEventListener("abort", () => {
            clearTimeout(keepAlive);
            reject(init.signal?.reason);
          });
        }),
    });
    const error = await hubFailure(hub.listProjects());
    assert.equal(error.failure, "timeout");
  });

  it("maps a body that is not JSON to invalid_json", async () => {
    const stub = stubFetch(() => new Response("<html>login</html>", { status: 200 }));
    assert.equal((await hubFailure(client(stub.fetch).listProjects())).failure, "invalid_json");
  });

  it("maps a response without a deals array to unexpected_shape", async () => {
    for (const body of [{ deals: [] }, null, "x", 42]) {
      const stub = stubFetch(() => Response.json(body));
      const error = await hubFailure(client(stub.fetch).listProjects());
      assert.equal(error.failure, "unexpected_shape", JSON.stringify(body));
    }
    const enveloped = stubFetch(() => Response.json({ data: {} }));
    const error = await hubFailure(
      client(enveloped.fetch, {
        listDeals: { path: "/d", itemsPath: "data.items" },
      }).listProjects(),
    );
    assert.equal(error.failure, "unexpected_shape");
  });

  it("refuses an oversized response by declared length and by streamed length", async () => {
    const declared = new LiveHubClient({
      baseUrl: BASE_URL,
      credential: CREDENTIAL,
      maxResponseBytes: 10,
      fetch: async () =>
        new Response("[]", { status: 200, headers: { "content-length": "1000000" } }),
    });
    assert.equal((await hubFailure(declared.listProjects())).failure, "too_large");

    const streamed = new LiveHubClient({
      baseUrl: BASE_URL,
      credential: CREDENTIAL,
      maxResponseBytes: 10,
      fetch: async () => new Response(JSON.stringify([deal()]), { status: 200 }),
    });
    assert.equal((await hubFailure(streamed.listProjects())).failure, "too_large");
  });
});

describe("LiveHubClient over real HTTP (loopback)", () => {
  let server: Server;
  let baseUrl: string;
  const seen: { url: string; headers: IncomingHttpHeaders }[] = [];

  before(async () => {
    server = createServer((request, response) => {
      seen.push({ url: request.url ?? "", headers: request.headers });
      if (request.url === "/hub/api/sales/deals") {
        response.writeHead(200, { "content-type": "application/json" });
        response.end(JSON.stringify([deal({ dealId: "L-1" })]));
        return;
      }
      if (request.url === "/moved/api/sales/deals") {
        response.writeHead(307, { location: "/elsewhere" });
        response.end();
        return;
      }
      response.writeHead(404).end();
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    baseUrl = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
  });

  after(async () => {
    server.closeAllConnections();
    await new Promise<void>((resolve) => server.close(() => resolve()));
  });

  it("lists projects with the global fetch", async () => {
    const hub = new LiveHubClient({ baseUrl: `${baseUrl}/hub`, credential: CREDENTIAL });
    assert.deepEqual(
      (await hub.listProjects()).map((project) => project.dealId),
      ["L-1"],
    );
    assert.equal(seen.at(-1)?.headers.authorization, `Bearer ${CREDENTIAL}`);
  });

  it("does not follow a redirect (the credential is not sent again)", async () => {
    const before = seen.length;
    const hub = new LiveHubClient({ baseUrl: `${baseUrl}/moved`, credential: CREDENTIAL });
    const error = await hubFailure(hub.listProjects());
    assert.equal(error.failure, "redirect");
    assert.equal(seen.length, before + 1, "the redirect target must not be requested");
  });
});
