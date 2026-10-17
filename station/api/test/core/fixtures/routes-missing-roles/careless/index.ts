// Test-only route area whose route declares no roles: the server must refuse to start.

import type { FastifyInstance } from "fastify";

export default async function carelessRoutes(app: FastifyInstance): Promise<void> {
  app.get("/careless", async () => ({ open: true }));
}
