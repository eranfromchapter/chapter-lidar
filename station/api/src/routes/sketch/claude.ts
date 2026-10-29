// Claude for the sketch reading (spec F16 §6): the client service, the system prompt, the
// structured-output schema and the request the station sends.
//
// - The client is `app.services.sketchClaude`. Tests inject a fake through
//   buildServer({ services: { sketchClaude } }), so no test reaches the network. Otherwise it is
//   built from config once; null when ANTHROPIC_API_KEY is not set (the route answers 503).
// - The system prompt is contract/prompts/sketch-interpretation.md, read from the file when the
//   route area loads (the image copies contract/prompts). It is the single source: the app's
//   Debug field test reads the same file.
// - The output format is the contract schema's $defs/reading with every $ref inlined, so the
//   schema sent to the API is self-contained, and without the keywords structured outputs do not
//   accept (numeric, string and array bounds; the reading uses none of them today).

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import Anthropic from "@anthropic-ai/sdk";
import type { FastifyInstance } from "fastify";
import { SCHEMAS } from "@chapter/capture-contract";
import "../../core/fastify-types.js";
import type { SketchMediaType } from "./image.js";

/** What the route needs of the SDK client: the beta Messages API (server-side fallbacks). */
export interface SketchClaudeClient {
  readonly beta: {
    readonly messages: {
      create(
        body: Anthropic.Beta.Messages.MessageCreateParamsNonStreaming,
        options?: Anthropic.RequestOptions,
      ): PromiseLike<Anthropic.Beta.Messages.BetaMessage>;
    };
  };
}

declare module "../../core/services.js" {
  interface StationServices {
    /** Claude client for the sketch reading; null when no API key is configured. */
    sketchClaude: SketchClaudeClient | null;
  }
}

/** Per-request timeout (spec F16 §6). */
export const SKETCH_TIMEOUT_MS = 120_000;
/** SDK retries on connection errors, 408, 409, 429 and 5xx (the SDK default). */
export const SKETCH_MAX_RETRIES = 2;
/** Room for adaptive thinking and the reading; non-streaming stays well inside the timeout. */
export const SKETCH_MAX_TOKENS = 16_000;
/** Geometry from a photo: more thinking than Claude Opus 5.5's default (medium). */
export const SKETCH_EFFORT = "high";
/** Server-side refusal fallback, "default" form (beta header for that form). */
export const SKETCH_FALLBACK_BETA = "server-side-fallback-2026-07-01";

/** contract/prompts/sketch-interpretation.md (src/ and dist/ sit at the same depth). */
export const SKETCH_PROMPT_PATH = fileURLToPath(
  new URL("../../../../../contract/prompts/sketch-interpretation.md", import.meta.url),
);

/** The system prompt, exactly as in the contract file. */
export function loadSketchPrompt(path = SKETCH_PROMPT_PATH): string {
  return readFileSync(path, "utf8");
}

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type JsonObject = { [key: string]: Json };

/** Keywords structured outputs do not accept (the SDK docs' "not supported" list). */
const UNSUPPORTED_KEYWORDS = new Set([
  "minimum",
  "maximum",
  "exclusiveMinimum",
  "exclusiveMaximum",
  "multipleOf",
  "minLength",
  "maxLength",
  "minItems",
  "maxItems",
  "uniqueItems",
  "contains",
  "minContains",
  "maxContains",
]);

function isObject(value: Json | undefined): value is JsonObject {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function inline(value: Json, defs: JsonObject, seen: readonly string[]): Json {
  if (Array.isArray(value)) {
    return value.map((item) => inline(item, defs, seen));
  }
  if (!isObject(value)) {
    return value;
  }
  const ref = value.$ref;
  if (typeof ref === "string") {
    const match = /^#\/\$defs\/([A-Za-z0-9_-]+)$/.exec(ref);
    const name = match?.[1];
    const target = name === undefined ? undefined : defs[name];
    if (name === undefined || !isObject(target)) {
      throw new Error(`sketch reading schema: unresolvable $ref ${ref}`);
    }
    if (seen.includes(name)) {
      throw new Error(`sketch reading schema: recursive $ref ${ref}`);
    }
    // Keywords next to the $ref (none today) apply on top of the target.
    const { $ref: _ref, ...siblings } = value;
    return inline({ ...target, ...siblings }, defs, [...seen, name]);
  }
  const out: JsonObject = {};
  for (const [key, item] of Object.entries(value)) {
    if (UNSUPPORTED_KEYWORDS.has(key)) {
      continue;
    }
    // Under "properties" every key is a property name, not a keyword.
    out[key] =
      key === "properties" && isObject(item)
        ? Object.fromEntries(
            Object.entries(item).map(([name, schema]) => [name, inline(schema, defs, seen)]),
          )
        : inline(item, defs, seen);
  }
  return out;
}

/** The reading schema (contract $defs/reading), self-contained, for output_config.format. */
export function readingOutputSchema(): Record<string, unknown> {
  const schema = SCHEMAS["sketch-interpretation"] as JsonObject;
  const defs = schema.$defs;
  if (!isObject(defs) || !isObject(defs.reading)) {
    throw new Error("sketch-interpretation schema has no $defs/reading");
  }
  return inline(defs.reading, defs, ["reading"]) as Record<string, unknown>;
}

export interface SketchRequestInput {
  readonly model: string;
  readonly systemPrompt: string;
  readonly outputSchema: Record<string, unknown>;
  readonly mediaType: SketchMediaType;
  /** Base64 image data, as received. */
  readonly data: string;
  readonly hint?: string;
}

/** The user instruction after the image; the hint (from the field operator) is appended. */
export function sketchInstruction(hint?: string): string {
  const base = "Read this floor-plan sketch.";
  return hint === undefined ? base : `${base}\n\nNote from the field operator: ${hint}`;
}

/** The Messages API request for one sketch photo. */
export function buildSketchRequest(
  input: SketchRequestInput,
): Anthropic.Beta.Messages.MessageCreateParamsNonStreaming {
  return {
    model: input.model,
    max_tokens: SKETCH_MAX_TOKENS,
    betas: [SKETCH_FALLBACK_BETA],
    fallbacks: "default",
    system: input.systemPrompt,
    // Claude Opus 5.5 always thinks (adaptive); stated explicitly so an older SKETCH_MODEL
    // that supports adaptive thinking also thinks.
    thinking: { type: "adaptive" },
    output_config: {
      effort: SKETCH_EFFORT,
      format: { type: "json_schema", schema: input.outputSchema },
    },
    messages: [
      {
        role: "user",
        content: [
          {
            type: "image",
            source: { type: "base64", media_type: input.mediaType, data: input.data },
          },
          { type: "text", text: sketchInstruction(input.hint) },
        ],
      },
    ],
  };
}

/** Builds the SDK client for an API key. */
export function createSketchClaudeClient(apiKey: string): SketchClaudeClient {
  return new Anthropic({ apiKey, timeout: SKETCH_TIMEOUT_MS, maxRetries: SKETCH_MAX_RETRIES });
}

/** The app's client: the injected one, else one built from config (null without a key). */
export function resolveSketchClaude(app: FastifyInstance): SketchClaudeClient | null {
  const existing = app.services.sketchClaude;
  if (existing !== undefined) {
    return existing;
  }
  // Read the secret from the config object itself: it is non-enumerable, so a spread drops it.
  const apiKey = app.config.sketch.anthropicApiKey;
  const created = apiKey === undefined ? null : createSketchClaudeClient(apiKey);
  app.services.sketchClaude = created;
  return created;
}
