// HubPublisher: puts a verdict into the HUB project's Files tab.
//
// 1. Opens the publication row (one per package revision). Already published for this verdict:
//    nothing to do.
// 2. Plans the files (plan.ts): uploads into Capture/... folders, station links for the rest.
//    Reads the report's sources (capture models, field controls, photos) and renders the
//    spatial report (report/), hands it to onReportRendered (the worker stores it) and records
//    the links.
// 3. Up to maxAttempts attempts, with exponential backoff between them (429, 5xx, network
//    errors and a failed verification are retried; any other HUB answer fails at once):
//    - for every upload not yet recorded: look it up by document search first (an earlier
//      attempt may have stored it and lost the answer), else read it, re-check its SHA-256 and
//      upload it; record it right after the upload succeeds, so a retry never sends it again;
//    - verify through the document search that every uploaded file is present.
// 4. Published, or publish_failed with the error { status, message } of the last attempt.
//
// The dealId is the package's HUB sales dealId (packages.deal_id), never a project record id.

import { createHash } from "node:crypto";
import type { CaptureRecord, Verdict } from "@chapter/capture-contract";
import { HubError, publicationErrorOf, type PublicationError } from "./errors.js";
import {
  MAX_HUB_UPLOAD_BYTES,
  REPORT_CONTENT_TYPE,
  planPublication,
  type PlannedUpload,
  type PublicationPlan,
  type PublishPackage,
} from "./plan.js";
import { renderSpatialReport, type RenderedReport, type ReportFile } from "./report.js";
import { DEFAULT_REPORT_TIME_ZONE } from "./report/format.js";
import { loadReportSources } from "./report/sources.js";
import { fileKey, type PublicationStore, type PublishedFile } from "./store.js";
import type { HubApi, HubLogger } from "./types.js";

export const DEFAULT_MAX_ATTEMPTS = 5;
/** Role of the spatial report's entry in hub_publications.files (older rows: verdict_report). */
export const SPATIAL_REPORT_ROLE = "spatial_report";
export const DEFAULT_BASE_DELAY_MS = 2_000;
export const DEFAULT_MAX_DELAY_MS = 30_000;

export interface PublishRequest {
  readonly pkg: PublishPackage;
  /** The stored verdict (contract document). */
  readonly verdict: Verdict;
  readonly captureRecord?: CaptureRecord;
  /** Bytes of the sealed manifest.json. */
  readManifest(): Promise<Uint8Array>;
  /** Bytes of one package file by its path. */
  readFile(path: string): Promise<Uint8Array>;
}

export interface PublishResult {
  readonly status: "published" | "publish_failed";
  /** Attempts made by this call (0 when it was already published). */
  readonly attempts: number;
  readonly alreadyPublished: boolean;
  readonly uploaded: number;
  readonly linked: number;
  readonly error?: PublicationError;
}

export interface HubPublisherOptions {
  readonly hub: HubApi;
  readonly store: PublicationStore;
  /** Web review screen base URL for station links (REVIEW_BASE_URL). */
  readonly reviewBaseUrl: string;
  readonly maxAttempts?: number;
  readonly baseDelayMs?: number;
  readonly maxDelayMs?: number;
  /** Randomize delays (0.5x to 1x). Defaults to true. */
  readonly jitter?: boolean;
  readonly maxUploadBytes?: number;
  readonly sleep?: (ms: number) => Promise<void>;
  readonly now?: () => Date;
  readonly logger?: HubLogger;
  /** IANA zone of the spatial report's printed dates (REPORT_TIME_ZONE). */
  readonly reportTimeZone?: string;
  /**
   * Called with the rendered spatial report before anything is uploaded (the worker stores it
   * for the web review). A throw leaves publish() as it is, like a store failure.
   */
  readonly onReportRendered?: (report: RenderedReport, verdict: Verdict) => Promise<void>;
  /** Budget of the report's reduced photos (tests lower it). */
  readonly reportPhotoBudgetBytes?: number;
}

interface UploadItem extends PlannedUpload {
  readonly verdictId?: string;
}

/** Where each file of a publication plan is, for the report's package record. */
export function reportFilesOf(plan: PublicationPlan): ReportFile[] {
  return plan.files.map((file) =>
    file.kind === "upload"
      ? {
          path: file.path ?? file.name,
          role: file.role ?? "manifest",
          bytes: file.bytes,
          sha256: file.sha256,
          location: { kind: "hub", folder: file.folder, name: file.name },
        }
      : {
          path: file.path,
          role: file.role,
          bytes: file.bytes,
          sha256: file.sha256,
          location: { kind: "link", url: file.url, reason: file.reason },
        },
  );
}

function sha256Hex(data: Uint8Array): string {
  return createHash("sha256").update(data).digest("hex");
}

/**
 * HubError decides itself; any other error is retried only when it says so (a storage read
 * error carries `retryable: true`). Everything else (bugs, rule failures) fails at once.
 */
export function isRetryable(error: unknown): boolean {
  if (error instanceof HubError) {
    return error.retryable;
  }
  return (
    typeof error === "object" &&
    error !== null &&
    (error as { retryable?: unknown }).retryable === true
  );
}

/** Wraps a store failure so the attempt loop rethrows it instead of recording it. */
class StoreFailure extends Error {
  constructor(override readonly cause: unknown) {
    super("publication store failed");
    this.name = "StoreFailure";
  }
}

async function storeCall<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    throw new StoreFailure(error);
  }
}

const defaultSleep = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms));

export class HubPublisher {
  readonly #hub: HubApi;
  readonly #store: PublicationStore;
  readonly #reviewBaseUrl: string;
  readonly #maxAttempts: number;
  readonly #baseDelayMs: number;
  readonly #maxDelayMs: number;
  readonly #jitter: boolean;
  readonly #maxUploadBytes: number;
  readonly #sleep: (ms: number) => Promise<void>;
  readonly #now: () => Date;
  readonly #logger: HubLogger | undefined;
  readonly #reportTimeZone: string;
  readonly #onReportRendered: HubPublisherOptions["onReportRendered"];
  readonly #photoBudgetBytes: number | undefined;

  constructor(options: HubPublisherOptions) {
    this.#hub = options.hub;
    this.#store = options.store;
    this.#reviewBaseUrl = options.reviewBaseUrl;
    this.#maxAttempts = options.maxAttempts ?? DEFAULT_MAX_ATTEMPTS;
    this.#baseDelayMs = options.baseDelayMs ?? DEFAULT_BASE_DELAY_MS;
    this.#maxDelayMs = options.maxDelayMs ?? DEFAULT_MAX_DELAY_MS;
    this.#jitter = options.jitter ?? true;
    this.#maxUploadBytes = options.maxUploadBytes ?? MAX_HUB_UPLOAD_BYTES;
    this.#sleep = options.sleep ?? defaultSleep;
    this.#now = options.now ?? (() => new Date());
    this.#logger = options.logger;
    this.#reportTimeZone = options.reportTimeZone ?? DEFAULT_REPORT_TIME_ZONE;
    this.#onReportRendered = options.onReportRendered;
    this.#photoBudgetBytes = options.reportPhotoBudgetBytes;
    if (!Number.isSafeInteger(this.#maxAttempts) || this.#maxAttempts < 1) {
      throw new RangeError("maxAttempts must be a positive integer");
    }
  }

  /** Delay before attempt n+1 after attempt n failed. */
  delayAfter(attempt: number, retryAfterMs?: number): number {
    const exponential = Math.min(this.#maxDelayMs, this.#baseDelayMs * 2 ** (attempt - 1));
    const delay = this.#jitter ? exponential * (0.5 + Math.random() * 0.5) : exponential;
    const wanted = retryAfterMs === undefined ? delay : Math.max(delay, retryAfterMs);
    return Math.round(Math.min(wanted, this.#maxDelayMs));
  }

  async publish(request: PublishRequest): Promise<PublishResult> {
    const { pkg, verdict } = request;
    if (verdict.packageId !== pkg.packageId) {
      throw new Error("verdict and package do not match");
    }
    const state = await this.#store.begin(pkg.packageId, verdict.verdictId);
    if (state.status === "published") {
      return {
        status: "published",
        attempts: 0,
        alreadyPublished: true,
        uploaded: state.files.filter((file) => file.kind === "uploaded").length,
        linked: state.files.filter((file) => file.kind === "linked").length,
      };
    }
    const recorded = new Map<string, PublishedFile>(
      state.files.map((file) => [fileKey(file), file]),
    );
    // A store (database) failure is not a HUB failure: it leaves publish() as it is, so the
    // caller's own retry handles it, instead of being recorded as publish_failed.
    const record = async (file: PublishedFile) => {
      await storeCall(() => this.#store.recordFile(pkg.packageId, file));
      recorded.set(fileKey(file), file);
    };

    let uploads: UploadItem[];
    let report: Buffer;
    let rendered: RenderedReport;
    const links: PublishedFile[] = [];
    let plan: PublicationPlan;
    try {
      plan = planPublication(pkg, verdict.verdictId, {
        reviewBaseUrl: this.#reviewBaseUrl,
        maxUploadBytes: this.#maxUploadBytes,
      });
    } catch (error) {
      return this.#failAtOnce(pkg.packageId, error);
    }
    // The report's sources are read like any upload: a storage failure leaves publish() (the
    // caller retries it), an integrity failure ends the caller's job.
    const sources = await loadReportSources(
      {
        files: pkg.files,
        ...(request.captureRecord === undefined ? {} : { captureRecord: request.captureRecord }),
        readFile: (path) => request.readFile(path),
      },
      this.#photoBudgetBytes === undefined ? {} : { photoBudgetBytes: this.#photoBudgetBytes },
    );
    try {
      rendered = await renderSpatialReport({
        verdict,
        packageId: pkg.packageId,
        dealId: pkg.dealId,
        ...(request.captureRecord === undefined ? {} : { captureRecord: request.captureRecord }),
        reportLocation: plan.report,
        files: reportFilesOf(plan),
        maxUploadBytes: this.#maxUploadBytes,
        reviewBaseUrl: this.#reviewBaseUrl,
        timeZone: this.#reportTimeZone,
        ...(pkg.sealedAt === undefined ? {} : { sealedAt: pkg.sealedAt }),
        manifestFileCount: pkg.manifestFileCount ?? pkg.files.length,
        ...sources,
      });
      report = rendered.bytes;
      if (report.byteLength > this.#maxUploadBytes) {
        throw new HubError("conflict", "The spatial report is larger than the HUB upload limit");
      }
      uploads = [
        {
          kind: "upload",
          source: "report",
          folder: plan.report.folder,
          name: plan.report.name,
          contentType: REPORT_CONTENT_TYPE,
          sha256: rendered.sha256,
          bytes: report.byteLength,
          verdictId: verdict.verdictId,
        },
        ...plan.files.filter((file): file is PlannedUpload => file.kind === "upload"),
      ];
      for (const file of plan.files) {
        if (file.kind !== "link") {
          continue;
        }
        const entry: PublishedFile = {
          kind: "linked",
          name: file.path,
          folder: null,
          path: file.path,
          role: file.role,
          sha256: file.sha256,
          bytes: file.bytes,
          url: file.url,
          reason: file.reason,
          recordedAt: this.#now().toISOString(),
        };
        links.push(entry);
      }
    } catch (error) {
      // Rendering failed: retrying the same input cannot help.
      return this.#failAtOnce(pkg.packageId, error);
    }
    if (this.#onReportRendered !== undefined) {
      await this.#onReportRendered(rendered, verdict);
    }

    for (const entry of links) {
      const existing = recorded.get(fileKey(entry));
      if (
        existing === undefined ||
        existing.url !== entry.url ||
        existing.sha256 !== entry.sha256
      ) {
        await record(entry);
      }
    }
    const linked = links.length;

    for (let attempt = 1; ; attempt += 1) {
      await this.#store.countAttempt(pkg.packageId);
      try {
        await this.#uploadMissing(request, uploads, report, recorded, record);
        await this.#verify(pkg.dealId, uploads, recorded);
        await storeCall(() => this.#store.markPublished(pkg.packageId));
        this.#logger?.info(
          {
            packageId: pkg.packageId,
            verdictId: verdict.verdictId,
            attempt,
            uploads: uploads.length,
            linked,
          },
          "published to the HUB",
        );
        return {
          status: "published",
          attempts: attempt,
          alreadyPublished: false,
          uploaded: uploads.length,
          linked,
        };
      } catch (error) {
        if (error instanceof StoreFailure) {
          throw error.cause;
        }
        const stored = publicationErrorOf(error);
        const retryable = isRetryable(error);
        if (!retryable || attempt >= this.#maxAttempts) {
          await this.#store.markFailed(pkg.packageId, stored);
          this.#logger?.warn(
            { packageId: pkg.packageId, attempt, error: stored, retryable },
            "HUB publication failed",
          );
          return {
            status: "publish_failed",
            attempts: attempt,
            alreadyPublished: false,
            uploaded: [...recorded.values()].filter((file) => file.kind === "uploaded").length,
            linked,
            error: stored,
          };
        }
        await this.#store.attemptFailed(pkg.packageId, stored);
        const delay = this.delayAfter(
          attempt,
          error instanceof HubError ? error.retryAfterMs : undefined,
        );
        this.#logger?.warn(
          { packageId: pkg.packageId, attempt, error: stored, retryInMs: delay },
          "HUB publication attempt failed; retrying",
        );
        await this.#sleep(delay);
      }
    }
  }

  /** Planning or rendering failed: publish_failed at once, after one counted attempt. */
  async #failAtOnce(packageId: string, error: unknown): Promise<PublishResult> {
    const stored = publicationErrorOf(error);
    await this.#store.countAttempt(packageId);
    await this.#store.markFailed(packageId, stored);
    return {
      status: "publish_failed",
      attempts: 1,
      alreadyPublished: false,
      uploaded: 0,
      linked: 0,
      error: stored,
    };
  }

  async #uploadMissing(
    request: PublishRequest,
    uploads: readonly UploadItem[],
    report: Buffer,
    recorded: Map<string, PublishedFile>,
    record: (file: PublishedFile) => Promise<void>,
  ): Promise<void> {
    const { pkg } = request;
    for (const item of uploads) {
      const key = fileKey({ kind: "uploaded", folder: item.folder, name: item.name });
      const existing = recorded.get(key);
      if (existing !== undefined) {
        if (existing.sha256 !== item.sha256 && item.source !== "report") {
          throw new HubError(
            "conflict",
            `A different file named ${item.name} is already published in ${item.folder}`,
          );
        }
        continue;
      }
      const base = {
        kind: "uploaded" as const,
        name: item.name,
        folder: item.folder,
        path: item.path ?? null,
        role: item.source === "report" ? SPATIAL_REPORT_ROLE : (item.role ?? "manifest"),
        sha256: item.sha256,
        bytes: item.bytes,
        ...(item.verdictId === undefined ? {} : { verdictId: item.verdictId }),
      };

      // An earlier attempt may have stored the file and lost the answer: never send it twice.
      const found = (await this.#hub.searchDocuments(pkg.dealId, item.name)).find(
        (doc) => doc.name === item.name && doc.folder === item.folder,
      );
      if (found !== undefined) {
        await record({
          ...base,
          ...(found.documentId === undefined ? {} : { documentId: found.documentId }),
          foundBySearch: true,
          recordedAt: this.#now().toISOString(),
        });
        continue;
      }

      const data = await this.#read(request, item, report);
      const result = await this.#hub.uploadDocument({
        dealId: pkg.dealId,
        folder: item.folder,
        name: item.name,
        contentType: item.contentType,
        data,
      });
      await record({
        ...base,
        ...(result.documentId === undefined ? {} : { documentId: result.documentId }),
        recordedAt: this.#now().toISOString(),
      });
    }
  }

  async #read(request: PublishRequest, item: UploadItem, report: Buffer): Promise<Uint8Array> {
    let data: Uint8Array;
    switch (item.source) {
      case "report":
        return report;
      case "manifest":
        data = await request.readManifest();
        break;
      case "package":
        if (item.path === undefined) {
          throw new HubError("integrity", `Upload ${item.name} has no package path`);
        }
        data = await request.readFile(item.path);
        break;
    }
    if (data.byteLength !== item.bytes || sha256Hex(data) !== item.sha256) {
      throw new HubError(
        "integrity",
        `${item.path ?? item.name} does not match its recorded SHA-256 and size; not uploaded`,
      );
    }
    return data;
  }

  async #verify(
    dealId: string,
    uploads: readonly UploadItem[],
    recorded: Map<string, PublishedFile>,
  ): Promise<void> {
    for (const item of uploads) {
      const documents = await this.#hub.searchDocuments(dealId, item.name);
      const matches = documents.filter(
        (doc) => doc.name === item.name && doc.folder === item.folder,
      );
      const entry = recorded.get(
        fileKey({ kind: "uploaded", folder: item.folder, name: item.name }),
      );
      const withIds = matches.filter((doc) => doc.documentId !== undefined);
      const present =
        entry?.documentId !== undefined && withIds.length > 0
          ? withIds.some((doc) => doc.documentId === entry.documentId)
          : matches.length > 0;
      if (!present) {
        throw new HubError(
          "verification",
          `Uploaded file ${item.folder}/${item.name} is not found by the HUB document search`,
        );
      }
      if (matches.length > 1) {
        this.#logger?.warn(
          { dealId, folder: item.folder, name: item.name, copies: matches.length },
          "the HUB holds more than one file with this name in the folder",
        );
      }
    }
  }
}
