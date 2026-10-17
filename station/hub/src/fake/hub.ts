// Fake HUB for tests and the end-to-end run: answers the deal list, document upload and document
// search routes of mapping.ts the way the station expects the HUB to, and records every request.
//
// - Enforces the HUB's 50 MB upload cap (413, nothing stored) and the dealId rule (1 to 64
//   characters; known project record ids are rejected with 400, unknown deals answer 404).
// - Requires the service credential in the mapped auth header (401 otherwise). Recorded requests
//   never hold the credential or any header.
// - Failures can be injected per operation: N answers with a status (503, 429, 400, ...), either
//   before anything is stored or after the upload was stored (a lost response).
//
// Use it in process through `fakeHub.fetch` (pass it to LiveHubApi) or over HTTP with
// startFakeHubServer (server.ts).

import { createHash, randomUUID } from "node:crypto";
import { HUB_PUBLISH_MAPPING, isDealId, type HubPublishMapping } from "../mapping.js";

/** The HUB's upload cap. 50 MB read as 50,000,000 bytes: the stricter of MB and MiB. */
export const FAKE_HUB_MAX_UPLOAD_BYTES = 50_000_000;
/** Allowance for multipart framing on top of the file bytes. */
export const MULTIPART_OVERHEAD_BYTES = 64 * 1024;

export const FAKE_DEAL_ID = "fixture-deal-0001";
export const FAKE_DEAL_ADDRESS = "100 Example Street, Testville, NY 00000";
/** A project record id of the fake (not a sales dealId): uploads to it answer 400. */
export const FAKE_PROJECT_RECORD_ID = "project-record-0001";
export const FAKE_CREDENTIAL = "fake-hub-credential-for-tests";

/** A deal as the HUB's sales deals list returns it (field names of mapping.ts). */
export interface FakeDeal {
  readonly dealId: string | number;
  readonly name?: string;
  readonly address?: string;
  readonly addressConfirmed?: boolean;
  readonly updatedAt?: string;
}

export const DEFAULT_FAKE_DEALS: readonly FakeDeal[] = Object.freeze([
  {
    dealId: FAKE_DEAL_ID,
    name: "Fixture project",
    address: FAKE_DEAL_ADDRESS,
    addressConfirmed: true,
    updatedAt: "2026-10-01T12:00:00Z",
  },
  {
    dealId: "fixture-deal-0003",
    name: "Fixture deal without a confirmed address",
    address: "300 Pending Road, Testville, NY 00000",
    addressConfirmed: false,
    updatedAt: "2026-10-10T08:00:00Z",
  },
]);

export type FakeOperation = "list_deals" | "upload" | "search";

export interface FailureRule {
  readonly operation: FakeOperation;
  readonly status: number;
  /** How many matching requests fail. */
  readonly times: number;
  /** Store the upload first, then answer with the failure (the response is "lost"). */
  readonly afterStore?: boolean;
  readonly retryAfterSeconds?: number;
  readonly message?: string;
}

export interface RecordedRequest {
  readonly seq: number;
  readonly method: string;
  /** Path without the query string. */
  readonly path: string;
  readonly operation: FakeOperation | "unknown";
  readonly dealId?: string;
  readonly status: number;
  /** Whether the request carried the right credential (never the credential itself). */
  readonly authorized: boolean;
  /** Upload: target folder and file names; search: the name searched for. */
  readonly folder?: string;
  readonly fileNames?: readonly string[];
  readonly search?: string;
  readonly bytes?: number;
  /** Whether the upload stored files. */
  readonly stored?: boolean;
}

export interface StoredDocument {
  readonly documentId: string;
  readonly dealId: string;
  readonly folder: string;
  readonly name: string;
  readonly bytes: number;
  readonly sha256: string;
  readonly contentType: string;
  /** The stored bytes (tests read the uploaded report back). */
  readonly data: Uint8Array;
}

export interface FakeHubOptions {
  readonly credential?: string;
  readonly deals?: readonly FakeDeal[];
  readonly projectRecordIds?: readonly string[];
  readonly maxUploadBytes?: number;
  readonly mapping?: HubPublishMapping;
}

interface Route {
  readonly operation: FakeOperation;
  readonly method: string;
  readonly pattern: RegExp;
}

function routePattern(template: string): RegExp {
  const parts = template
    .split("{dealId}")
    .map((part) => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  return new RegExp(`^${parts.join("([^/]*)")}$`);
}

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

export class FakeHub {
  readonly credential: string;
  readonly maxUploadBytes: number;
  readonly requests: RecordedRequest[] = [];
  readonly documents: StoredDocument[] = [];
  readonly #deals: FakeDeal[];
  readonly #projectRecordIds: Set<string>;
  readonly #mapping: HubPublishMapping;
  readonly #routes: Route[];
  #failures: Array<FailureRule & { left: number }> = [];

  constructor(options: FakeHubOptions = {}) {
    this.credential = options.credential ?? FAKE_CREDENTIAL;
    this.maxUploadBytes = options.maxUploadBytes ?? FAKE_HUB_MAX_UPLOAD_BYTES;
    this.#deals = [...(options.deals ?? DEFAULT_FAKE_DEALS)];
    this.#projectRecordIds = new Set(options.projectRecordIds ?? [FAKE_PROJECT_RECORD_ID]);
    this.#mapping = options.mapping ?? HUB_PUBLISH_MAPPING;
    this.#routes = [
      {
        operation: "list_deals",
        method: "GET",
        pattern: routePattern(this.#mapping.listDeals.path),
      },
      { operation: "upload", method: "POST", pattern: routePattern(this.#mapping.upload.path) },
      {
        operation: "search",
        method: "GET",
        pattern: routePattern(this.#mapping.searchDocuments.path),
      },
    ];
  }

  /** fetch over this fake (in process, no network). */
  readonly fetch: typeof fetch = async (input, init) => this.handle(new Request(input, init));

  /** Makes the next `times` requests of an operation fail with `status`. */
  failNext(rule: FailureRule): void {
    this.#failures.push({ ...rule, left: rule.times });
  }

  clearFailures(): void {
    this.#failures = [];
  }

  addDeal(deal: FakeDeal): void {
    this.#deals.push(deal);
  }

  /** Uploads that stored files (whatever the answer was). */
  storedUploads(): RecordedRequest[] {
    return this.requests.filter((request) => request.operation === "upload" && request.stored);
  }

  /** Recorded requests of one operation. */
  requestsOf(operation: FakeOperation): RecordedRequest[] {
    return this.requests.filter((request) => request.operation === operation);
  }

  #record(entry: Omit<RecordedRequest, "seq">): void {
    this.requests.push({ seq: this.requests.length + 1, ...entry });
  }

  #takeFailure(operation: FakeOperation): (FailureRule & { left: number }) | undefined {
    const rule = this.#failures.find((item) => item.operation === operation && item.left > 0);
    if (rule !== undefined) {
      rule.left -= 1;
    }
    return rule;
  }

  #failureResponse(rule: FailureRule): Response {
    return json(
      rule.status,
      { message: rule.message ?? `Injected HUB failure ${rule.status}` },
      rule.retryAfterSeconds === undefined ? {} : { "retry-after": String(rule.retryAfterSeconds) },
    );
  }

  #authorized(request: Request): boolean {
    const auth = this.#mapping.auth;
    const expected = auth.scheme === null ? this.credential : `${auth.scheme} ${this.credential}`;
    return request.headers.get(auth.header) === expected;
  }

  /** Answers a request whose body was too large to read (HTTP server only). */
  tooLarge(method: string, path: string): Response {
    const route = this.#routes.find((item) => item.method === method && item.pattern.test(path));
    this.#record({
      method,
      path,
      operation: route?.operation ?? "unknown",
      status: 413,
      authorized: false,
      stored: false,
    });
    return json(413, { message: "Upload is larger than the 50 MB limit" });
  }

  async handle(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const method = request.method.toUpperCase();
    const path = url.pathname;
    let operation: FakeOperation | "unknown" = "unknown";
    let rawDealId: string | undefined;
    for (const route of this.#routes) {
      const match = route.pattern.exec(path);
      if (match !== null && route.method === method) {
        operation = route.operation;
        rawDealId = match[1];
        break;
      }
    }
    const authorized = this.#authorized(request);
    const base = { method, path, operation, authorized } as const;

    if (operation === "unknown") {
      this.#record({ ...base, status: 404 });
      return json(404, { message: "Not found" });
    }
    if (!authorized) {
      this.#record({ ...base, status: 401 });
      return json(401, { message: "Unauthorized" });
    }

    if (operation === "list_deals") {
      const rule = this.#takeFailure("list_deals");
      if (rule !== undefined) {
        this.#record({ ...base, status: rule.status });
        return this.#failureResponse(rule);
      }
      this.#record({ ...base, status: 200 });
      return json(200, this.#deals);
    }

    let dealId: string;
    try {
      dealId = decodeURIComponent(rawDealId ?? "");
    } catch {
      this.#record({ ...base, status: 400 });
      return json(400, { message: "dealId is not valid" });
    }
    if (!isDealId(dealId)) {
      this.#record({ ...base, status: 400 });
      return json(400, { message: "dealId must be 1 to 64 characters" });
    }
    if (this.#projectRecordIds.has(dealId)) {
      this.#record({ ...base, dealId, status: 400 });
      return json(400, { message: "This is a project record id, not a sales dealId" });
    }
    if (!this.#deals.some((deal) => String(deal.dealId) === dealId)) {
      this.#record({ ...base, dealId, status: 404 });
      return json(404, { message: "No deal with this dealId" });
    }

    if (operation === "search") {
      const search = url.searchParams.get(this.#mapping.searchDocuments.queryParam) ?? "";
      const rule = this.#takeFailure("search");
      if (rule !== undefined) {
        this.#record({ ...base, dealId, search, status: rule.status });
        return this.#failureResponse(rule);
      }
      const needle = search.toLowerCase();
      const found = this.documents
        .filter((doc) => doc.dealId === dealId && doc.name.toLowerCase().includes(needle))
        .map((doc) => ({
          id: doc.documentId,
          name: doc.name,
          folder: doc.folder,
          size: doc.bytes,
        }));
      this.#record({ ...base, dealId, search, status: 200 });
      return json(200, found);
    }

    return this.#upload(request, base, dealId);
  }

  async #upload(
    request: Request,
    base: Pick<RecordedRequest, "method" | "path" | "operation" | "authorized">,
    dealId: string,
  ): Promise<Response> {
    const body = new Uint8Array(await request.arrayBuffer());
    if (body.byteLength > this.maxUploadBytes + MULTIPART_OVERHEAD_BYTES) {
      this.#record({ ...base, dealId, status: 413, bytes: body.byteLength, stored: false });
      return json(413, { message: "Upload is larger than the 50 MB limit" });
    }
    const contentType = request.headers.get("content-type") ?? "";
    let form: FormData;
    try {
      form = await new Response(body, { headers: { "content-type": contentType } }).formData();
    } catch {
      this.#record({ ...base, dealId, status: 400, bytes: body.byteLength, stored: false });
      return json(400, { message: "Body is not multipart/form-data" });
    }
    const folderValue = form.get(this.#mapping.upload.folderField);
    const folder = typeof folderValue === "string" ? folderValue : undefined;
    const files = form
      .getAll(this.#mapping.upload.fileField)
      .filter(
        (value): value is Exclude<ReturnType<FormData["get"]>, string | null> =>
          typeof value !== "string",
      );
    const fileNames = files.map((file) => file.name);
    const recorded = {
      ...base,
      dealId,
      bytes: body.byteLength,
      fileNames,
      ...(folder ? { folder } : {}),
    };
    if (files.length === 0) {
      this.#record({ ...recorded, status: 400, stored: false });
      return json(400, {
        message: `No file in the multipart field ${this.#mapping.upload.fileField}`,
      });
    }
    if (files.some((file) => file.size > this.maxUploadBytes)) {
      this.#record({ ...recorded, status: 413, stored: false });
      return json(413, { message: "File is larger than the 50 MB limit" });
    }

    const rule = this.#takeFailure("upload");
    if (rule !== undefined && rule.afterStore !== true) {
      this.#record({ ...recorded, status: rule.status, stored: false });
      return this.#failureResponse(rule);
    }

    const stored: StoredDocument[] = [];
    for (const file of files) {
      const data = new Uint8Array(await file.arrayBuffer());
      const doc: StoredDocument = {
        documentId: randomUUID(),
        dealId,
        folder: folder ?? "",
        name: file.name,
        bytes: data.byteLength,
        sha256: createHash("sha256").update(data).digest("hex"),
        contentType: file.type,
        data,
      };
      this.documents.push(doc);
      stored.push(doc);
    }
    if (rule !== undefined) {
      this.#record({ ...recorded, status: rule.status, stored: true });
      return this.#failureResponse(rule);
    }
    this.#record({ ...recorded, status: 201, stored: true });
    return json(
      201,
      stored.map((doc) => ({ id: doc.documentId, name: doc.name, folder: doc.folder })),
    );
  }
}
