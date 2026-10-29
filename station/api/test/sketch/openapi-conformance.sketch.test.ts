// F7 AC6 for the sketches area: createSketchInterpretation is implemented with the path,
// method, roles, request schema and response schemas of contract/openapi/station.yaml.
//
// Every documented response status is produced through the real app (every src/routes area,
// a test Entra issuer, a fake Claude client, the fake database) and checked against the
// document: status documented, media type documented, body valid against that status's schema
// (the 200 and the 422 interpretation against the contract sketch-interpretation schema).

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import type { FastifySchema } from "fastify";
import { SKETCH_INTERPRETATION_BODY_SCHEMA } from "../../src/routes/sketch/schemas.js";
import { MAX_IMAGE_BASE64_LENGTH } from "../../src/routes/sketch/image.js";
import { OpenApi } from "../packages/openapi.js";
import {
  BEDROOM_READING,
  FakeSketchClaude,
  NOT_A_PLAN_READING,
  SKETCH_URL,
  type SketchTestApp,
  bearer,
  claudeMessage,
  pngImage,
  refusalMessage,
  sdkErrors,
  sketchBody,
  sketchTestApp,
} from "./support.js";

const OPERATION = "createSketchInterpretation";
const openapi = new OpenApi();
const PHOTO = pngImage(64, 48);

let t: SketchTestApp;
let unconfigured: SketchTestApp;
const claude = new FakeSketchClaude();
const produced = new Set<string>();
let routeSchema: FastifySchema | undefined;

before(async () => {
  t = await sketchTestApp(claude, {}, (app) => {
    // Runs after the core auth hook, so only for requests that passed sign-in.
    app.addHook("onRequest", async (request) => {
      if (request.routeOptions.url === SKETCH_URL) {
        routeSchema = request.routeOptions.schema;
      }
    });
  });
  unconfigured = await sketchTestApp(undefined);
});

after(async () => {
  await t?.close();
  await unconfigured?.close();
});

async function conforms(
  app: SketchTestApp,
  payload: unknown,
  expected: number,
  options: { roles?: readonly string[] | null; token?: boolean } = {},
): Promise<Record<string, unknown>> {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (options.token !== false) {
    Object.assign(headers, bearer(await app.token(options.roles)));
  }
  const response = await app.app.inject({
    method: "POST",
    url: SKETCH_URL,
    headers,
    payload: JSON.stringify(payload),
  });
  assert.equal(response.statusCode, expected, response.body.slice(0, 500));
  assert.deepEqual(
    openapi.responseErrors(OPERATION, {
      statusCode: response.statusCode,
      headers: response.headers,
      body: response.body,
    }),
    [],
    `${OPERATION} ${response.statusCode} does not match the document`,
  );
  produced.add(String(response.statusCode));
  return response.json() as Record<string, unknown>;
}

function withoutAnnotations(value: unknown): unknown {
  if (Array.isArray(value)) {
    return value.map(withoutAnnotations);
  }
  if (value === null || typeof value !== "object") {
    return value;
  }
  return Object.fromEntries(
    Object.entries(value)
      .filter(([key]) => key !== "description" && key !== "examples")
      .map(([key, item]) => [key, withoutAnnotations(item)]),
  );
}

describe("createSketchInterpretation route", () => {
  it("is registered at its path with exactly its x-roles", () => {
    const op = openapi.operation(OPERATION);
    assert.equal(op.method, "POST");
    assert.equal(op.routeUrl, SKETCH_URL);
    const route = t.app.routeAccess.find(
      (access) => access.url === op.routeUrl && access.method.split(",").includes(op.method),
    );
    assert.ok(route, `${op.method} ${op.routeUrl} is not registered`);
    assert.equal(route.public, false);
    assert.deepEqual([...route.roles].sort(), [...op.roles].sort());
    assert.deepEqual(op.roles, ["capture"]);
  });

  it("has no other route under /v1/sketch-interpretations", () => {
    const extra = t.app.routeAccess
      .filter((route) => route.method !== "HEAD" && route.url.startsWith(SKETCH_URL))
      .map((route) => `${route.method} ${route.url}`);
    assert.deepEqual(extra, [`POST ${SKETCH_URL}`]);
  });

  it("validates the documented request body schema", async () => {
    await conforms(t, sketchBody(PHOTO), 200);
    assert.ok(routeSchema?.body, "the route must validate its body");
    const documented = (openapi.doc.components as Record<string, Record<string, unknown>>).schemas
      ?.SketchInterpretationRequest;
    assert.deepEqual(withoutAnnotations(routeSchema.body), withoutAnnotations(documented));
    assert.deepEqual(routeSchema.body, SKETCH_INTERPRETATION_BODY_SCHEMA);
  });

  it("accepts and rejects the same bodies as the document", () => {
    const data = PHOTO.toString("base64");
    const valid = [
      { mediaType: "image/png", data },
      { mediaType: "image/heic", data },
      { mediaType: "image/png", data, hint: "existing printed plan" },
    ];
    const invalid = [
      { data },
      { mediaType: "image/png" },
      { mediaType: "", data },
      { mediaType: "image/png", data: "" },
      { mediaType: "image/png", data, hint: "" },
      { mediaType: "image/png", data, hint: "h".repeat(501) },
      { mediaType: "image/png", data, other: 1 },
    ];
    for (const body of valid) {
      assert.deepEqual(openapi.requestBodyErrors(OPERATION, body), [], JSON.stringify(body));
    }
    for (const body of invalid) {
      assert.notDeepEqual(openapi.requestBodyErrors(OPERATION, body), [], JSON.stringify(body));
    }
  });
});

describe("createSketchInterpretation responses", () => {
  it("200 with a contract-valid interpretation", async () => {
    claude.responder = () => claudeMessage(BEDROOM_READING);
    const body = await conforms(t, sketchBody(PHOTO, "image/png", "hand sketch"), 200);
    assert.deepEqual(body.reading, BEDROOM_READING);
  });

  it("400 for a body outside the schema and for data that is not an image", async () => {
    await conforms(t, { mediaType: "image/png" }, 400);
    const body = await conforms(t, { mediaType: "image/png", data: "not base64" }, 400);
    assert.equal(body.code, "sketch_image_invalid");
  });

  it("401 without a token", async () => {
    await conforms(t, sketchBody(PHOTO), 401, { token: false });
  });

  it("403 without the capture role", async () => {
    await conforms(t, sketchBody(PHOTO), 403, { roles: ["bim"] });
  });

  it("413 above 10 MB", async () => {
    const body = await conforms(
      t,
      { mediaType: "image/png", data: "A".repeat(MAX_IMAGE_BASE64_LENGTH + 4) },
      413,
    );
    assert.equal(body.code, "sketch_image_too_large");
    await conforms(
      t,
      { mediaType: "image/png", data: "A".repeat(MAX_IMAGE_BASE64_LENGTH + 128 * 1024) },
      413,
    );
  });

  it("415 for HEIC", async () => {
    await conforms(t, sketchBody(PHOTO, "image/heic"), 415);
  });

  it("422 not a plan (with the interpretation) and refused", async () => {
    claude.responder = () => claudeMessage(NOT_A_PLAN_READING);
    const notAPlan = await conforms(t, sketchBody(PHOTO), 422);
    assert.equal(notAPlan.code, "sketch_not_a_plan");
    assert.ok(notAPlan.interpretation);
    claude.responder = () => refusalMessage();
    const refused = await conforms(t, sketchBody(PHOTO), 422);
    assert.equal(refused.code, "sketch_refused");
  });

  it("502 truncated, unreadable and rejected", async () => {
    claude.responder = () => claudeMessage(null, { stopReason: "max_tokens", text: "{" });
    await conforms(t, sketchBody(PHOTO), 502);
    claude.responder = () => claudeMessage(null, { text: "no JSON here" });
    await conforms(t, sketchBody(PHOTO), 502);
    claude.responder = () => {
      throw sdkErrors.badRequest();
    };
    await conforms(t, sketchBody(PHOTO), 502);
  });

  it("503 without an API key and when Claude is unavailable", async () => {
    await conforms(unconfigured, sketchBody(PHOTO), 503);
    claude.responder = () => {
      throw sdkErrors.rateLimit("12");
    };
    await conforms(t, sketchBody(PHOTO), 503);
    claude.responder = () => claudeMessage(BEDROOM_READING);
  });

  it("produced every documented status", () => {
    const responses = openapi.operation(OPERATION).node.responses as Record<string, unknown>;
    assert.deepEqual([...produced].sort(), Object.keys(responses).sort());
  });
});
