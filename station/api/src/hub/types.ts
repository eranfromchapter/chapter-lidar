// HUB lookup types shared by the live client, the fake and the cache.
//
// The key of a project is the HUB's SALES dealId (not the id of the HUB's all-projects
// listing). Only deals with a confirmed property address are projects for capture.

/** A HUB deal with its confirmed property address. */
export interface HubProject {
  /** HUB sales deal id, 1 to 64 characters. */
  readonly dealId: string;
  /** Deal or project name as shown in the HUB, 1 to 200 characters; omitted when unknown. */
  readonly projectName?: string;
  readonly address: {
    /** Single-line address exactly as shown by the HUB, 1 to 300 characters. */
    readonly formatted: string;
  };
  /** Last update time reported by the HUB (epoch ms), used for "most recently updated first". */
  readonly updatedAtMs?: number;
}

/** Read access to HUB projects. Implementations throw HubError when the HUB fails. */
export interface HubClient {
  /** Every deal with a confirmed address, most recently updated first. */
  listProjects(): Promise<readonly HubProject[]>;
  /** The deal with a confirmed address, or null when there is none with this dealId. */
  getProject(dealId: string): Promise<HubProject | null>;
}

/** Why a HUB call failed. Safe to log: never carries credentials, headers or response bodies. */
export type HubFailure =
  | "timeout"
  | "network"
  | "redirect"
  | "http_status"
  | "too_large"
  | "invalid_json"
  | "unexpected_shape"
  | "request";

/** The HUB did not answer or answered with something unusable. */
export class HubError extends Error {
  constructor(
    readonly failure: HubFailure,
    /** Safe, credential-free description for logs. */
    readonly reason: string,
    /** HTTP status of the HUB answer, for failure http_status. */
    readonly status?: number,
  ) {
    super(reason);
    this.name = "HubError";
  }
}

/** The little logging the HUB clients do (a pino/Fastify logger fits). */
export interface HubLogger {
  warn(details: Record<string, unknown>, message: string): void;
}
