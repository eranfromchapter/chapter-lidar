// Request schemas and response shaping for the project routes (contract/openapi/station.yaml,
// operations listProjects and getProject). Not a route plugin: only index.ts is autoloaded.

import type { HubProject } from "../../hub/types.js";

/** components.schemas.DealId. */
export const DEAL_ID_SCHEMA = {
  type: "string",
  minLength: 1,
  maxLength: 64,
} as const;

export const LIST_PROJECTS_DEFAULT_LIMIT = 25;

/** Query parameters of GET /projects. Unknown parameters are rejected (400). */
export const LIST_PROJECTS_QUERY_SCHEMA = {
  type: "object",
  additionalProperties: false,
  properties: {
    q: { type: "string", minLength: 1, maxLength: 200 },
    limit: { type: "integer", minimum: 1, maximum: 100, default: LIST_PROJECTS_DEFAULT_LIMIT },
  },
} as const;

export interface ListProjectsQuery {
  q?: string;
  limit?: number;
}

/** True when the value can be a HUB dealId (DealId schema). */
export function isDealId(value: string): boolean {
  return value.length >= DEAL_ID_SCHEMA.minLength && value.length <= DEAL_ID_SCHEMA.maxLength;
}

/** HubProject response body: only the contract fields. */
export interface HubProjectBody {
  dealId: string;
  projectName?: string;
  address: { formatted: string };
  projectManager?: { name: string; phone?: string };
}

export function toProjectBody(project: HubProject): HubProjectBody {
  const manager = project.projectManager;
  return {
    dealId: project.dealId,
    ...(project.projectName === undefined ? {} : { projectName: project.projectName }),
    address: { formatted: project.address.formatted },
    ...(manager === undefined
      ? {}
      : {
          projectManager: {
            name: manager.name,
            ...(manager.phone === undefined ? {} : { phone: manager.phone }),
          },
        }),
  };
}

/**
 * Projects whose name or address contains q (case-insensitive), in the given order (most
 * recently updated first), at most limit of them.
 */
export function searchProjects(
  projects: readonly HubProject[],
  q: string | undefined,
  limit: number,
): HubProject[] {
  const needle = q?.toLocaleLowerCase("en-US");
  const matches =
    needle === undefined
      ? projects
      : projects.filter(
          (project) =>
            project.address.formatted.toLocaleLowerCase("en-US").includes(needle) ||
            (project.projectName?.toLocaleLowerCase("en-US").includes(needle) ?? false),
        );
  return matches.slice(0, limit);
}
