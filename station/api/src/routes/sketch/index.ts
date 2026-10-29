// Sketch photo reading (spec F16 §3, §6; OpenAPI operation createSketchInterpretation).
//
// POST /v1/sketch-interpretations sends one sketch photo to Claude (vision, structured output
// in the contract's reading format) and answers the sketch interpretation:
//
// - 200: the interpretation (contract sketch-interpretation 1.0.0), validated before it is sent.
// - 422 sketch_not_a_plan: Claude read the image and it is not a floor plan; the problem body
//   carries the interpretation so the app can show reading.problem. 422 sketch_refused: Claude
//   and the server-side fallback declined.
// - 400/413/415: the image is not base64 or not an image of mediaType / larger than 10 MB / not
//   a media type the Claude API reads.
// - 502: the answer was cut off, not a valid reading, or the API refused the request itself.
// - 503 sketch_unavailable: no API key, or Claude unreachable after the SDK's retries.
//
// The station never stores the image and never logs it or the API key. Every call that sends
// the image to Anthropic writes one audit row (sketch.interpret): who, when, image bytes, model,
// outcome and tokens, no image content.

import Anthropic from "@anthropic-ai/sdk";
import {
  type SketchInterpretation,
  formatErrors,
  validateSketchInterpretation,
} from "@chapter/capture-contract";
import type { FastifyBaseLogger, FastifyInstance, FastifyRequest } from "fastify";
import { audit } from "../../core/audit.js";
import { ProblemError } from "../../core/problem.js";
import { toApiDateTime } from "../../core/time.js";
import {
  SKETCH_PROMPT_PATH,
  SKETCH_TIMEOUT_MS,
  buildSketchRequest,
  loadSketchPrompt,
  readingOutputSchema,
  resolveSketchClaude,
} from "./claude.js";
import {
  type ImageSize,
  MAX_IMAGE_BYTES,
  SKETCH_MEDIA_TYPES,
  base64DecodedLength,
  imageSize,
  isSketchMediaType,
} from "./image.js";
import {
  SKETCH_BODY_LIMIT_BYTES,
  SKETCH_INTERPRETATION_BODY_SCHEMA,
  SKETCH_PROBLEMS,
  type SketchInterpretationBody,
} from "./schemas.js";

/** Audit action of one call to Claude. */
export const SKETCH_AUDIT_ACTION = "sketch.interpret";

const UNAVAILABLE_DETAIL =
  "Sketch reading is not available right now. Try again later, or enter the sketch by hand.";

type BetaMessage = Anthropic.Beta.Messages.BetaMessage;

/** What one call produced, for the audit row. */
interface CallRecord {
  outcome: string;
  servedBy?: string;
  fallback?: boolean;
  inputTokens?: number;
  outputTokens?: number;
  anthropicRequestId?: string;
}

function tokens(message: BetaMessage): Pick<CallRecord, "inputTokens" | "outputTokens"> {
  // usage.iterations lists every attempt (a declined attempt and its fallback); the top-level
  // usage covers only the attempt that produced the message.
  const iterations = message.usage.iterations ?? [];
  if (iterations.length > 0) {
    return {
      inputTokens: iterations.reduce((sum, entry) => sum + (entry.input_tokens ?? 0), 0),
      outputTokens: iterations.reduce((sum, entry) => sum + (entry.output_tokens ?? 0), 0),
    };
  }
  return { inputTokens: message.usage.input_tokens, outputTokens: message.usage.output_tokens };
}

function describeMessage(message: BetaMessage): Omit<CallRecord, "outcome"> {
  const requestId = (message as { _request_id?: string | null })._request_id;
  return {
    servedBy: message.model,
    fallback: (message.usage.iterations ?? []).some((entry) => entry.type === "fallback_message"),
    ...tokens(message),
    ...(typeof requestId === "string" ? { anthropicRequestId: requestId } : {}),
  };
}

/** The answer text: text blocks after the last fallback boundary (a declined partial is not used). */
function answerText(message: BetaMessage): string {
  const lastFallback = message.content.map((block) => block.type).lastIndexOf("fallback");
  return message.content
    .slice(lastFallback + 1)
    .flatMap((block) => (block.type === "text" ? [block.text] : []))
    .join("");
}

/** Interpretation of a successful message, or the problem to answer instead. */
function interpret(
  message: BetaMessage,
  image: ImageSize,
  log: FastifyBaseLogger,
): { interpretation: SketchInterpretation } | { problem: ProblemError; outcome: string } {
  if (message.stop_reason === "refusal") {
    log.warn(
      { sketch: { category: message.stop_details?.category ?? null } },
      "Claude declined to read the sketch",
    );
    return {
      outcome: "refused",
      problem: new ProblemError(422, SKETCH_PROBLEMS.refused, {
        detail: "The sketch could not be read. Retake the photo, or enter the sketch by hand.",
      }),
    };
  }
  if (message.stop_reason === "max_tokens") {
    return {
      outcome: "truncated",
      problem: new ProblemError(502, SKETCH_PROBLEMS.truncated, {
        detail: "The reading of the sketch was cut off. Try again, or enter the sketch by hand.",
      }),
    };
  }
  const unreadable = (reason: string, extra: Record<string, unknown> = {}) => {
    log.error({ sketch: { reason, stopReason: message.stop_reason, ...extra } }, reason);
    return {
      outcome: "unreadable_response",
      problem: new ProblemError(502, SKETCH_PROBLEMS.unreadableResponse, {
        detail: "Claude's answer was not a usable reading. Try again, or enter the sketch by hand.",
      }),
    };
  };
  if (message.stop_reason !== "end_turn") {
    return unreadable("unexpected stop reason from Claude");
  }
  let reading: unknown;
  try {
    reading = JSON.parse(answerText(message));
  } catch {
    return unreadable("Claude's answer is not JSON");
  }
  const candidate = {
    schemaVersion: "1.0.0",
    model: message.model,
    interpretedAt: toApiDateTime(new Date()),
    image: { width: image.width, height: image.height },
    reading,
  };
  const result = validateSketchInterpretation(candidate);
  if (!result.ok) {
    // Paths and schema messages only: no values from the answer.
    return unreadable("Claude's reading does not match the contract", {
      errors: formatErrors(result.errors.slice(0, 10)),
    });
  }
  return { interpretation: result.value };
}

/** Maps an SDK error to the answer; null for anything that is not an API error (a bug). */
function upstreamProblem(
  error: unknown,
  log: FastifyBaseLogger,
): { problem: ProblemError; outcome: string } | null {
  if (!(error instanceof Anthropic.APIError)) {
    return null;
  }
  const where = {
    status: error.status ?? null,
    type: error.type ?? null,
    requestId: error.requestID ?? null,
  };
  if (error instanceof Anthropic.RateLimitError) {
    const retryAfter = error.headers?.get("retry-after") ?? undefined;
    log.warn({ sketch: where }, "Claude rate limit reached after retries");
    return {
      outcome: "rate_limited",
      problem: new ProblemError(503, SKETCH_PROBLEMS.unavailable, {
        detail: UNAVAILABLE_DETAIL,
        ...(retryAfter !== undefined && /^\d{1,6}$/.test(retryAfter)
          ? { headers: { "Retry-After": retryAfter } }
          : {}),
      }),
    };
  }
  if (
    error instanceof Anthropic.AuthenticationError ||
    error instanceof Anthropic.PermissionDeniedError
  ) {
    log.error(
      { sketch: where },
      "ANTHROPIC_API_KEY was rejected by the Claude API: sketch reading is down until it is replaced",
    );
    return {
      outcome: "auth_failed",
      problem: new ProblemError(503, SKETCH_PROBLEMS.unavailable, { detail: UNAVAILABLE_DETAIL }),
    };
  }
  if (error instanceof Anthropic.APIConnectionError) {
    // Includes the request timeout (APIConnectionTimeoutError).
    log.warn({ sketch: where }, "Claude API unreachable after retries");
    return {
      outcome: "unreachable",
      problem: new ProblemError(503, SKETCH_PROBLEMS.unavailable, { detail: UNAVAILABLE_DETAIL }),
    };
  }
  if (error instanceof Anthropic.InternalServerError) {
    // 5xx and 529 overloaded, after retries.
    log.warn({ sketch: where }, "Claude API error or overloaded after retries");
    return {
      outcome: "server_error",
      problem: new ProblemError(503, SKETCH_PROBLEMS.unavailable, { detail: UNAVAILABLE_DETAIL }),
    };
  }
  // 400 and other client errors: the request the station built (or the image) was refused.
  log.error(
    { sketch: { ...where, message: error.message.slice(0, 500) } },
    "Claude API refused the sketch request",
  );
  return {
    outcome: "rejected",
    problem: new ProblemError(502, SKETCH_PROBLEMS.rejected, {
      detail: "The sketch could not be sent for reading. Try another photo, or enter it by hand.",
    }),
  };
}

export default async function sketchRoutes(app: FastifyInstance): Promise<void> {
  // Read once at startup. A missing prompt file is a packaging fault: the route answers 503
  // and the rest of the station keeps working.
  let systemPrompt: string | null;
  try {
    systemPrompt = loadSketchPrompt();
  } catch {
    systemPrompt = null;
    app.log.error(
      { path: SKETCH_PROMPT_PATH },
      "sketch prompt file missing: sketch reading is off",
    );
  }
  const outputSchema = readingOutputSchema();

  async function record(
    request: FastifyRequest,
    bytes: number,
    mediaType: string,
    call: CallRecord,
  ): Promise<void> {
    try {
      await audit(
        request,
        SKETCH_AUDIT_ACTION,
        { type: "sketch_interpretation" },
        { bytes, mediaType, model: request.server.config.sketch.model, ...call },
      );
    } catch (error) {
      // The answer is already paid for; a failed audit row is logged loudly, not returned.
      request.log.error(
        { err: error, sketch: { bytes, outcome: call.outcome } },
        "could not write the sketch.interpret audit row",
      );
    }
  }

  app.post<{ Body: SketchInterpretationBody }>(
    "/sketch-interpretations",
    {
      config: { roles: ["capture"] },
      bodyLimit: SKETCH_BODY_LIMIT_BYTES,
      schema: { body: SKETCH_INTERPRETATION_BODY_SCHEMA },
    },
    async (request, reply) => {
      const { mediaType, data } = request.body;
      const hint = request.body.hint?.trim() || undefined;

      if (!isSketchMediaType(mediaType)) {
        throw new ProblemError(415, SKETCH_PROBLEMS.unsupportedMediaType, {
          detail: `The image must be one of ${SKETCH_MEDIA_TYPES.join(", ")}. Convert HEIC to JPEG.`,
        });
      }
      const bytes = base64DecodedLength(data);
      if (bytes === null) {
        throw new ProblemError(400, SKETCH_PROBLEMS.invalidImage, {
          detail: "data must be the image in standard base64 (no line breaks, padded).",
          errors: [{ pointer: "/data", message: "is not base64" }],
        });
      }
      if (bytes > MAX_IMAGE_BYTES) {
        throw new ProblemError(413, SKETCH_PROBLEMS.tooLarge, {
          detail: `The image is ${bytes} bytes; at most ${MAX_IMAGE_BYTES} are accepted.`,
        });
      }
      const size = imageSize(Buffer.from(data, "base64"), mediaType);
      if (size === null) {
        throw new ProblemError(400, SKETCH_PROBLEMS.invalidImage, {
          detail: `data is not a readable ${mediaType} image.`,
          errors: [{ pointer: "/data", message: `is not a ${mediaType} image` }],
        });
      }

      const client = resolveSketchClaude(app);
      if (client === null || systemPrompt === null) {
        request.log.warn(
          { sketch: { apiKey: client !== null, prompt: systemPrompt !== null } },
          "sketch reading requested but not configured (ANTHROPIC_API_KEY or prompt missing)",
        );
        throw new ProblemError(503, SKETCH_PROBLEMS.unavailable, { detail: UNAVAILABLE_DETAIL });
      }

      const params = buildSketchRequest({
        model: app.config.sketch.model,
        systemPrompt,
        outputSchema,
        mediaType,
        data,
        ...(hint === undefined ? {} : { hint }),
      });

      let message: BetaMessage;
      try {
        message = await client.beta.messages.create(params, { timeout: SKETCH_TIMEOUT_MS });
      } catch (error) {
        const mapped = upstreamProblem(error, request.log);
        await record(request, bytes, mediaType, { outcome: mapped?.outcome ?? "error" });
        throw mapped?.problem ?? error;
      }

      const result = interpret(message, size, request.log);
      if ("problem" in result) {
        await record(request, bytes, mediaType, {
          outcome: result.outcome,
          ...describeMessage(message),
        });
        throw result.problem;
      }
      const { interpretation } = result;
      if (!interpretation.reading.isFloorPlan) {
        await record(request, bytes, mediaType, {
          outcome: "not_a_plan",
          ...describeMessage(message),
        });
        throw new ProblemError(422, SKETCH_PROBLEMS.notAPlan, {
          detail: interpretation.reading.problem ?? "The photo does not show a floor plan.",
          extensions: { interpretation },
        });
      }
      await record(request, bytes, mediaType, { outcome: "ok", ...describeMessage(message) });
      return reply.code(200).send(interpretation);
    },
  );
}
