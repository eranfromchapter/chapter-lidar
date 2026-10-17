// Test helpers for the project routes: an app with the real src/routes areas, a test Entra
// issuer and an injected HubClient. No network beyond loopback, no Docker.

import type { FastifyInstance } from "fastify";
import { buildServer } from "../../src/core/app.js";
import { HubError, type HubClient, type HubProject } from "../../src/hub/types.js";
import {
  fakeDatabase,
  logCollector,
  startTestIssuer,
  testConfig,
  type TestIssuer,
} from "../core/helpers.js";

export interface ProjectsTestApp {
  readonly app: FastifyInstance;
  readonly issuer: TestIssuer;
  readonly logs: string[];
  token(roles: readonly string[] | null): Promise<string>;
  close(): Promise<void>;
}

/** Builds the real app (every route area) with the given HubClient injected. */
export async function projectsTestApp(
  hub: HubClient | undefined,
  env: Record<string, string | undefined> = {},
): Promise<ProjectsTestApp> {
  const issuer = await startTestIssuer();
  const logs = logCollector();
  const app = await buildServer({
    config: testConfig({ ENTRA_JWKS_URL: issuer.jwksUrl, ...env }),
    db: fakeDatabase(),
    ...(hub === undefined ? {} : { services: { hub } }),
    logStream: logs.stream,
  });
  await app.ready();
  return {
    app,
    issuer,
    logs: logs.lines,
    token: (roles) => issuer.mint({ roles: roles === null ? null : [...roles] }),
    async close() {
      await app.close();
      await issuer.close();
    },
  };
}

export function bearer(token: string): Record<string, string> {
  return { authorization: `Bearer ${token}` };
}

/** A HubClient whose every call fails like an unreachable HUB, counting calls. */
export class FailingHubClient implements HubClient {
  calls = 0;

  constructor(
    private readonly error: Error = new HubError("http_status", "HUB answered 503", 503),
  ) {}

  async listProjects(): Promise<readonly HubProject[]> {
    this.calls += 1;
    throw this.error;
  }

  async getProject(): Promise<HubProject | null> {
    this.calls += 1;
    throw this.error;
  }
}

/** A HubClient over fixed projects that counts calls (for cache tests). */
export class CountingHubClient implements HubClient {
  listCalls = 0;
  getCalls = 0;
  fail = false;

  constructor(public projects: readonly HubProject[]) {}

  async listProjects(): Promise<readonly HubProject[]> {
    this.listCalls += 1;
    if (this.fail) {
      throw new HubError("timeout", "HUB did not answer within 10000 ms");
    }
    return this.projects;
  }

  async getProject(dealId: string): Promise<HubProject | null> {
    this.getCalls += 1;
    if (this.fail) {
      throw new HubError("timeout", "HUB did not answer within 10000 ms");
    }
    return this.projects.find((project) => project.dealId === dealId) ?? null;
  }
}

/** A clock for cache tests. */
export class TestClock {
  constructor(public nowMs = Date.UTC(2026, 9, 17, 12, 0, 0)) {}

  readonly now = (): number => this.nowMs;

  advance(ms: number): void {
    this.nowMs += ms;
  }
}
