// Fastify type extensions used by every station route. Imported for its side effect by app.ts
// and auth.ts so the augmentation is in scope wherever the core is used.

import type { Role, Principal, RouteAccess } from "./auth.js";
import type { StationConfig } from "./config.js";
import type { Database } from "./db.js";
import type { StationServices } from "./services.js";

declare module "fastify" {
  interface FastifyContextConfig {
    /** Station roles allowed to call the route. Required on every route except /health. */
    roles?: readonly Role[];
    /** Only for /health: the route needs no token. */
    public?: true;
  }

  interface FastifyInstance {
    readonly config: StationConfig;
    readonly db: Database;
    readonly services: Partial<StationServices>;
    /** Access rule of every registered route, in registration order. */
    readonly routeAccess: readonly RouteAccess[];
  }

  interface FastifyRequest {
    /** Verified caller on protected routes; null on public routes and before auth. */
    principal: Principal | null;
  }
}
