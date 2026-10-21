// The write-through of HUB projects to projects_cache (hub/persist.ts): every project the HUB
// returns is handed to the store, and a store failure (a database outage) is only logged,
// without project data, while the HUB answer is returned as usual: to the client and through
// GET /v1/projects of the app.

import assert from "node:assert/strict";
import { describe, it } from "node:test";
import type { QueryResult, QueryResultRow } from "pg";
import { FIXTURE_DEAL_ADDRESS } from "../../src/hub/fake.js";
import { PersistingHubClient } from "../../src/hub/persist.js";
import type { HubLogger, HubProject } from "../../src/hub/types.js";
import { fakeDatabase, type FakeDatabase } from "../core/helpers.js";
import { CountingHubClient, bearer, projectsTestApp } from "./helpers.js";

const PROJECTS: readonly HubProject[] = [
  {
    dealId: "deal-1",
    projectName: "Maverick penthouse",
    address: { formatted: "500 West 22nd Street, New York, NY" },
  },
  { dealId: "deal-2", address: { formatted: "65 Franklin Street" } },
];

class RecordingLogger implements HubLogger {
  readonly warnings: { details: Record<string, unknown>; message: string }[] = [];

  warn(details: Record<string, unknown>, message: string): void {
    this.warnings.push({ details, message });
  }
}

const unavailable = async (): Promise<void> => {
  throw new Error("connect ECONNREFUSED 127.0.0.1:5432");
};

describe("PersistingHubClient", () => {
  it("hands every project the HUB returns to the store", async () => {
    const stored: (readonly HubProject[])[] = [];
    const client = new PersistingHubClient(new CountingHubClient(PROJECTS), async (projects) => {
      stored.push(projects);
    });
    assert.deepEqual(await client.listProjects(), PROJECTS);
    assert.deepEqual(await client.getProject("deal-2"), PROJECTS[1]);
    assert.equal(await client.getProject("no-such-deal"), null);
    assert.deepEqual(stored, [PROJECTS, [PROJECTS[1]]]);
  });

  it("returns the HUB answer when the store fails and logs it without project data", async () => {
    const logger = new RecordingLogger();
    const client = new PersistingHubClient(new CountingHubClient(PROJECTS), unavailable, logger);
    assert.deepEqual(await client.listProjects(), PROJECTS);
    assert.deepEqual(await client.getProject("deal-1"), PROJECTS[0]);
    assert.deepEqual(logger.warnings, [
      {
        details: { hub: { projects: 2, reason: "Error" } },
        message: "could not store HUB projects in projects_cache",
      },
      {
        details: { hub: { projects: 1, reason: "Error" } },
        message: "could not store HUB projects in projects_cache",
      },
    ]);
  });

  it("returns the HUB answer when the store fails and there is no logger", async () => {
    const client = new PersistingHubClient(new CountingHubClient(PROJECTS), unavailable);
    assert.deepEqual(await client.listProjects(), PROJECTS);
  });
});

/** fakeDatabase() whose writes to projects_cache fail like an unreachable database. */
function cacheWritesFail(): FakeDatabase {
  const db = fakeDatabase();
  const query = db.query;
  db.query = <R extends QueryResultRow>(text: string, values: readonly unknown[] = []) => {
    if (text.includes("projects_cache")) {
      db.queries.push({ text, values });
      return Promise.reject<QueryResult<R>>(new Error("connect ECONNREFUSED 127.0.0.1:5432"));
    }
    return query<R>(text, values);
  };
  return db;
}

describe("GET /v1/projects while projects_cache cannot be written", () => {
  it("answers from the HUB (200) and logs the failure without project data", async () => {
    const db = cacheWritesFail();
    const t = await projectsTestApp(undefined, { HUB_MODE: "fake" }, db);
    try {
      const response = await t.app.inject({
        method: "GET",
        url: "/v1/projects",
        headers: bearer(await t.token(["capture"])),
      });
      assert.equal(response.statusCode, 200, response.body);
      const { projects } = response.json() as { projects: { dealId: string }[] };
      assert.deepEqual(projects.map((project) => project.dealId).sort(), [
        "fixture-deal-0001",
        "fixture-deal-0002",
      ]);
      assert.ok(
        db.queries.some((query) => query.text.includes("projects_cache")),
        "the app must try to store the projects",
      );
      const warning = t.logs.find((line) =>
        line.includes("could not store HUB projects in projects_cache"),
      );
      assert.ok(warning, t.logs.join("\n"));
      assert.ok(!warning.includes(FIXTURE_DEAL_ADDRESS), warning);
      assert.ok(!warning.includes("fixture-deal-0001"), warning);
    } finally {
      await t.close();
    }
  });
});
