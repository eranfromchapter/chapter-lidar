// Request schema and problem codes of POST /v1/sketch-interpretations (OpenAPI operation
// createSketchInterpretation).

import { MAX_PDF_BASE64_LENGTH } from "./image.js";

export interface SketchInterpretationBody {
  mediaType: string;
  data: string;
  hint?: string;
}

/** Largest hint, in characters. */
export const MAX_HINT_LENGTH = 500;

/**
 * The JSON body. mediaType and the file size are checked by the route (415 and 413, not 400),
 * so the schema only bounds them loosely.
 */
export const SKETCH_INTERPRETATION_BODY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["mediaType", "data"],
  properties: {
    mediaType: { type: "string", minLength: 1, maxLength: 100 },
    data: { type: "string", minLength: 1 },
    hint: { type: "string", minLength: 1, maxLength: MAX_HINT_LENGTH },
  },
} as const;

/**
 * Route body limit: a 24 MB PDF in base64 (the largest file accepted) plus room for the rest of
 * the JSON. A larger body is refused by Fastify before it is read (413 payload_too_large).
 */
export const SKETCH_BODY_LIMIT_BYTES = MAX_PDF_BASE64_LENGTH + 64 * 1024;

/** Problem codes of the operation. */
export const SKETCH_PROBLEMS = {
  /** 400: data is not base64, or the bytes are not an image of mediaType (or not a PDF). */
  invalidImage: "sketch_image_invalid",
  /** 413: the decoded image is larger than 10 MB, or the decoded PDF larger than 24 MB. */
  tooLarge: "sketch_image_too_large",
  /** 415: mediaType is not one the Claude API reads. */
  unsupportedMediaType: "sketch_unsupported_media_type",
  /** 422: Claude read the image and it is not a floor plan (the interpretation explains). */
  notAPlan: "sketch_not_a_plan",
  /** 422: Claude, and the server-side fallback, declined to read the image. */
  refused: "sketch_refused",
  /** 502: the reading was cut off at the output limit. */
  truncated: "sketch_truncated",
  /** 502: the answer was not a contract-valid reading. */
  unreadableResponse: "sketch_unreadable_response",
  /** 502: the Claude API refused the request itself (a station or image problem). */
  rejected: "sketch_request_rejected",
  /** 503: no API key, or Claude is unavailable after the SDK's retries. */
  unavailable: "sketch_unavailable",
} as const;
