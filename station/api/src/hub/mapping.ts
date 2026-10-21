// How the live HubClient talks to the HUB REST API: the request path, the auth header and the
// response field names, all in this one module.
//
// NOT CONFIRMED WITH THE HUB TEAM. What we know for sure (HUB MCP connector): deals are listed
// by the HUB's sales deals endpoint, each deal has a sales dealId and an address, and dealId is
// the SALES dealId, not the `id` of the all-projects listing. The path, the field names, the
// response envelope, the "address confirmed" marker, paging and the service-credential header
// below are placeholders until the HUB team confirms them. Until then the live client fails
// closed: an unexpected response shape is a HubError (502), and a deal without an explicit
// `true` confirmation marker is not returned.

export interface HubApiMapping {
  readonly listDeals: {
    /** Path of the sales deals list, relative to HUB_BASE_URL. */
    readonly path: string;
    /**
     * Dotted path to the deals array in the JSON response, or null when the response body is
     * the array itself.
     */
    readonly itemsPath: string | null;
  };
  /** Dotted field paths inside one deal object. */
  readonly fields: {
    readonly dealId: string;
    readonly projectName: string;
    /** Single-line formatted address (a string). */
    readonly address: string;
    /** Boolean marker that the address is confirmed; only `true` counts. */
    readonly addressConfirmed: string;
    /** Last update time (ISO 8601 string or epoch ms), for ordering. */
    readonly updatedAt: string;
  };
  /**
   * Dotted field paths of the deal's project manager (optional in the HUB answer; the project
   * has none when the name is absent). Kept apart from `fields`, which station-hub mirrors.
   */
  readonly projectManager: {
    readonly name: string;
    readonly phone: string;
  };
  /** How the service credential is sent. */
  readonly auth: {
    /** Request header that carries the credential. */
    readonly header: string;
    /** Scheme before the credential ("Bearer" gives "Bearer <credential>"), or null for none. */
    readonly scheme: string | null;
  };
}

/** Current best guess; see the module comment. Override per client for tests or once confirmed. */
export const HUB_API_MAPPING: HubApiMapping = Object.freeze({
  listDeals: Object.freeze({ path: "/api/sales/deals", itemsPath: null }),
  fields: Object.freeze({
    dealId: "dealId",
    projectName: "name",
    address: "address",
    addressConfirmed: "addressConfirmed",
    updatedAt: "updatedAt",
  }),
  projectManager: Object.freeze({ name: "projectManager.name", phone: "projectManager.phone" }),
  auth: Object.freeze({ header: "authorization", scheme: "Bearer" }),
});

const UNSAFE_SEGMENTS = new Set(["__proto__", "prototype", "constructor"]);

/** Reads a dotted path ("a.b.c") from parsed JSON; undefined when any step is missing. */
export function readPath(value: unknown, path: string): unknown {
  let current: unknown = value;
  for (const segment of path.split(".")) {
    if (UNSAFE_SEGMENTS.has(segment)) {
      return undefined;
    }
    if (current === null || typeof current !== "object" || Array.isArray(current)) {
      return undefined;
    }
    if (!Object.prototype.hasOwnProperty.call(current, segment)) {
      return undefined;
    }
    current = (current as Record<string, unknown>)[segment];
  }
  return current;
}
