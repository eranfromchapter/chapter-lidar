// Loads contract/openapi/station.yaml for conformance tests and validates JSON values against
// its schemas.
//
// - YAML parsing and $ref resolution use the repo's Redocly CLI (root devDependency, also used
//   by the F1 OpenAPI lint), bundled with every $ref dereferenced into a temporary JSON file.
// - Validation uses Fastify's own Ajv (the station's declared dependency) with coercion,
//   defaults and property removal switched off, so a value is checked exactly as given.
// - Fail closed: a schema keyword outside SUPPORTED_KEYWORDS fails the test, so a schema the
//   checker does not understand can never pass silently.

import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import Fastify from "fastify";

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
export type JsonSchema = { [key: string]: Json };

export interface OpenApiOperation {
  readonly method: string;
  /** OpenAPI path, for example /projects/{dealId}. */
  readonly path: string;
  readonly operationId: string;
  readonly tags: readonly string[];
  readonly roles: readonly string[];
  readonly parameters: readonly {
    name: string;
    in: string;
    required?: boolean;
    schema: JsonSchema;
  }[];
  /** status -> media type -> schema. */
  readonly responses: Readonly<Record<string, Readonly<Record<string, JsonSchema>>>>;
}

const HERE = dirname(fileURLToPath(import.meta.url));

function findUp(start: string, relative: string): string {
  let dir = start;
  for (;;) {
    const candidate = join(dir, relative);
    if (existsSync(candidate)) {
      return candidate;
    }
    const parent = dirname(dir);
    if (parent === dir) {
      throw new Error(`Could not find ${relative} above ${start}`);
    }
    dir = parent;
  }
}

/** contract/openapi/station.yaml, every $ref resolved. */
export function loadStationOpenApi(): Record<string, unknown> {
  const document = findUp(HERE, "contract/openapi/station.yaml");
  const repoRoot = resolve(dirname(document), "../..");
  const redocly = findUp(repoRoot, "node_modules/@redocly/cli/bin/cli.js");
  const out = mkdtempSync(join(tmpdir(), "station-openapi-"));
  try {
    const target = join(out, "station.json");
    const result = spawnSync(
      process.execPath,
      [redocly, "bundle", document, "--dereferenced", "--ext", "json", "--output", target],
      {
        cwd: repoRoot,
        encoding: "utf8",
        env: { ...process.env, REDOCLY_TELEMETRY: "off", REDOCLY_SUPPRESS_UPDATE_NOTICE: "true" },
      },
    );
    if (result.status !== 0 || !existsSync(target)) {
      throw new Error(`redocly bundle failed:\n${result.stderr}\n${result.stdout}`);
    }
    return JSON.parse(readFileSync(target, "utf8")) as Record<string, unknown>;
  } finally {
    rmSync(out, { recursive: true, force: true });
  }
}

const METHODS = ["get", "put", "post", "delete", "patch", "head", "options"];

/** Every operation of the document. */
export function operations(document: Record<string, unknown>): OpenApiOperation[] {
  const paths = document.paths as Record<string, Record<string, unknown>>;
  const result: OpenApiOperation[] = [];
  for (const [path, item] of Object.entries(paths)) {
    const shared = (item.parameters ?? []) as OpenApiOperation["parameters"];
    for (const method of METHODS) {
      const operation = item[method] as Record<string, unknown> | undefined;
      if (operation === undefined) {
        continue;
      }
      const responses: Record<string, Record<string, JsonSchema>> = {};
      for (const [status, response] of Object.entries(
        operation.responses as Record<string, { content?: Record<string, { schema: JsonSchema }> }>,
      )) {
        responses[status] = Object.fromEntries(
          Object.entries(response.content ?? {}).map(([type, media]) => [type, media.schema]),
        );
      }
      result.push({
        method: method.toUpperCase(),
        path,
        operationId: String(operation.operationId),
        tags: (operation.tags ?? []) as string[],
        roles: (operation["x-roles"] ?? []) as string[],
        parameters: [
          ...shared,
          ...((operation.parameters ?? []) as OpenApiOperation["parameters"]),
        ],
        responses,
      });
    }
  }
  return result;
}

/** /projects/{dealId} -> /v1/projects/:dealId (the Fastify route URL). */
export function routeUrl(path: string): string {
  return `/v1${path.replace(/\{([A-Za-z0-9_]+)\}/g, ":$1")}`;
}

/** Copy of a schema without annotation keywords (description), for comparisons. */
export function withoutAnnotations(schema: Json): Json {
  if (Array.isArray(schema)) {
    return schema.map(withoutAnnotations);
  }
  if (schema === null || typeof schema !== "object") {
    return schema;
  }
  return Object.fromEntries(
    Object.entries(schema)
      .filter(([key]) => key !== "description")
      .map(([key, value]) => [key, withoutAnnotations(value)]),
  );
}

const SUPPORTED_KEYWORDS = new Set([
  "type",
  "properties",
  "required",
  "additionalProperties",
  "items",
  "minItems",
  "maxItems",
  "minLength",
  "maxLength",
  "pattern",
  "minimum",
  "maximum",
  "format",
  "const",
  "enum",
  "description",
  "default",
]);

function assertSupported(schema: Json, where: string): void {
  if (schema === null || typeof schema !== "object" || Array.isArray(schema)) {
    return;
  }
  for (const [key, value] of Object.entries(schema)) {
    if (!SUPPORTED_KEYWORDS.has(key)) {
      throw new Error(`Schema keyword "${key}" at ${where} is not supported by this checker`);
    }
    if (key === "properties" && value !== null && typeof value === "object") {
      for (const [name, sub] of Object.entries(value)) {
        assertSupported(sub, `${where}/properties/${name}`);
      }
    } else if (key === "items" || (key === "additionalProperties" && typeof value === "object")) {
      assertSupported(value, `${where}/${key}`);
    }
  }
}

export interface SchemaValidator {
  /** Error messages; empty when the value is valid. */
  validate(name: string, value: unknown): Promise<string[]>;
  close(): Promise<void>;
}

/** Compiles the named schemas with Fastify's Ajv (strict JSON checks, no coercion). */
export async function schemaValidator(
  schemas: Readonly<Record<string, JsonSchema>>,
): Promise<SchemaValidator> {
  const app = Fastify({
    logger: false,
    ajv: {
      customOptions: {
        removeAdditional: false,
        coerceTypes: false,
        useDefaults: false,
        allErrors: true,
      },
    },
  });
  const names = Object.keys(schemas);
  names.forEach((name, index) => {
    const schema = schemas[name] as JsonSchema;
    assertSupported(schema, name);
    app.post(`/validate/${index}`, { schema: { body: schema } }, async () => ({ valid: true }));
  });
  app.setErrorHandler((error: Error, _request, reply) => {
    const issues = (error as { validation?: { instancePath?: string; message?: string }[] })
      .validation;
    return reply.code(400).send({
      errors: issues?.map((issue) => `${issue.instancePath || "/"} ${issue.message ?? ""}`) ?? [
        error.message,
      ],
    });
  });
  await app.ready();
  return {
    async validate(name, value) {
      const index = names.indexOf(name);
      if (index < 0) {
        throw new Error(`No schema named ${name}`);
      }
      const response = await app.inject({
        method: "POST",
        url: `/validate/${index}`,
        headers: { "content-type": "application/json" },
        payload: JSON.stringify(value),
      });
      return response.statusCode === 200
        ? []
        : ((response.json() as { errors: string[] }).errors ?? ["invalid"]);
    },
    close: () => app.close(),
  };
}
