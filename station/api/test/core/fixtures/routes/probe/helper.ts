// Not a route plugin: only <area>/index files are autoloaded. If this file were loaded, its
// route (which has no access rule) would make the server fail at startup.

import type { FastifyInstance } from "fastify";

export default async function notARoutePlugin(app: FastifyInstance): Promise<void> {
  app.get("/probe/helper", async () => ({ loaded: true }));
}
