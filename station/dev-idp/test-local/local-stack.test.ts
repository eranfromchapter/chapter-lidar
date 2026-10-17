// F13 AC2: on the running local stack (station/api/scripts/local-up.sh), a capture token from
// dev-idp lists projects (200), the same token is refused a download link (403), and no token
// gets 401.
//
//   npm run test:local --workspace station/dev-idp
//
// STATION_URL [http://localhost:8080] and STATION_DEV_IDP_URL [http://localhost:8090] point at
// the stack. Not part of `npm test`: it needs the stack running.

import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { before, describe, it } from "node:test";

const STATION_URL = (process.env.STATION_URL ?? "http://localhost:8080").replace(/\/+$/, "");
const DEV_IDP_URL = (process.env.STATION_DEV_IDP_URL ?? "http://localhost:8090").replace(
  /\/+$/,
  "",
);

async function captureToken(): Promise<string> {
  const response = await fetch(`${DEV_IDP_URL}/token`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ roles: ["capture"], sub: "e2e-capture-user", name: "E2E Capture" }),
  });
  assert.equal(response.status, 200, `dev-idp POST /token at ${DEV_IDP_URL}`);
  const body = (await response.json()) as { access_token?: unknown; token_type?: unknown };
  assert.equal(body.token_type, "Bearer");
  assert.equal(typeof body.access_token, "string");
  return body.access_token as string;
}

describe("local stack sign-in with dev-idp", () => {
  let token: string;

  before(async () => {
    const health = await fetch(`${STATION_URL}/health`);
    assert.equal(health.status, 200, `station GET /health at ${STATION_URL}`);
    token = await captureToken();
  });

  it("no token: GET /v1/projects is 401", async () => {
    const response = await fetch(`${STATION_URL}/v1/projects`);
    assert.equal(response.status, 401, await response.text());
  });

  it("capture token: GET /v1/projects is 200 with a project list", async () => {
    const response = await fetch(`${STATION_URL}/v1/projects`, {
      headers: { authorization: `Bearer ${token}` },
    });
    const text = await response.text();
    assert.equal(response.status, 200, text);
    const body = JSON.parse(text) as { projects?: unknown };
    assert.ok(Array.isArray(body.projects));
  });

  it("capture token: a download link is 403", async () => {
    const url = `${STATION_URL}/v1/packages/${randomUUID()}/files/download?path=x`;
    const response = await fetch(url, { headers: { authorization: `Bearer ${token}` } });
    assert.equal(response.status, 403, await response.text());
  });
});
