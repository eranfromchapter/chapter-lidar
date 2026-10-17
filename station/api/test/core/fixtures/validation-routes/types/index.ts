// Test-only route area for request validation (test/core/validation.test.ts): one route per
// request part. Each answers with what the handler received and the JavaScript type of it, so
// a test can tell a value that was converted from one that arrived as sent.

import type { FastifyInstance } from "fastify";

export default async function typesRoutes(app: FastifyInstance): Promise<void> {
  app.post<{ Body: Record<string, unknown> }>(
    "/types/body",
    {
      config: { roles: ["bim"] },
      schema: {
        body: {
          type: "object",
          additionalProperties: false,
          required: ["count"],
          properties: {
            count: { type: "integer", minimum: 0 },
            flag: { type: "boolean" },
            label: { type: "string" },
            tags: { type: "array", items: { type: "string" } },
            mode: { type: "string", default: "plain" },
          },
        },
      },
    },
    async (request) => {
      const types = Object.fromEntries(
        Object.entries(request.body).map(([key, value]) => [
          key,
          Array.isArray(value) ? "array" : typeof value,
        ]),
      );
      return { body: request.body, types };
    },
  );

  app.get<{ Querystring: { limit?: number; tag?: string[] } }>(
    "/types/query",
    {
      config: { roles: ["bim"] },
      schema: {
        querystring: {
          type: "object",
          additionalProperties: false,
          properties: {
            limit: { type: "integer", minimum: 1, maximum: 100, default: 25 },
            tag: { type: "array", items: { type: "string" } },
          },
        },
      },
    },
    async (request) => {
      const { limit, tag } = request.query;
      return { limit, limitType: typeof limit, ...(tag === undefined ? {} : { tag }) };
    },
  );

  app.get<{ Params: { n: number } }>(
    "/types/items/:n",
    {
      config: { roles: ["bim"] },
      schema: {
        params: {
          type: "object",
          required: ["n"],
          properties: { n: { type: "integer", minimum: 1 } },
        },
      },
    },
    async (request) => {
      return { n: request.params.n, nType: typeof request.params.n };
    },
  );
}
