// F16 AC4: POST /v1/sketch-interpretations calls Claude with the image and the reading schema,
// answers 200 with a contract-valid interpretation, 422 for a non-plan, 503 without a key.
// Claude is a fake injected as app.services.sketchClaude: no test reaches the network, and no
// test needs Postgres (the audit rows go to the fake database).

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { after, before, describe, it } from "node:test";
import Anthropic from "@anthropic-ai/sdk";
import { validateSketchInterpretation } from "@chapter/capture-contract";
import { loadConfig } from "../../src/core/config.js";
import {
  SKETCH_FALLBACK_BETA,
  SKETCH_PROMPT_PATH,
  createSketchClaudeClient,
  readingOutputSchema,
} from "../../src/routes/sketch/claude.js";
import {
  MAX_IMAGE_BASE64_LENGTH,
  MAX_IMAGE_BYTES,
  base64DecodedLength,
  imageSize,
} from "../../src/routes/sketch/image.js";
import { testEnv } from "../core/helpers.js";
import {
  BEDROOM_READING,
  FakeSketchClaude,
  NOT_A_PLAN_READING,
  SKETCH_URL,
  type SketchTestApp,
  TEST_API_KEY,
  auditRows,
  bearer,
  claudeMessage,
  example,
  gifHeader,
  jpegHeader,
  pngImage,
  refusalMessage,
  sdkErrors,
  sketchBody,
  sketchTestApp,
  webpHeader,
} from "./support.js";

const PHOTO = pngImage(3024 / 8, 4032 / 8); // 378 x 504, portrait like a phone photo

interface Answer {
  status: number;
  body: Record<string, unknown>;
  headers: Record<string, unknown>;
}

async function post(t: SketchTestApp, payload: unknown, roles?: readonly string[] | null) {
  const token = await t.token(roles);
  const response = await t.app.inject({
    method: "POST",
    url: SKETCH_URL,
    headers: { ...bearer(token), "content-type": "application/json" },
    payload: JSON.stringify(payload),
  });
  return {
    status: response.statusCode,
    body: response.json() as Record<string, unknown>,
    headers: response.headers,
  } satisfies Answer;
}

describe("a sketch photo read by Claude", () => {
  let t: SketchTestApp;
  const claude = new FakeSketchClaude();

  before(async () => {
    t = await sketchTestApp(claude);
  });
  after(async () => t.close());

  it("answers 200 with the bedroom reading as a contract-valid interpretation", async () => {
    const answer = await post(t, sketchBody(PHOTO));
    assert.equal(answer.status, 200, JSON.stringify(answer.body));
    const result = validateSketchInterpretation(answer.body);
    assert.deepEqual(result.errors, []);
    assert.equal(answer.body.schemaVersion, "1.0.0");
    assert.equal(answer.body.model, "claude-opus-5-5");
    assert.deepEqual(answer.body.image, { width: 378, height: 504 });
    assert.deepEqual(answer.body.reading, BEDROOM_READING);
    assert.match(String(answer.body.interpretedAt), /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
  });

  it("sends the image, the contract prompt and the reading schema to Claude", async () => {
    claude.calls.length = 0;
    const body = sketchBody(PHOTO, "image/png", "existing printed plan");
    const answer = await post(t, body);
    assert.equal(answer.status, 200);
    assert.equal(claude.calls.length, 1);
    const { body: sent, options } = claude.calls[0]!;

    assert.equal(sent.model, "claude-opus-5-5");
    assert.equal(sent.max_tokens, 16000);
    assert.equal(sent.system, readFileSync(SKETCH_PROMPT_PATH, "utf8"));
    assert.deepEqual(sent.thinking, { type: "adaptive" });
    assert.equal(sent.output_config?.effort, "high");
    assert.equal(sent.output_config?.format?.type, "json_schema");
    assert.deepEqual(sent.output_config?.format?.schema, readingOutputSchema());
    assert.equal(sent.fallbacks, "default");
    assert.deepEqual(sent.betas, [SKETCH_FALLBACK_BETA]);
    assert.equal(SKETCH_FALLBACK_BETA, "server-side-fallback-2026-07-01");
    assert.equal(sent.stream, undefined);
    assert.equal(options?.timeout, 120_000);

    assert.equal(sent.messages.length, 1);
    const [message] = sent.messages;
    assert.equal(message?.role, "user");
    const content = message?.content as { type: string; [key: string]: unknown }[];
    assert.deepEqual(content[0], {
      type: "image",
      source: { type: "base64", media_type: "image/png", data: body.data },
    });
    assert.equal(content[1]?.type, "text");
    assert.match(String(content[1]?.text), /floor-plan sketch/);
    assert.match(String(content[1]?.text), /existing printed plan$/);
  });

  it("sends a self-contained reading schema that structured outputs accept", () => {
    const schema = readingOutputSchema();
    const text = JSON.stringify(schema);
    assert.doesNotMatch(text, /"\$ref"|"\$defs"/);
    for (const keyword of ["minimum", "maximum", "minLength", "maxLength", "minItems"]) {
      assert.doesNotMatch(text, new RegExp(`"${keyword}"`), keyword);
    }
    assert.deepEqual(schema.required, [
      "isFloorPlan",
      "problem",
      "dimensionUnits",
      "ceilingHeightMm",
      "rooms",
      "dimensions",
    ]);
    // Every object forbids additional properties, as structured outputs require.
    const objects: Record<string, unknown>[] = [];
    const walk = (node: unknown): void => {
      if (Array.isArray(node)) {
        node.forEach(walk);
      } else if (node !== null && typeof node === "object") {
        const record = node as Record<string, unknown>;
        if (record.type === "object") {
          objects.push(record);
        }
        Object.values(record).forEach(walk);
      }
    };
    walk(schema);
    assert.ok(objects.length >= 6);
    for (const object of objects) {
      assert.equal(object.additionalProperties, false);
    }
  });

  it("sends no hint text when there is no hint", async () => {
    claude.calls.length = 0;
    await post(t, sketchBody(PHOTO));
    const content = claude.calls[0]?.body.messages[0]?.content as { text?: string }[];
    assert.equal(content[1]?.text, "Read this floor-plan sketch.");
  });

  it("reads the size of JPEG, WebP and GIF images from their headers", async () => {
    for (const [image, mediaType] of [
      [jpegHeader(4032, 3024), "image/jpeg"],
      [webpHeader(1600, 1200), "image/webp"],
      [gifHeader(640, 480), "image/gif"],
    ] as const) {
      const answer = await post(t, sketchBody(image, mediaType));
      assert.equal(answer.status, 200, `${mediaType}: ${JSON.stringify(answer.body)}`);
      const size = imageSize(image, mediaType);
      assert.deepEqual(answer.body.image, size);
    }
    assert.deepEqual(imageSize(jpegHeader(4032, 3024), "image/jpeg"), {
      width: 4032,
      height: 3024,
    });
  });

  it("keeps the model that served the answer after a server-side fallback", async () => {
    claude.responder = () =>
      claudeMessage(BEDROOM_READING, {
        model: "claude-opus-5",
        before: [
          {
            type: "fallback",
            from: { model: "claude-opus-5-5" },
            to: { model: "claude-opus-5" },
          },
        ],
        iterations: [
          { type: "message", input_tokens: 2000, output_tokens: 0 },
          {
            type: "fallback_message",
            model: "claude-opus-5",
            input_tokens: 2100,
            output_tokens: 3000,
          },
        ],
      });
    const before = auditRows(t.db).length;
    const answer = await post(t, sketchBody(PHOTO));
    claude.responder = () => claudeMessage(BEDROOM_READING);
    assert.equal(answer.status, 200);
    assert.equal(answer.body.model, "claude-opus-5");
    const row = auditRows(t.db)[before];
    assert.equal(row?.details.fallback, true);
    assert.equal(row?.details.servedBy, "claude-opus-5");
    assert.equal(row?.details.inputTokens, 4100);
    assert.equal(row?.details.outputTokens, 3000);
  });

  it("audits each call without the image, and never logs the image", async () => {
    const before = auditRows(t.db).length;
    const body = sketchBody(PHOTO);
    await post(t, body);
    const rows = auditRows(t.db).slice(before);
    assert.equal(rows.length, 1);
    const [row] = rows;
    assert.equal(row?.action, "sketch.interpret");
    assert.deepEqual(row?.details, {
      bytes: PHOTO.length,
      mediaType: "image/png",
      model: "claude-opus-5-5",
      outcome: "ok",
      servedBy: "claude-opus-5-5",
      fallback: false,
      inputTokens: 2100,
      outputTokens: 3400,
    });
    const audited = t.db.queries.map((query) => JSON.stringify(query.values)).join("\n");
    assert.ok(!audited.includes(body.data!.slice(0, 64)), "image data in an audit row");
    assert.ok(!t.logs.join("\n").includes(body.data!.slice(0, 64)), "image data in the log");
  });
});

describe("answers that are not a reading", () => {
  let t: SketchTestApp;
  const claude = new FakeSketchClaude();

  before(async () => {
    t = await sketchTestApp(claude);
  });
  after(async () => t.close());

  it("422 sketch_not_a_plan with the interpretation in the problem", async () => {
    claude.responder = () => claudeMessage(NOT_A_PLAN_READING);
    const answer = await post(t, sketchBody(PHOTO));
    assert.equal(answer.status, 422);
    assert.match(String(answer.headers["content-type"]), /^application\/problem\+json/);
    assert.equal(answer.body.code, "sketch_not_a_plan");
    const reading = NOT_A_PLAN_READING as { problem: string };
    assert.equal(answer.body.detail, reading.problem);
    const interpretation = answer.body.interpretation as Record<string, unknown>;
    assert.deepEqual(validateSketchInterpretation(interpretation).errors, []);
    assert.deepEqual(interpretation.reading, NOT_A_PLAN_READING);
    assert.equal(auditRows(t.db).at(-1)?.details.outcome, "not_a_plan");
  });

  it("422 sketch_refused when Claude and the fallback decline", async () => {
    claude.responder = () => refusalMessage();
    const answer = await post(t, sketchBody(PHOTO));
    assert.equal(answer.status, 422);
    assert.equal(answer.body.code, "sketch_refused");
    assert.equal(answer.body.interpretation, undefined);
    assert.equal(auditRows(t.db).at(-1)?.details.outcome, "refused");
  });

  it("502 sketch_truncated at the output limit", async () => {
    claude.responder = () =>
      claudeMessage(null, { stopReason: "max_tokens", text: '{"isFloorPlan": true, "rooms": [' });
    const answer = await post(t, sketchBody(PHOTO));
    assert.equal(answer.status, 502);
    assert.equal(answer.body.code, "sketch_truncated");
  });

  it("502 sketch_unreadable_response for text that is not JSON", async () => {
    claude.responder = () => claudeMessage(null, { text: "I see a bedroom and a closet." });
    const answer = await post(t, sketchBody(PHOTO));
    assert.equal(answer.status, 502);
    assert.equal(answer.body.code, "sketch_unreadable_response");
    assert.equal(auditRows(t.db).at(-1)?.details.outcome, "unreadable_response");
  });

  it("502 sketch_unreadable_response for a reading the contract rejects", async () => {
    for (const name of ["invalid/unknown-furniture.json", "invalid/reading-without-problem.json"]) {
      claude.responder = () => claudeMessage(example(name).reading);
      const answer = await post(t, sketchBody(PHOTO));
      assert.equal(answer.status, 502, name);
      assert.equal(answer.body.code, "sketch_unreadable_response", name);
    }
    const missingRooms = { ...(BEDROOM_READING as Record<string, unknown>) };
    delete missingRooms.rooms;
    claude.responder = () => claudeMessage(missingRooms);
    assert.equal((await post(t, sketchBody(PHOTO))).status, 502);
  });
});

describe("Claude unavailable", () => {
  it("503 sketch_unavailable when no API key is configured (the station still starts)", async () => {
    const t = await sketchTestApp(undefined);
    try {
      assert.equal(t.app.config.sketch.anthropicApiKey, undefined);
      const answer = await post(t, sketchBody(PHOTO));
      assert.equal(answer.status, 503);
      assert.equal(answer.body.code, "sketch_unavailable");
      assert.deepEqual(auditRows(t.db), [], "nothing was sent, so nothing is audited");
      const health = await t.app.inject({ method: "GET", url: "/health" });
      assert.equal(health.statusCode, 200);
    } finally {
      await t.close();
    }
  });

  const cases: [string, () => Error, string][] = [
    ["rate limited", () => sdkErrors.rateLimit("30"), "rate_limited"],
    ["overloaded", sdkErrors.overloaded, "server_error"],
    ["unreachable", sdkErrors.connection, "unreachable"],
    ["timed out", sdkErrors.timeout, "unreachable"],
    ["rejecting the API key", sdkErrors.authentication, "auth_failed"],
  ];
  for (const [label, error, outcome] of cases) {
    it(`503 sketch_unavailable when Claude is ${label}`, async () => {
      const claude = new FakeSketchClaude(() => {
        throw error();
      });
      const t = await sketchTestApp(claude);
      try {
        const answer = await post(t, sketchBody(PHOTO));
        assert.equal(answer.status, 503);
        assert.equal(answer.body.code, "sketch_unavailable");
        assert.equal(auditRows(t.db).at(-1)?.details.outcome, outcome);
        if (outcome === "rate_limited") {
          assert.equal(answer.headers["retry-after"], "30");
        } else {
          assert.equal(answer.headers["retry-after"], undefined);
        }
        if (outcome === "auth_failed") {
          assert.ok(
            t.logs.some(
              (line) => line.includes('"level":50') && line.includes("ANTHROPIC_API_KEY"),
            ),
          );
        }
      } finally {
        await t.close();
      }
    });
  }

  it("503 without Retry-After when the rate limit gives none", async () => {
    const t = await sketchTestApp(
      new FakeSketchClaude(() => {
        throw sdkErrors.rateLimit();
      }),
    );
    try {
      const answer = await post(t, sketchBody(PHOTO));
      assert.equal(answer.status, 503);
      assert.equal(answer.headers["retry-after"], undefined);
    } finally {
      await t.close();
    }
  });

  it("502 sketch_request_rejected (logged) when the API answers 400", async () => {
    const t = await sketchTestApp(
      new FakeSketchClaude(() => {
        throw sdkErrors.badRequest();
      }),
    );
    try {
      const answer = await post(t, sketchBody(PHOTO));
      assert.equal(answer.status, 502);
      assert.equal(answer.body.code, "sketch_request_rejected");
      assert.ok(t.logs.some((line) => line.includes("Claude API refused the sketch request")));
      assert.equal(auditRows(t.db).at(-1)?.details.outcome, "rejected");
    } finally {
      await t.close();
    }
  });
});

describe("request checks", () => {
  let t: SketchTestApp;
  const claude = new FakeSketchClaude();

  before(async () => {
    t = await sketchTestApp(claude);
  });
  after(async () => t.close());

  it("415 for a media type the Claude API does not read (HEIC)", async () => {
    const answer = await post(t, sketchBody(PHOTO, "image/heic"));
    assert.equal(answer.status, 415);
    assert.equal(answer.body.code, "sketch_unsupported_media_type");
  });

  it("400 for data that is not base64", async () => {
    for (const data of ["not base64!", "abc", "QUJD\nREVG", "data:image/png;base64,QUJD"]) {
      const answer = await post(t, { mediaType: "image/png", data });
      assert.equal(answer.status, 400, data);
      assert.equal(answer.body.code, "sketch_image_invalid", data);
    }
  });

  it("400 for bytes that are not an image of the declared type", async () => {
    const answer = await post(t, sketchBody(PHOTO, "image/jpeg"));
    assert.equal(answer.status, 400);
    assert.equal(answer.body.code, "sketch_image_invalid");
    const text = await post(t, sketchBody(Buffer.from("just some text, not an image")));
    assert.equal(text.status, 400);
  });

  it("400 invalid_request for a body outside the schema", async () => {
    const data = PHOTO.toString("base64");
    for (const body of [
      { data },
      { mediaType: "image/png" },
      { mediaType: "image/png", data, hint: "x".repeat(501) },
      { mediaType: "image/png", data, extra: true },
      { mediaType: 1, data },
    ]) {
      const answer = await post(t, body);
      assert.equal(answer.status, 400, JSON.stringify(Object.keys(body)));
      assert.equal(answer.body.code, "invalid_request");
    }
  });

  it("413 sketch_image_too_large above 10 MB decoded", async () => {
    const length = MAX_IMAGE_BASE64_LENGTH + 4;
    const data = "A".repeat(length);
    assert.ok((base64DecodedLength(data) ?? 0) > MAX_IMAGE_BYTES);
    const answer = await post(t, { mediaType: "image/png", data });
    assert.equal(answer.status, 413);
    assert.equal(answer.body.code, "sketch_image_too_large");
  });

  it("413 payload_too_large for a body above the route limit", async () => {
    const data = "A".repeat(MAX_IMAGE_BASE64_LENGTH + 128 * 1024);
    const answer = await post(t, { mediaType: "image/png", data });
    assert.equal(answer.status, 413);
    assert.equal(answer.body.code, "payload_too_large");
  });

  it("accepts a 10 MB image (the route body limit is above the global one)", async () => {
    const data = "A".repeat(MAX_IMAGE_BASE64_LENGTH - 4);
    assert.ok(data.length > t.app.config.server.bodyLimitBytes);
    // Not an image, so 400, but it was read and checked, not refused as too large.
    const answer = await post(t, { mediaType: "image/png", data });
    assert.equal(answer.status, 400);
    assert.equal(answer.body.code, "sketch_image_invalid");
  });

  it("401 without a token and 403 without the capture role", async () => {
    const calls = claude.calls.length;
    const anonymous = await t.app.inject({
      method: "POST",
      url: SKETCH_URL,
      headers: { "content-type": "application/json" },
      payload: JSON.stringify(sketchBody(PHOTO)),
    });
    assert.equal(anonymous.statusCode, 401);
    for (const roles of [["bim"], ["admin"], null]) {
      const answer = await post(t, sketchBody(PHOTO), roles);
      assert.equal(answer.status, 403, JSON.stringify(roles));
    }
    assert.equal(claude.calls.length, calls, "Claude was called without the capture role");
  });

  it("never calls Claude for a request it refuses", () => {
    assert.equal(claude.calls.length, 0);
  });
});

describe("configuration", () => {
  it("defaults SKETCH_MODEL to claude-opus-5-5 and keeps the key out of JSON", () => {
    const config = loadConfig(testEnv({ ANTHROPIC_API_KEY: TEST_API_KEY }));
    assert.equal(config.sketch.model, "claude-opus-5-5");
    assert.equal(config.sketch.anthropicApiKey, TEST_API_KEY);
    assert.ok(!JSON.stringify(config).includes(TEST_API_KEY));
  });

  it("SKETCH_MODEL overrides the model sent to Claude", async () => {
    const claude = new FakeSketchClaude();
    const t = await sketchTestApp(claude, { SKETCH_MODEL: "claude-opus-5" });
    try {
      await post(t, sketchBody(PHOTO));
      assert.equal(claude.calls[0]?.body.model, "claude-opus-5");
    } finally {
      await t.close();
    }
  });

  it("refuses a SKETCH_MODEL that is not a model id", () => {
    assert.throws(() => loadConfig(testEnv({ SKETCH_MODEL: "claude opus" })), /SKETCH_MODEL/);
  });

  it("builds the SDK client with a 120 s timeout and 2 retries (no request is made)", () => {
    const client = createSketchClaudeClient(TEST_API_KEY) as Anthropic;
    assert.ok(client instanceof Anthropic);
    assert.equal(client.timeout, 120_000);
    assert.equal(client.maxRetries, 2);
  });

  it("with a key and nothing injected, the route builds the real client from config", async () => {
    const t = await sketchTestApp(undefined, { ANTHROPIC_API_KEY: TEST_API_KEY });
    try {
      const { resolveSketchClaude } = await import("../../src/routes/sketch/claude.js");
      const client = resolveSketchClaude(t.app);
      assert.ok(client instanceof Anthropic);
      assert.ok(!t.logs.join("\n").includes(TEST_API_KEY), "API key in the log");
    } finally {
      await t.close();
    }
  });
});
