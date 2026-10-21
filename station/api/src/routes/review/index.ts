// Review screen lists (contract/openapi/station.yaml, tag review):
//
//   GET /v1/review/projects?q&limit   listReviewProjects   capture, bim, admin
//   GET /v1/review/packages?q&limit   listReviewPackages   capture, bim, admin
//
// Reads only: nothing is written, so nothing is audited. The capture role sees the lists (it
// shows status only; the station enforces roles on every package operation). See store.ts for
// names, ordering and search.

import type { FastifyInstance } from "fastify";
import type { Role } from "../../core/auth.js";
import {
  REVIEW_LIST_DEFAULT_LIMIT,
  reviewListQuerySchema,
  type ReviewListQuery,
} from "./schemas.js";
import { listReviewPackages, listReviewProjects } from "./store.js";

const REVIEW_ROLES: readonly Role[] = ["capture", "bim", "admin"];

export default async function reviewRoutes(app: FastifyInstance): Promise<void> {
  const links = app.config.links;

  app.get<{ Querystring: ReviewListQuery }>(
    "/review/projects",
    { config: { roles: REVIEW_ROLES }, schema: { querystring: reviewListQuerySchema } },
    async (request) => {
      const { q, limit = REVIEW_LIST_DEFAULT_LIMIT } = request.query;
      const page = await listReviewProjects(app.db, links, q, limit);
      return { projects: page.items, truncated: page.truncated };
    },
  );

  app.get<{ Querystring: ReviewListQuery }>(
    "/review/packages",
    { config: { roles: REVIEW_ROLES }, schema: { querystring: reviewListQuerySchema } },
    async (request) => {
      const { q, limit = REVIEW_LIST_DEFAULT_LIMIT } = request.query;
      const page = await listReviewPackages(app.db, links, q, limit);
      return { packages: page.items, truncated: page.truncated };
    },
  );
}
