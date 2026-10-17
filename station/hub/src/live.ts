// HubApi over the HUB REST API, authenticated with the station's HUB service credential
// (HUB_SERVICE_CREDENTIAL, a Key Vault secretRef in Azure).
//
// Safety rules:
// - The credential lives in a private field and is only ever written into the request header.
//   It is never logged, never put in an error and never sent to another host: every URL is
//   built on HUB_BASE_URL's origin and redirects are refused instead of followed.
// - Every failure is a HubError with a station-written message. Of a HUB error body only a
//   short JSON message excerpt is kept, scrubbed of the credential and token-shaped text.
// - Paths and field names come from mapping.ts (NOT CONFIRMED with the HUB team). Deal list and
//   search responses that do not match it fail closed (unexpected_shape).

import { HubError, scrub } from "./errors.js";
import {
  HUB_PUBLISH_MAPPING,
  dealPath,
  isDealId,
  readItems,
  readPath,
  type HubPublishMapping,
} from "./mapping.js";
import type { HubApi, HubDeal, HubDocument, HubUpload, HubUploadResult } from "./types.js";

export const HUB_REQUEST_TIMEOUT_MS = 15_000;
/** Uploads carry up to 45 MiB; allow for a slow link. */
export const HUB_UPLOAD_TIMEOUT_MS = 180_000;
export const HUB_MAX_RESPONSE_BYTES = 10 * 1024 * 1024;
/** Largest part of an error body read for the HUB's message. */
const ERROR_BODY_BYTES = 64 * 1024;
const HUB_MESSAGE_MAX = 200;
export const ADDRESS_MAX_LENGTH = 300;
export const PROJECT_NAME_MAX_LENGTH = 200;

export interface LiveHubApiOptions {
  /** HUB REST API base URL (HUB_BASE_URL). */
  readonly baseUrl: string;
  /** HUB service credential (HUB_SERVICE_CREDENTIAL). Secret. */
  readonly credential: string;
  readonly mapping?: HubPublishMapping;
  /** fetch implementation (tests, the in-process fake). Defaults to the global fetch. */
  readonly fetch?: typeof fetch;
  readonly timeoutMs?: number;
  readonly uploadTimeoutMs?: number;
  readonly maxResponseBytes?: number;
}

const HEADER_NAME = /^[!#$%&'*+.^_`|~0-9A-Za-z-]+$/;
// Visible ASCII only: no spaces, control characters or line breaks in the credential.
const CREDENTIAL = /^[\x21-\x7e]+$/;

function parseRetryAfter(value: string | null): number | undefined {
  if (value === null) {
    return undefined;
  }
  const trimmed = value.trim();
  if (/^\d+$/.test(trimmed)) {
    return Number(trimmed) * 1000;
  }
  const at = Date.parse(trimmed);
  return Number.isNaN(at) ? undefined : Math.max(0, at - Date.now());
}

function normalizeDealId(value: unknown): string | undefined {
  if (typeof value === "number" && Number.isSafeInteger(value) && value >= 0) {
    return String(value);
  }
  return isDealId(value) ? value : undefined;
}

function normalizeAddress(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }
  // Exactly as shown by the HUB: one non-blank line that fits.
  if (value.trim() === "" || /[\r\n]/.test(value) || value.length > ADDRESS_MAX_LENGTH) {
    return undefined;
  }
  return value;
}

function optionalId(value: unknown): string | undefined {
  if (typeof value === "string" && value.length > 0 && value.length <= 1024) {
    return value;
  }
  if (typeof value === "number" && Number.isSafeInteger(value)) {
    return String(value);
  }
  return undefined;
}

export class LiveHubApi implements HubApi {
  readonly #credential: string;
  readonly #base: URL;
  readonly #mapping: HubPublishMapping;
  readonly #fetch: typeof fetch;
  readonly #timeoutMs: number;
  readonly #uploadTimeoutMs: number;
  readonly #maxResponseBytes: number;

  constructor(options: LiveHubApiOptions) {
    const mapping = options.mapping ?? HUB_PUBLISH_MAPPING;
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
    if (!base.pathname.endsWith("/")) {
      base.pathname = `${base.pathname}/`;
    }
    this.#credential = options.credential;
    this.#base = base;
    this.#mapping = mapping;
    this.#fetch = options.fetch ?? globalThis.fetch;
    this.#timeoutMs = options.timeoutMs ?? HUB_REQUEST_TIMEOUT_MS;
    this.#uploadTimeoutMs = options.uploadTimeoutMs ?? HUB_UPLOAD_TIMEOUT_MS;
    this.#maxResponseBytes = options.maxResponseBytes ?? HUB_MAX_RESPONSE_BYTES;
  }

  /** URL on the HUB base URL's origin; anything else is refused. */
  #url(path: string): URL {
    const url = new URL(path.replace(/^\/+/, ""), this.#base);
    if (url.origin !== this.#base.origin) {
      throw new HubError("request", "HUB path must stay on the HUB base URL's host");
    }
    return url;
  }

  async getDeal(dealId: string): Promise<HubDeal | null> {
    if (!isDealId(dealId)) {
      throw new HubError("request", "dealId must be 1 to 64 characters");
    }
    const body = await this.#json(this.#url(this.#mapping.listDeals.path), {
      method: "GET",
    });
    const items = readItems(body, this.#mapping.listDeals.itemsPath);
    if (!Array.isArray(items)) {
      throw new HubError("unexpected_shape", "HUB deals response does not contain a deals array");
    }
    const fields = this.#mapping.dealFields;
    for (const item of items as unknown[]) {
      if (normalizeDealId(readPath(item, fields.dealId)) !== dealId) {
        continue;
      }
      // First deal with this id wins (as in the station API). Only an explicit true counts.
      if (readPath(item, fields.addressConfirmed) !== true) {
        return null;
      }
      const address = normalizeAddress(readPath(item, fields.address));
      if (address === undefined) {
        return null;
      }
      const name = readPath(item, fields.projectName);
      const projectName =
        typeof name === "string" && name.trim() !== ""
          ? name.trim().slice(0, PROJECT_NAME_MAX_LENGTH)
          : undefined;
      return { dealId, address, ...(projectName === undefined ? {} : { projectName }) };
    }
    return null;
  }

  async uploadDocument(upload: HubUpload): Promise<HubUploadResult> {
    const mapping = this.#mapping.upload;
    let url: URL;
    try {
      url = this.#url(dealPath(mapping.path, upload.dealId));
    } catch (error) {
      if (error instanceof HubError) {
        throw error;
      }
      throw new HubError("request", "dealId must be 1 to 64 characters");
    }
    const form = new FormData();
    form.append(mapping.folderField, upload.folder);
    form.append(
      mapping.fileField,
      new Blob([upload.data], { type: upload.contentType }),
      upload.name,
    );
    const text = await this.#text(url, { method: "POST", body: form }, this.#uploadTimeoutMs);
    // The upload response shape is not confirmed: a document id is optional information and
    // the station verifies every upload by document search instead of trusting this body.
    let body: unknown;
    try {
      body = text.trim() === "" ? undefined : (JSON.parse(text) as unknown);
    } catch {
      return {};
    }
    const items = readItems(body, mapping.response.itemsPath);
    const first: unknown = Array.isArray(items) ? items[0] : items;
    const documentId = optionalId(readPath(first, mapping.response.documentId));
    return documentId === undefined ? {} : { documentId };
  }

  async searchDocuments(dealId: string, name: string): Promise<readonly HubDocument[]> {
    const mapping = this.#mapping.searchDocuments;
    let url: URL;
    try {
      url = this.#url(dealPath(mapping.path, dealId));
    } catch (error) {
      if (error instanceof HubError) {
        throw error;
      }
      throw new HubError("request", "dealId must be 1 to 64 characters");
    }
    url.searchParams.set(mapping.queryParam, name);
    const body = await this.#json(url, { method: "GET" });
    const items = readItems(body, mapping.itemsPath);
    if (!Array.isArray(items)) {
      throw new HubError(
        "unexpected_shape",
        "HUB document search response does not contain a documents array",
      );
    }
    const documents: HubDocument[] = [];
    for (const item of items as unknown[]) {
      const docName = readPath(item, mapping.fields.name);
      if (typeof docName !== "string") {
        throw new HubError("unexpected_shape", "HUB document search item has no name");
      }
      const folder = readPath(item, mapping.fields.folder);
      const documentId = optionalId(readPath(item, mapping.fields.documentId));
      documents.push({
        name: docName,
        ...(typeof folder === "string" ? { folder } : {}),
        ...(documentId === undefined ? {} : { documentId }),
      });
    }
    return documents;
  }

  async #json(url: URL, init: { method: string }): Promise<unknown> {
    const text = await this.#text(url, init, this.#timeoutMs);
    try {
      return JSON.parse(text) as unknown;
    } catch {
      throw new HubError("invalid_json", "HUB response is not JSON");
    }
  }

  async #text(
    url: URL,
    init: { method: string; body?: FormData },
    timeoutMs: number,
  ): Promise<string> {
    const auth = this.#mapping.auth;
    const headers = new Headers({ accept: "application/json" });
    let response: Response;
    try {
      headers.set(
        auth.header,
        auth.scheme === null ? this.#credential : `${auth.scheme} ${this.#credential}`,
      );
      response = await this.#fetch(url, {
        method: init.method,
        headers,
        ...(init.body === undefined ? {} : { body: init.body }),
        redirect: "manual",
        signal: AbortSignal.timeout(timeoutMs),
      });
    } catch (error) {
      // Not chained as a cause: some errors repeat header values.
      if (error instanceof Error && error.name === "TimeoutError") {
        throw new HubError("timeout", `HUB did not answer within ${timeoutMs} ms`);
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
        const hubMessage = await this.#errorMessage(response);
        throw new HubError(
          "http_status",
          `HUB answered ${response.status}`,
          response.status,
          hubMessage,
          parseRetryAfter(response.headers.get("retry-after")),
        );
      }
      const declared = Number(response.headers.get("content-length") ?? "0");
      if (Number.isFinite(declared) && declared > this.#maxResponseBytes) {
        throw new HubError("too_large", "HUB response is larger than the station accepts");
      }
      return await this.#readText(response, this.#maxResponseBytes, true, timeoutMs);
    } finally {
      if (!response.bodyUsed) {
        await response.body?.cancel().catch(() => undefined);
      }
    }
  }

  /** Short, scrubbed HUB error message from a JSON error body; undefined otherwise. */
  async #errorMessage(response: Response): Promise<string | undefined> {
    let text: string;
    try {
      text = await this.#readText(response, ERROR_BODY_BYTES, false, this.#timeoutMs);
    } catch {
      return undefined;
    }
    let body: unknown;
    try {
      body = JSON.parse(text) as unknown;
    } catch {
      return undefined;
    }
    for (const path of ["message", "error", "title", "detail", "error.message"]) {
      const value = readPath(body, path);
      if (typeof value === "string" && value.trim() !== "") {
        return scrub(value, [this.#credential], HUB_MESSAGE_MAX);
      }
    }
    return undefined;
  }

  async #readText(
    response: Response,
    maxBytes: number,
    failWhenLarger: boolean,
    timeoutMs: number,
  ): Promise<string> {
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
        if (total > maxBytes) {
          await reader.cancel().catch(() => undefined);
          if (failWhenLarger) {
            throw new HubError("too_large", "HUB response is larger than the station accepts");
          }
          break;
        }
        chunks.push(value);
      }
    } catch (error) {
      if (error instanceof HubError) {
        throw error;
      }
      if (error instanceof Error && error.name === "TimeoutError") {
        throw new HubError("timeout", `HUB did not answer within ${timeoutMs} ms`);
      }
      throw new HubError("network", "HUB response was cut off (network error)");
    }
    return new TextDecoder("utf-8").decode(Buffer.concat(chunks));
  }
}
