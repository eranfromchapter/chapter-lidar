// GET /health and GET /v1/health: unauthenticated liveness check (operation getHealth).
// 200 {status: "ok", version} when the registry answers; 503 problem otherwise.

import type { FastifyInstance } from "fastify";
import { sendProblem } from "./problem.js";

const healthResponse = {
  type: "object",
  additionalProperties: false,
  required: ["status", "version"],
  properties: {
    status: { const: "ok" },
    version: { type: "string", minLength: 1, maxLength: 50 },
  },
} as const;

export async function healthRoutes(app: FastifyInstance): Promise<void> {
  for (const url of ["/health", "/v1/health"]) {
    app.get(
      url,
      {
        config: { public: true },
        schema: { response: { 200: healthResponse } },
      },
      async (request, reply) => {
        try {
          await app.db.ping();
        } catch (error) {
          request.log.error({ err: error }, "health: registry unreachable");
          return sendProblem(reply, 503, "registry_unavailable", {
            detail: "The station registry is unreachable.",
          });
        }
        return { status: "ok" as const, version: app.config.version };
      },
    );
  }
}
