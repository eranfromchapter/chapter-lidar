// HUB project lookup for the capture app (OpenAPI operations listProjects and getProject).
//
// Only HUB deals with a confirmed address are returned; the key is the HUB's sales dealId.
// HUB failures answer 502 hub_unavailable. Read-only: nothing is written, so nothing is audited.

import type { FastifyBaseLogger, FastifyInstance } from "fastify";
import { resolveHubClient } from "../../hub/service.js";
import { HubError, type HubClient } from "../../hub/types.js";
import { ProblemError } from "../../core/problem.js";
import {
  LIST_PROJECTS_DEFAULT_LIMIT,
  LIST_PROJECTS_QUERY_SCHEMA,
  type ListProjectsQuery,
  isDealId,
  searchProjects,
  toProjectBody,
} from "./schemas.js";

/** Problem code of the 502 answer when the HUB fails. */
export const HUB_UNAVAILABLE_CODE = "hub_unavailable";

async function fromHub<T>(log: FastifyBaseLogger, call: () => Promise<T>): Promise<T> {
  try {
    return await call();
  } catch (error) {
    if (error instanceof HubError) {
      // The reason is credential-free by construction; no HUB body is ever included.
      log.warn({ hub: { failure: error.failure, reason: error.reason } }, "HUB lookup failed");
      throw new ProblemError(502, HUB_UNAVAILABLE_CODE, {
        detail: "The HUB did not answer or returned an error. Try again in a moment.",
      });
    }
    throw error;
  }
}

export default async function projectRoutes(app: FastifyInstance): Promise<void> {
  const hub: HubClient = resolveHubClient(app);

  app.get<{ Querystring: ListProjectsQuery }>(
    "/projects",
    {
      config: { roles: ["capture", "bim", "admin"] },
      schema: { querystring: LIST_PROJECTS_QUERY_SCHEMA },
    },
    async (request) => {
      const { q, limit = LIST_PROJECTS_DEFAULT_LIMIT } = request.query;
      const projects = await fromHub(request.log, () => hub.listProjects());
      return { projects: searchProjects(projects, q, limit).map(toProjectBody) };
    },
  );

  app.get<{ Params: { dealId: string } }>(
    "/projects/:dealId",
    { config: { roles: ["capture", "bim", "admin"] } },
    async (request) => {
      const { dealId } = request.params;
      // A value outside the DealId schema cannot name a HUB deal: answer 404, as documented.
      const project = isDealId(dealId)
        ? await fromHub(request.log, () => hub.getProject(dealId))
        : null;
      if (project === null) {
        throw new ProblemError(404, "project_not_found", {
          detail: "No HUB deal with a confirmed address has this dealId.",
        });
      }
      return toProjectBody(project);
    },
  );
}
