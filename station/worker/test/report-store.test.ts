// The spatial report store: write-once blobs (same SHA-256 again is success, a different report
// is refused), the spatial_reports upsert and its audit row, and the manifest photo labels.

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { describe, it } from "node:test";
import { RestError } from "@azure/storage-blob";
import type { Verdict } from "@chapter/capture-contract";
import type { RenderedReport } from "@chapter/station-hub";
import { TerminalJobError } from "../src/context.js";
import type { Database, Queryable } from "../src/db.js";
import { photoLabels } from "../src/publish-job.js";
import { reportBlobName, storeSpatialReport } from "../src/report-store.js";
import {
  REPORT_SHA256_METADATA,
  ReportConflictError,
  reportsWriter,
  type ReportsContainer,
} from "../src/storage.js";

const PACKAGE_ID = "6a1f2a8e-0b1c-4d2e-8f3a-4b5c6d7e8f90";
const VERDICT_ID = "7b2e3f40-1c2d-4e3f-9a4b-5c6d7e8f9a01";

function sha(data: Uint8Array): string {
  return createHash("sha256").update(data).digest("hex");
}

/** An in-memory container that refuses to overwrite (If-None-Match: *), as Azure does. */
function memoryContainer(): ReportsContainer & {
  blobs: Map<string, { data: Uint8Array; metadata: Record<string, string>; contentType: string }>;
  uploads: number;
} {
  const blobs = new Map<
    string,
    { data: Uint8Array; metadata: Record<string, string>; contentType: string }
  >();
  const container = {
    containerName: "reports",
    blobs,
    uploads: 0,
    getBlockBlobClient(name: string) {
      return {
        async upload(
          body: Uint8Array,
          _length: number,
          options: Parameters<ReturnType<ReportsContainer["getBlockBlobClient"]>["upload"]>[2],
        ) {
          container.uploads += 1;
          if (options.conditions.ifNoneMatch === "*" && blobs.has(name)) {
            throw new RestError("The specified blob already exists.", {
              code: "BlobAlreadyExists",
              statusCode: 409,
            });
          }
          blobs.set(name, {
            data: body,
            metadata: options.metadata,
            contentType: options.blobHTTPHeaders.blobContentType,
          });
          return {};
        },
        async getProperties() {
          const blob = blobs.get(name);
          if (blob === undefined) {
            throw new RestError("not found", { code: "BlobNotFound", statusCode: 404 });
          }
          return { metadata: blob.metadata, contentLength: blob.data.byteLength };
        },
      };
    },
  };
  return container;
}

function report(text: string): RenderedReport {
  const bytes = Buffer.from(`%PDF-1.7 ${text}`);
  return {
    bytes,
    sha256: sha(bytes),
    pages: 30,
    checksPage: 4,
    recordPage: 29,
    name: `spatial-report-${VERDICT_ID}.pdf`,
    floors: [
      {
        captureId: "33ede7f4-cfcb-4cd6-9af5-7daffee829a9",
        areaKey: "floor-1",
        roomsScanned: 12,
        roomsUnlabeled: 5,
        floorAreaSqFt: 796.2,
      },
    ],
  };
}

const VERDICT = {
  verdictId: VERDICT_ID,
  evaluatedAt: "2026-10-17T15:20:44Z",
} as Verdict;

/** A database that records statements (one transaction = the same recorder). */
function recordingDb(): Database & { statements: Array<{ sql: string; values: unknown[] }> } {
  const statements: Array<{ sql: string; values: unknown[] }> = [];
  const query = async (sql: string, values: unknown[] = []) => {
    statements.push({ sql, values });
    return { rows: [], rowCount: 0 };
  };
  const tx = { query } as unknown as Queryable;
  return {
    statements,
    query,
    transaction: async <T>(fn: (q: Queryable) => Promise<T>) => fn(tx),
    close: async () => {},
  } as unknown as Database & { statements: Array<{ sql: string; values: unknown[] }> };
}

describe("reports writer", () => {
  it("creates the blob once with its SHA-256 and the PDF content type", async () => {
    const container = memoryContainer();
    const writer = reportsWriter(container);
    const data = Buffer.from("%PDF report");
    assert.equal(await writer.write("p/spatial-report-x.pdf", data, sha(data)), "created");
    const blob = container.blobs.get("p/spatial-report-x.pdf");
    assert.equal(blob?.contentType, "application/pdf");
    assert.equal(blob?.metadata[REPORT_SHA256_METADATA], sha(data));
  });

  it("treats the same report again as success (a retried job)", async () => {
    const container = memoryContainer();
    const writer = reportsWriter(container);
    const data = Buffer.from("%PDF report");
    await writer.write("p/r.pdf", data, sha(data));
    assert.equal(await writer.write("p/r.pdf", data, sha(data)), "exists");
    assert.equal(container.blobs.size, 1);
  });

  it("refuses to replace a stored report with different bytes", async () => {
    const container = memoryContainer();
    const writer = reportsWriter(container);
    const first = Buffer.from("%PDF one");
    const second = Buffer.from("%PDF two");
    await writer.write("p/r.pdf", first, sha(first));
    await assert.rejects(writer.write("p/r.pdf", second, sha(second)), ReportConflictError);
    assert.equal(sha(container.blobs.get("p/r.pdf")?.data ?? new Uint8Array()), sha(first));
  });
});

describe("storeSpatialReport", () => {
  it("writes the blob, upserts spatial_reports with checks page and floors, and audits", async () => {
    const container = memoryContainer();
    const db = recordingDb();
    const rendered = report("a");
    await storeSpatialReport(
      { db, reports: reportsWriter(container), secrets: [] },
      PACKAGE_ID,
      rendered,
      VERDICT,
      "job-1",
    );
    const blobName = reportBlobName(PACKAGE_ID, rendered.name);
    assert.equal(blobName, `${PACKAGE_ID}/spatial-report-${VERDICT_ID}.pdf`);
    assert.ok(container.blobs.has(blobName));
    const upsert = db.statements.find((s) => s.sql.includes("INSERT INTO spatial_reports"));
    assert.ok(upsert);
    assert.match(upsert.sql, /ON CONFLICT \(package_id\) DO UPDATE/);
    assert.deepEqual(upsert.values.slice(0, 8), [
      PACKAGE_ID,
      VERDICT_ID,
      rendered.name,
      blobName,
      rendered.sha256,
      rendered.bytes.byteLength,
      30,
      4,
    ]);
    assert.deepEqual(JSON.parse(String(upsert.values[8])), rendered.floors);
    assert.equal(upsert.values[9], VERDICT.evaluatedAt);
    const audit = db.statements.find((s) => s.sql.includes("INSERT INTO audit_log"));
    assert.equal(audit?.values[1], "report.store");
    const details = JSON.parse(String(audit?.values[3])) as Record<string, unknown>;
    assert.equal(details.sha256, rendered.sha256);
    assert.equal(details.blob, "created");
    assert.equal(details.jobId, "job-1");
  });

  it("is idempotent for the same report and ends the job on a conflicting one", async () => {
    const container = memoryContainer();
    const db = recordingDb();
    const ctx = { db, reports: reportsWriter(container), secrets: [] };
    await storeSpatialReport(ctx, PACKAGE_ID, report("a"), VERDICT);
    await storeSpatialReport(ctx, PACKAGE_ID, report("a"), VERDICT);
    assert.equal(
      db.statements.filter((s) => s.sql.includes("INSERT INTO spatial_reports")).length,
      2,
    );
    await assert.rejects(
      storeSpatialReport(ctx, PACKAGE_ID, report("b"), VERDICT),
      (error: unknown) =>
        error instanceof TerminalJobError && error.auditAction === "report.conflict",
    );
  });
});

describe("photo labels from the manifest", () => {
  it("keeps complete labels and drops anything else", () => {
    const labels = {
      room: "Living Room",
      direction: "E",
      subject: "opening",
      takenAt: "2026-10-17T14:10:11Z",
      directionSource: "compass",
    };
    assert.deepEqual(photoLabels(labels), {
      room: "Living Room",
      direction: "E",
      subject: "opening",
      takenAt: "2026-10-17T14:10:11Z",
    });
    assert.equal(photoLabels(undefined), undefined);
    assert.equal(photoLabels({ ...labels, direction: "NE" }), undefined);
    assert.equal(photoLabels({ ...labels, subject: "window" }), undefined);
    assert.equal(photoLabels({ room: "x" }), undefined);
  });
});
