// How the station talks to the HUB REST API for publishing: every path, field name and the auth
// header live in this one module.
//
// NOT CONFIRMED WITH THE HUB TEAM, except the upload path and its multipart field `files`
// (spec F9 / architecture: POST /api/projects/{dealId}/document-media/upload, 50 MB cap).
// Placeholders until the HUB team confirms them:
// - the multipart field that names the target folder (`folder`),
// - the upload response shape (where a HUB document id is, if anywhere),
// - the document search path, its query parameter and response shape,
// - the deal lookup (sales deals list) path, envelope and field names,
// - the service-credential header and scheme.
//
// The deal lookup and the auth header MUST stay identical to the station API's
// station/api/src/hub/mapping.ts (test/mapping-drift.test.ts fails when they drift apart).
//
// The client fails closed: a deal list or search response that does not have the shape below is
// a HubError (unexpected_shape), and a deal without an explicit `true` address confirmation is
// not used. The dealId is always the HUB's SALES dealId, never the id of a project record.

export interface HubPublishMapping {
  readonly upload: {
    /** Upload path relative to HUB_BASE_URL; {dealId} is replaced (URL-encoded). */
    readonly path: string;
    /** Multipart field that carries the file(s). */
    readonly fileField: string;
    /** Multipart text field that names the target folder in the project's Files tab. */
    readonly folderField: string;
    /**
     * Where the uploaded document's id is in the upload response: dotted path to an array of
     * uploaded items (null when the body is the array itself) and the id field in one item.
     * Optional information: when absent the station verifies the upload by document search.
     */
    readonly response: { readonly itemsPath: string | null; readonly documentId: string };
  };
  readonly searchDocuments: {
    /** Search path relative to HUB_BASE_URL; {dealId} is replaced (URL-encoded). */
    readonly path: string;
    /** Query parameter that carries the file name searched for. */
    readonly queryParam: string;
    /** Dotted path to the documents array, or null when the body is the array itself. */
    readonly itemsPath: string | null;
    /** Dotted field paths inside one document. */
    readonly fields: {
      readonly name: string;
      readonly folder: string;
      readonly documentId: string;
    };
  };
  /** Deal lookup: the sales deals list (same as the station API). */
  readonly listDeals: {
    readonly path: string;
    readonly itemsPath: string | null;
  };
  /** Dotted field paths inside one deal object (same as the station API). */
  readonly dealFields: {
    readonly dealId: string;
    readonly projectName: string;
    readonly address: string;
    readonly addressConfirmed: string;
    readonly updatedAt: string;
  };
  /** How the service credential is sent (same as the station API). */
  readonly auth: {
    readonly header: string;
    readonly scheme: string | null;
  };
}

/** Current best guess; see the module comment. */
export const HUB_PUBLISH_MAPPING: HubPublishMapping = Object.freeze({
  upload: Object.freeze({
    path: "/api/projects/{dealId}/document-media/upload",
    fileField: "files",
    folderField: "folder",
    response: Object.freeze({ itemsPath: null, documentId: "id" }),
  }),
  searchDocuments: Object.freeze({
    path: "/api/projects/{dealId}/documents",
    queryParam: "search",
    itemsPath: null,
    fields: Object.freeze({ name: "name", folder: "folder", documentId: "id" }),
  }),
  listDeals: Object.freeze({ path: "/api/sales/deals", itemsPath: null }),
  dealFields: Object.freeze({
    dealId: "dealId",
    projectName: "name",
    address: "address",
    addressConfirmed: "addressConfirmed",
    updatedAt: "updatedAt",
  }),
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

/** Reads the items array of a response: the body itself when itemsPath is null. */
export function readItems(body: unknown, itemsPath: string | null): unknown {
  return itemsPath === null ? body : readPath(body, itemsPath);
}

/** DealId rule (contract/openapi/station.yaml DealId, station_deal_id): 1 to 64 characters. */
export const DEAL_ID_MAX_LENGTH = 64;

export function isDealId(value: unknown): value is string {
  return typeof value === "string" && value.length >= 1 && value.length <= DEAL_ID_MAX_LENGTH;
}

/** A mapping path with {dealId} replaced by the URL-encoded dealId. */
export function dealPath(template: string, dealId: string): string {
  if (!isDealId(dealId)) {
    throw new RangeError("dealId must be 1 to 64 characters");
  }
  return template.split("{dealId}").join(encodeURIComponent(dealId));
}
