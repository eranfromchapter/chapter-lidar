// Test-only route area, autoloaded like src/routes/<area>/index.ts.

import type { FastifyInstance } from "fastify";
import { requirePrincipal } from "../../../../../src/core/auth.js";

export default async function probeRoutes(app: FastifyInstance): Promise<void> {
  app.get("/probe/bim", { config: { roles: ["bim"] } }, async (request) => {
    const principal = requirePrincipal(request);
    return { userId: principal.userId, name: principal.name, roles: principal.roles };
  });

  app.post(
    "/probe/:packageId/notes",
    {
      config: { roles: ["capture", "admin"] },
      schema: {
        body: {
          type: "object",
          additionalProperties: false,
          required: ["text"],
          properties: { text: { type: "string", minLength: 1 } },
        },
      },
    },
    async (_request, reply) => reply.code(201).send({ ok: true }),
  );
}
