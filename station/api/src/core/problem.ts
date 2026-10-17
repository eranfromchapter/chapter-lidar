// RFC 9457 problem details for every error the station returns.
//
// Route code throws ProblemError (or calls sendProblem); the error handler turns Fastify
// errors (validation, bad JSON, body too large, unknown routes) and unexpected errors into the
// same shape. 5xx responses never carry internal error text.

import { STATUS_CODES } from "node:http";
import type { FastifyError, FastifyInstance, FastifyReply } from "fastify";
import fp from "fastify-plugin";

export const PROBLEM_CONTENT_TYPE = "application/problem+json";

export interface ProblemFieldError {
  /** JSON Pointer to the offending value in the request body. */
  pointer: string;
  message: string;
}

export interface Problem {
  type: string;
  title: string;
  status: number;
  code: string;
  detail?: string;
  errors?: ProblemFieldError[];
}

export interface ProblemOptions {
  detail?: string;
  errors?: ProblemFieldError[];
  title?: string;
  type?: string;
  /** Extra response headers, for example WWW-Authenticate. */
  headers?: Record<string, string>;
}

const CODE_PATTERN = /^[a-z][a-z0-9_]*$/;

/** Error that the error handler turns into a problem response. */
export class ProblemError extends Error {
  readonly status: number;
  readonly code: string;
  readonly options: ProblemOptions;

  constructor(status: number, code: string, options: ProblemOptions = {}) {
    super(options.detail ?? code);
    if (!Number.isInteger(status) || status < 400 || status > 599) {
      throw new RangeError(`Problem status must be 400-599, got ${status}`);
    }
    if (!CODE_PATTERN.test(code)) {
      throw new RangeError(`Problem code must match ${CODE_PATTERN}, got ${code}`);
    }
    this.name = "ProblemError";
    this.status = status;
    this.code = code;
    this.options = options;
  }
}

/** Default code for a status, for example 404 -> not_found. */
export function defaultCode(status: number): string {
  const phrase = STATUS_CODES[status] ?? (status >= 500 ? "Internal Server Error" : "Bad Request");
  return phrase
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
}

export function problemBody(status: number, code: string, options: ProblemOptions = {}): Problem {
  const body: Problem = {
    type: options.type ?? "about:blank",
    title: options.title ?? STATUS_CODES[status] ?? "Error",
    status,
    code,
  };
  if (options.detail !== undefined) {
    body.detail = options.detail;
  }
  if (options.errors !== undefined && options.errors.length > 0) {
    body.errors = options.errors;
  }
  return body;
}

export function sendProblem(
  reply: FastifyReply,
  status: number,
  code: string,
  options: ProblemOptions = {},
): FastifyReply {
  for (const [name, value] of Object.entries(options.headers ?? {})) {
    reply.header(name, value);
  }
  return reply
    .code(status)
    .type(PROBLEM_CONTENT_TYPE)
    .send(JSON.stringify(problemBody(status, code, options)));
}

function escapePointerToken(token: string): string {
  return token.replace(/~/g, "~0").replace(/\//g, "~1");
}

interface ValidationIssue {
  instancePath?: string;
  keyword?: string;
  message?: string;
  params?: Record<string, unknown>;
}

/** Maps Ajv validation errors to problem field errors with JSON Pointers. */
export function validationErrors(issues: readonly ValidationIssue[]): ProblemFieldError[] {
  return issues.map((issue) => {
    let pointer = issue.instancePath ?? "";
    const params = issue.params ?? {};
    if (issue.keyword === "required" && typeof params.missingProperty === "string") {
      pointer += `/${escapePointerToken(params.missingProperty)}`;
    } else if (
      issue.keyword === "additionalProperties" &&
      typeof params.additionalProperty === "string"
    ) {
      pointer += `/${escapePointerToken(params.additionalProperty)}`;
    }
    return { pointer, message: issue.message ?? issue.keyword ?? "is invalid" };
  });
}

async function problemPlugin(app: FastifyInstance): Promise<void> {
  app.setNotFoundHandler((request, reply) => {
    sendProblem(reply, 404, "not_found", {
      detail: `No route for ${request.method} ${request.url.split("?")[0] ?? ""}.`,
    });
  });

  app.setErrorHandler((error: FastifyError | ProblemError | Error, request, reply) => {
    if (error instanceof ProblemError) {
      if (error.status >= 500) {
        request.log.error({ code: error.code }, "request failed with a server problem");
      }
      return sendProblem(reply, error.status, error.code, error.options);
    }

    const fastifyError = error as FastifyError;
    if (Array.isArray(fastifyError.validation)) {
      const where = fastifyError.validationContext ?? "request";
      const errors = where === "body" ? validationErrors(fastifyError.validation) : [];
      return sendProblem(reply, 400, "invalid_request", {
        detail:
          where === "body"
            ? "The request body does not match the schema."
            : `Invalid ${where}: ${fastifyError.message}`,
        errors,
      });
    }

    const status = fastifyError.statusCode;
    if (typeof status === "number" && status >= 400 && status < 500) {
      return sendProblem(reply, status, defaultCode(status), { detail: fastifyError.message });
    }

    request.log.error({ err: error }, "unhandled error");
    return sendProblem(reply, 500, "internal_error", {
      detail: "The station could not complete the request.",
    });
  });
}

/** Registers the problem+json error and not-found handlers on the root instance. */
export const problems = fp(problemPlugin, { name: "station-problems", fastify: "5.x" });
