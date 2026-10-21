// HubClient over the HUB REST API (HUB_MODE=live), authenticated with the station's HUB service
// credential (Key Vault secretRef HUB_SERVICE_CREDENTIAL).
//
// Safety rules:
// - The credential lives in a private field and is only ever written into the request header.
//   It is never logged, never put in an error and never sent to another host: redirects are
//   refused instead of followed.
// - Every failure (network, timeout, non-2xx, oversized or non-JSON body, unexpected shape) is
//   a HubError with a fixed, credential-free reason; no HUB response body is logged.
// - Paths and field names come from mapping.ts (not yet confirmed with the HUB team).

import { HUB_API_MAPPING, type HubApiMapping, readPath } from "./mapping.js";
import { normalizeDeals, type RawHubDeal } from "./normalize.js";
import { HubError, type HubClient, type HubLogger, type HubProject } from "./types.js";

export const HUB_REQUEST_TIMEOUT_MS = 10_000;
export const HUB_MAX_RESPONSE_BYTES = 10 * 1024 * 1024;

export interface LiveHubClientOptions {
  /** HUB REST API base URL (HUB_BASE_URL). */
  readonly baseUrl: string;
  /** HUB service credential (HUB_SERVICE_CREDENTIAL). Secret. */
  readonly credential: string;
  readonly mapping?: HubApiMapping;
  /** fetch implementation, for tests. Defaults to the global fetch. */
  readonly fetch?: typeof fetch;
  readonly timeoutMs?: number;
  readonly maxResponseBytes?: number;
  readonly logger?: HubLogger;
}

const HEADER_NAME = /^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/;
// Visible ASCII only: no spaces, control characters or line breaks in the credential.
const CREDENTIAL = /^[\x21-\x7e]+$/;

function joinUrl(baseUrl: string, path: string): URL {
  const base = baseUrl.endsWith("/") ? baseUrl : `${baseUrl}/`;
  const url = new URL(path.replace(/^\/+/, ""), base);
  if (url.origin !== new URL(base).origin) {
    throw new Error("HUB list path must stay on the HUB base URL's host");
  }
  return url;
}

export class LiveHubClient implements HubClient {
  readonly #credential: string;
  readonly #listUrl: URL;
  readonly #mapping: HubApiMapping;
  readonly #fetch: typeof fetch;
  readonly #timeoutMs: number;
  readonly #maxResponseBytes: number;
  readonly #logger: HubLogger | undefined;

  constructor(options: LiveHubClientOptions) {
    const mapping = options.mapping ?? HUB_API_MAPPING;
    if (!CREDENTIAL.test(options.credential)) {
      // Fixed message: the credential itself must never appear in an error.
      throw new Error("HUB service credential must be non-empty visible ASCII without spaces");
    }
    if (!HEADER_NAME.test(mapping.auth.header)) {
      throw new Error("HUB auth header name in the mapping is not a valid header name");
    }
    const base = new URL(options.baseUrl);
    if (base.protocol !== "https:" && base.protocol !== "http:") {
      throw new Error("HUB base URL must be http(s)");
    }
    if (base.username !== "" || base.password !== "" || base.search !== "" || base.hash !== "") {
      throw new Error("HUB base URL must not carry credentials, a query or a fragment");
    }
    this.#credential = options.credential;
    this.#listUrl = joinUrl(options.baseUrl, mapping.listDeals.path);
    this.#mapping = mapping;
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#timeoutMs = options.timeoutMs ?? HUB_REQUEST_TIMEOUT_MS;
    this.#maxResponseBytes = options.maxResponseBytes ?? HUB_MAX_RESPONSE_BYTES;
    this.#logger = options.logger;
  }

  async listProjects(): Promise<readonly HubProject[]> {
    const body = await this.#getJson(this.#listUrl);
    const items =
      this.#mapping.listDeals.itemsPath === null
        ? body
        : readPath(body, this.#mapping.listDeals.itemsPath);
    if (!Array.isArray(items)) {
      throw new HubError("unexpected_shape", "HUB deals response does not contain a deals array");
    }
    const fields = this.#mapping.fields;
    const raws: RawHubDeal[] = items.map((item: unknown) => ({
      dealId: readPath(item, fields.dealId),
      projectName: readPath(item, fields.projectName),
      address: readPath(item, fields.address),
      addressConfirmed: readPath(item, fields.addressConfirmed),
      updatedAt: readPath(item, fields.updatedAt),
      projectManagerName: readPath(item, this.#mapping.projectManager.name),
      projectManagerPhone: readPath(item, this.#mapping.projectManager.phone),
    }));
    const { projects, skipped, duplicates } = normalizeDeals(raws);
    if (Object.keys(skipped).length > 0 || duplicates > 0) {
      // Counts only: no deal data, no addresses.
      this.#logger?.warn(
        { hub: { deals: items.length, projects: projects.length, skipped, duplicates } },
        "some HUB deals are not available for capture",
      );
    }
    return projects;
  }

  async getProject(dealId: string): Promise<HubProject | null> {
    // The deals list is the only HUB read whose shape we rely on; look the deal up in it.
    const projects = await this.listProjects();
    return projects.find((project) => project.dealId === dealId) ?? null;
  }

  async #getJson(url: URL): Promise<unknown> {
    const auth = this.#mapping.auth;
    const headers = new Headers({ accept: "application/json" });
    let response: Response;
    try {
      headers.set(
        auth.header,
        auth.scheme === null ? this.#credential : `${auth.scheme} ${this.#credential}`,
      );
      response = await this.#fetch(url, {
        method: "GET",
        headers,
        redirect: "manual",
        signal: AbortSignal.timeout(this.#timeoutMs),
      });
    } catch (error) {
      // Not chained as a cause: some errors repeat header values.
      if (error instanceof Error && error.name === "TimeoutError") {
        throw new HubError("timeout", `HUB did not answer within ${this.#timeoutMs} ms`);
      }
      throw new HubError("network", "HUB request failed before an answer (network error)");
    }

    try {
      if (response.type === "opaqueredirect" || (response.status >= 300 && response.status < 400)) {
        throw new HubError(
          "redirect",
          `HUB answered with a redirect (${response.status}), not followed`,
          response.status,
        );
      }
      if (!response.ok) {
        throw new HubError("http_status", `HUB answered ${response.status}`, response.status);
      }
      const declared = Number(response.headers.get("content-length") ?? "0");
      if (Number.isFinite(declared) && declared > this.#maxResponseBytes) {
        throw new HubError("too_large", "HUB response is larger than the station accepts");
      }
      const text = await this.#readText(response);
      try {
        return JSON.parse(text) as unknown;
      } catch {
        throw new HubError("invalid_json", "HUB response is not JSON");
      }
    } finally {
      if (!response.bodyUsed) {
        await response.body?.cancel().catch(() => undefined);
      }
    }
  }

  async #readText(response: Response): Promise<string> {
    if (response.body === null) {
      return "";
    }
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (done) {
          break;
        }
        total += value.byteLength;
        if (total > this.#maxResponseBytes) {
          await reader.cancel().catch(() => undefined);
          throw new HubError("too_large", "HUB response is larger than the station accepts");
        }
        chunks.push(value);
      }
    } catch (error) {
      if (error instanceof HubError) {
        throw error;
      }
      if (error instanceof Error && error.name === "TimeoutError") {
        throw new HubError("timeout", `HUB did not answer within ${this.#timeoutMs} ms`);
      }
      throw new HubError("network", "HUB response was cut off (network error)");
    }
    return new TextDecoder("utf-8").decode(Buffer.concat(chunks));
  }
}
