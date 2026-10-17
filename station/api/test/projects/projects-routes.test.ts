// Project routes: search, limit and order, the 502 mapping of HUB failures, the service wiring
// and that no HUB credential or address reaches the log.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { CachedHubClient } from "../../src/hub/cache.js";
import { FakeHubClient } from "../../src/hub/fake.js";
import { HubError, type HubProject } from "../../src/hub/types.js";
import { searchProjects } from "../../src/routes/projects/schemas.js";
import {
  CountingHubClient,
  FailingHubClient,
  bearer,
  projectsTestApp,
  type ProjectsTestApp,
} from "./helpers.js";

const PROJECTS: readonly HubProject[] = [
  {
    dealId: "D-3",
    projectName: "Maverick penthouse",
    address: { formatted: "500 West 22nd Street, New York, NY" },
  },
  { dealId: "D-2", projectName: "Tribeca loft", address: { formatted: "65 Franklin Street" } },
  { dealId: "D-1", address: { formatted: "2211 Third Avenue, New York, NY" } },
];

describe("GET /v1/projects", () => {
  let t: ProjectsTestApp;
  const hub = new CountingHubClient(PROJECTS);

  before(async () => {
    t = await projectsTestApp(hub);
  });
  after(async () => {
    await t.close();
  });

  async function list(query = ""): Promise<string[]> {
    const response = await t.app.inject({
      method: "GET",
      url: `/v1/projects${query}`,
      headers: bearer(await t.token(["capture"])),
    });
    assert.equal(response.statusCode, 200, response.body);
    return (response.json() as { projects: { dealId: string }[] }).projects.map((p) => p.dealId);
  }

  it("keeps the HUB order (most recently updated first)", async () => {
    assert.deepEqual(await list(), ["D-3", "D-2", "D-1"]);
  });

  it("matches q against name and address, case-insensitively", async () => {
    assert.deepEqual(await list("?q=new%20york"), ["D-3", "D-1"]);
    assert.deepEqual(await list("?q=TRIBECA"), ["D-2"]);
    assert.deepEqual(await list("?q=franklin"), ["D-2"]);
    assert.deepEqual(await list("?q=nowhere"), []);
  });

  it("does not match q against the dealId", async () => {
    assert.deepEqual(await list("?q=D-1"), []);
  });

  it("applies limit, 25 by default", async () => {
    assert.deepEqual(await list("?limit=2"), ["D-3", "D-2"]);
    const many: HubProject[] = Array.from({ length: 30 }, (_, i) => ({
      dealId: `M-${i}`,
      address: { formatted: `${i} Main Street` },
    }));
    assert.equal(searchProjects(many, undefined, 25).length, 25);
    hub.projects = many;
    try {
      assert.equal((await list()).length, 25);
    } finally {
      hub.projects = PROJECTS;
    }
  });

  it("returns only contract fields", async () => {
    const response = await t.app.inject({
      method: "GET",
      url: "/v1/projects?q=tribeca",
      headers: bearer(await t.token(["bim"])),
    });
    assert.deepEqual(response.json(), {
      projects: [
        {
          dealId: "D-2",
          projectName: "Tribeca loft",
          address: { formatted: "65 Franklin Street" },
        },
      ],
    });
  });
});

describe("GET /v1/projects/:dealId", () => {
  let t: ProjectsTestApp;

  before(async () => {
    t = await projectsTestApp(new FakeHubClient());
  });
  after(async () => {
    await t.close();
  });

  it("returns the fixture deal for every station role", async () => {
    for (const role of ["capture", "bim", "admin"]) {
      const response = await t.app.inject({
        method: "GET",
        url: "/v1/projects/fixture-deal-0001",
        headers: bearer(await t.token([role])),
      });
      assert.equal(response.statusCode, 200, response.body);
      assert.equal(
        (response.json() as { address: { formatted: string } }).address.formatted,
        "100 Example Street, Testville, NY 00000",
      );
    }
  });

  it("answers 404 project_not_found for a deal without a confirmed address", async () => {
    const response = await t.app.inject({
      method: "GET",
      url: "/v1/projects/fixture-deal-0003",
      headers: bearer(await t.token(["capture"])),
    });
    assert.equal(response.statusCode, 404);
    assert.equal((response.json() as { code: string }).code, "project_not_found");
  });

  it("decodes an encoded dealId", async () => {
    const response = await t.app.inject({
      method: "GET",
      url: "/v1/projects/fixture%2Ddeal%2D0001",
      headers: bearer(await t.token(["capture"])),
    });
    assert.equal(response.statusCode, 200, response.body);
  });
});

describe("HUB failures", () => {
  it("answer 502 hub_unavailable and log only the safe reason", async () => {
    const failing = new FailingHubClient(new HubError("http_status", "HUB answered 401", 401));
    const t = await projectsTestApp(failing);
    try {
      for (const url of ["/v1/projects", "/v1/projects/fixture-deal-0001"]) {
        const response = await t.app.inject({
          method: "GET",
          url,
          headers: bearer(await t.token(["capture"])),
        });
        assert.equal(response.statusCode, 502, response.body);
        assert.match(String(response.headers["content-type"]), /^application\/problem\+json/);
        const body = response.json() as { code: string; detail: string };
        assert.equal(body.code, "hub_unavailable");
        assert.ok(!body.detail.includes("401"), "HUB details stay in the log");
      }
      assert.equal(failing.calls, 2);
      assert.ok(t.logs.some((line) => line.includes("HUB answered 401")));
    } finally {
      await t.close();
    }
  });

  it("are not cached: the next request asks the HUB again", async () => {
    const inner = new CountingHubClient(PROJECTS);
    inner.fail = true;
    const t = await projectsTestApp(new CachedHubClient(inner));
    try {
      const headers = bearer(await t.token(["capture"]));
      const first = await t.app.inject({ method: "GET", url: "/v1/projects", headers });
      assert.equal(first.statusCode, 502);
      inner.fail = false;
      const second = await t.app.inject({ method: "GET", url: "/v1/projects", headers });
      assert.equal(second.statusCode, 200);
      assert.equal(inner.listCalls, 2);
    } finally {
      await t.close();
    }
  });

  it("answer 500 for an unexpected error that is not a HubError", async () => {
    const t = await projectsTestApp(new FailingHubClient(new Error("bug in the client")));
    try {
      const response = await t.app.inject({
        method: "GET",
        url: "/v1/projects",
        headers: bearer(await t.token(["capture"])),
      });
      assert.equal(response.statusCode, 500);
      assert.equal((response.json() as { code: string }).code, "internal_error");
    } finally {
      await t.close();
    }
  });
});

describe("service wiring", () => {
  it("uses the cached fake HUB from config when none is injected (HUB_MODE=fake)", async () => {
    const t = await projectsTestApp(undefined, { HUB_MODE: "fake" });
    try {
      assert.ok(t.app.services.hub instanceof CachedHubClient);
      const response = await t.app.inject({
        method: "GET",
        url: "/v1/projects/fixture-deal-0001",
        headers: bearer(await t.token(["capture"])),
      });
      assert.equal(response.statusCode, 200, response.body);
    } finally {
      await t.close();
    }
  });

  it("uses the injected HubClient as is", async () => {
    const hub = new FakeHubClient();
    const t = await projectsTestApp(hub);
    try {
      assert.equal(t.app.services.hub, hub);
    } finally {
      await t.close();
    }
  });

  it("never logs the HUB credential (live mode)", async () => {
    const credential = "route-test-credential-abcdef0123";
    const t = await projectsTestApp(undefined, {
      HUB_MODE: "live",
      // Nothing listens on port 9: every HUB call fails fast with a network error.
      HUB_BASE_URL: "http://127.0.0.1:9",
      HUB_SERVICE_CREDENTIAL: credential,
    });
    try {
      const response = await t.app.inject({
        method: "GET",
        url: "/v1/projects",
        headers: bearer(await t.token(["capture"])),
      });
      assert.equal(response.statusCode, 502, response.body);
      assert.ok(t.logs.length > 0);
      assert.ok(!t.logs.some((line) => line.includes(credential)), "credential found in logs");
      assert.ok(!response.body.includes(credential));
    } finally {
      await t.close();
    }
  });
});
