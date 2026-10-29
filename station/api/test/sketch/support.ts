// Test support for POST /v1/sketch-interpretations: a fake Claude client (no network), tiny
// images of each accepted type, Claude messages built from the contract examples and an app
// with every route area, a test Entra issuer and the fake database.

import { readFileSync } from "node:fs";
import { crc32, deflateSync } from "node:zlib";
import Anthropic from "@anthropic-ai/sdk";
import type { FastifyInstance } from "fastify";
import { buildServer } from "../../src/core/app.js";
import type { SketchClaudeClient } from "../../src/routes/sketch/claude.js";
import {
  type FakeDatabase,
  fakeDatabase,
  logCollector,
  startTestIssuer,
  testConfig,
  type TestIssuer,
} from "../core/helpers.js";

type BetaMessage = Anthropic.Beta.Messages.BetaMessage;
type CreateParams = Anthropic.Beta.Messages.MessageCreateParamsNonStreaming;

const EXAMPLES = new URL("../../../../contract/examples/sketch-interpretation/", import.meta.url);

/** A contract example (valid/ or invalid/). */
export function example(name: string): Record<string, unknown> & { reading: unknown } {
  return JSON.parse(readFileSync(new URL(name, EXAMPLES), "utf8")) as Record<string, unknown> & {
    reading: unknown;
  };
}

export const BEDROOM_READING = example("valid/bedroom-and-closet.json").reading;
export const NOT_A_PLAN_READING = example("valid/not-a-plan.json").reading;

export interface RecordedCall {
  readonly body: CreateParams;
  readonly options: Anthropic.RequestOptions | undefined;
}

type Responder = (body: CreateParams) => BetaMessage | Promise<BetaMessage>;

/** Records every request and answers with the responder (which may throw an SDK error). */
export class FakeSketchClaude implements SketchClaudeClient {
  readonly calls: RecordedCall[] = [];
  responder: Responder;

  constructor(responder: Responder = () => claudeMessage(BEDROOM_READING)) {
    this.responder = responder;
  }

  readonly beta = {
    messages: {
      create: async (body: CreateParams, options?: Anthropic.RequestOptions) => {
        this.calls.push({ body: structuredClone(body), options });
        return this.responder(body);
      },
    },
  };
}

export interface MessageOptions {
  readonly model?: string;
  readonly stopReason?: BetaMessage["stop_reason"];
  readonly stopDetails?: BetaMessage["stop_details"];
  /** Raw answer text instead of JSON.stringify(reading). */
  readonly text?: string;
  /** Content blocks before the answer (thinking, a fallback boundary). */
  readonly before?: unknown[];
  readonly iterations?: unknown[] | null;
}

/** A Messages API response carrying the reading as the structured-output text. */
export function claudeMessage(reading: unknown, options: MessageOptions = {}): BetaMessage {
  return {
    id: "msg_test_0001",
    type: "message",
    role: "assistant",
    model: options.model ?? "claude-opus-5-5",
    content: [
      { type: "thinking", thinking: "", signature: "sig-test" },
      ...(options.before ?? []),
      { type: "text", text: options.text ?? JSON.stringify(reading), citations: null },
    ],
    stop_reason: options.stopReason ?? "end_turn",
    stop_sequence: null,
    stop_details: options.stopDetails ?? null,
    container: null,
    context_management: null,
    usage: {
      input_tokens: 2100,
      output_tokens: 3400,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      iterations: options.iterations ?? null,
    },
  } as unknown as BetaMessage;
}

/** A refusal of the whole fallback chain (pre-output: no content). */
export function refusalMessage(): BetaMessage {
  return {
    ...claudeMessage(null),
    content: [],
    stop_reason: "refusal",
    stop_details: { type: "refusal", category: "cyber", explanation: null },
  } as unknown as BetaMessage;
}

const headers = (entries: Record<string, string> = {}) => new Headers(entries);
const errorBody = (type: string) => ({ type: "error", error: { type, message: `test ${type}` } });

/** SDK errors as the SDK raises them once its retries are spent. */
export const sdkErrors = {
  rateLimit: (retryAfter?: string) =>
    new Anthropic.RateLimitError(
      429,
      errorBody("rate_limit_error"),
      "429 rate limited",
      headers(retryAfter === undefined ? {} : { "retry-after": retryAfter }),
    ),
  overloaded: () =>
    new Anthropic.InternalServerError(
      529,
      errorBody("overloaded_error"),
      "529 overloaded",
      headers(),
    ),
  connection: () => new Anthropic.APIConnectionError({ message: "Connection error." }),
  timeout: () => new Anthropic.APIConnectionTimeoutError(),
  badRequest: () =>
    new Anthropic.BadRequestError(
      400,
      errorBody("invalid_request_error"),
      "400 invalid request",
      headers(),
    ),
  authentication: () =>
    new Anthropic.AuthenticationError(
      401,
      errorBody("authentication_error"),
      "401 invalid x-api-key",
      headers(),
    ),
};

function pngChunk(type: string, data: Buffer): Buffer {
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, "latin1"), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([length, body, crc]);
}

/** A real (decodable) grey PNG of the given size. */
export function pngImage(width: number, height: number): Buffer {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 0; // greyscale
  const rows = Buffer.alloc((width + 1) * height, 0x80);
  for (let row = 0; row < height; row += 1) {
    rows[row * (width + 1)] = 0; // filter: none
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk("IHDR", ihdr),
    pngChunk("IDAT", deflateSync(rows)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
}

/** JPEG markers up to the frame header (SOI, APP0, a progressive SOF2), then EOI. */
export function jpegHeader(width: number, height: number): Buffer {
  const app0 = Buffer.from([
    0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01,
    0x00, 0x00,
  ]);
  const sof = Buffer.from([0xff, 0xc2, 0x00, 0x0b, 0x08, 0, 0, 0, 0, 0x01, 0x01, 0x11, 0x00]);
  sof.writeUInt16BE(height, 5);
  sof.writeUInt16BE(width, 7);
  return Buffer.concat([Buffer.from([0xff, 0xd8]), app0, sof, Buffer.from([0xff, 0xd9])]);
}

export function gifHeader(width: number, height: number): Buffer {
  const header = Buffer.alloc(13);
  header.write("GIF89a", 0, "latin1");
  header.writeUInt16LE(width, 6);
  header.writeUInt16LE(height, 8);
  return header;
}

/** RIFF/WEBP with a VP8X (extended) header. */
export function webpHeader(width: number, height: number): Buffer {
  const bytes = Buffer.alloc(30);
  bytes.write("RIFF", 0, "latin1");
  bytes.writeUInt32LE(22, 4);
  bytes.write("WEBP", 8, "latin1");
  bytes.write("VP8X", 12, "latin1");
  bytes.writeUInt32LE(10, 16);
  bytes.writeUIntLE(width - 1, 24, 3);
  bytes.writeUIntLE(height - 1, 27, 3);
  return bytes;
}

/** The request body for an image. */
export function sketchBody(
  image: Buffer,
  mediaType = "image/png",
  hint?: string,
): Record<string, string> {
  return {
    mediaType,
    data: image.toString("base64"),
    ...(hint === undefined ? {} : { hint }),
  };
}

export const SKETCH_URL = "/v1/sketch-interpretations";

/** A placeholder key: never a real one, and no API call is made with it. */
export const TEST_API_KEY = "test-anthropic-key-not-real";

export interface SketchTestApp {
  readonly app: FastifyInstance;
  readonly issuer: TestIssuer;
  readonly db: FakeDatabase;
  readonly logs: string[];
  token(roles?: readonly string[] | null): Promise<string>;
  close(): Promise<void>;
}

/**
 * The real app (every route area). `claude` is injected as app.services.sketchClaude; leave it
 * undefined to resolve the client from config (no key configured unless env sets one).
 * `prepare` runs before ready(), for hooks.
 */
export async function sketchTestApp(
  claude: SketchClaudeClient | null | undefined,
  env: Record<string, string | undefined> = {},
  prepare?: (app: FastifyInstance) => void,
): Promise<SketchTestApp> {
  const issuer = await startTestIssuer();
  const logs = logCollector();
  const db = fakeDatabase();
  const app = await buildServer({
    config: testConfig({ ENTRA_JWKS_URL: issuer.jwksUrl, ...env }),
    db,
    ...(claude === undefined ? {} : { services: { sketchClaude: claude } }),
    logStream: logs.stream,
  });
  prepare?.(app);
  await app.ready();
  return {
    app,
    issuer,
    db,
    logs: logs.lines,
    token: (roles = ["capture"]) => issuer.mint({ roles }),
    async close() {
      await app.close();
      await issuer.close();
    },
  };
}

export function bearer(token: string): Record<string, string> {
  return { authorization: `Bearer ${token}` };
}

/** Audit rows written through the fake database: action and parsed details. */
export function auditRows(
  db: FakeDatabase,
): { action: unknown; details: Record<string, unknown> }[] {
  return db.queries
    .filter((query) => query.text.includes("INSERT INTO audit_log"))
    .map((query) => ({
      action: query.values[4],
      details: JSON.parse(String(query.values[7])) as Record<string, unknown>,
    }));
}
