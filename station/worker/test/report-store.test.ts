// The spatial report store: write-once blobs (same SHA-256 again is success, a different report
// is refused), the spatial_reports upsert and its audit row, the report an earlier attempt
// stored kept over a re-render that differs, and the manifest photo labels.

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
        async downloadToBuffer() {
          const blob = blobs.get(name);
          if (blob === undefined) {
            throw new RestError("not found", { code: "BlobNotFound", statusCode: 404 });
          }
          return Buffer.from(blob.data);
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

/**
 * A database that records statements (one transaction = the same recorder) and keeps the
 * spatial_reports rows it is given, so a later attempt can read them back.
 */
function recordingDb(): Database & { statements: Array<{ sql: string; values: unknown[] }> } {
  const statements: Array<{ sql: string; values: unknown[] }> = [];
  const rows = new Map<string, Record<string, unknown>>();
  const query = async (sql: string, values: unknown[] = []) => {
    statements.push({ sql, values });
    if (sql.includes("INSERT INTO spatial_reports")) {
      const [packageId, verdictId, , blobName, sha256, bytes, pages, checksPage, floors] = values;
      rows.set(String(packageId), {
        verdict_id: verdictId,
        blob_name: blobName,
        sha256,
        bytes: String(bytes),
        pages,
        checks_page: checksPage,
        floors: JSON.parse(String(floors)) as unknown,
      });
    }
    if (sql.includes("FROM spatial_reports")) {
      const row = rows.get(String(values[0]));
      const found =
        row !== undefined && row.verdict_id === values[1] && row.blob_name === values[2];
      return { rows: found ? [row] : [], rowCount: found ? 1 : 0 };
    }
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
    await assert.rejects(
      writer.write("p/r.pdf", second, sha(second)),
      (error: unknown) => error instanceof ReportConflictError && error.storedSha256 === sha(first),
    );
    assert.equal(sha(container.blobs.get("p/r.pdf")?.data ?? new Uint8Array()), sha(first));
    assert.equal(sha(await writer.read("p/r.pdf")), sha(first));
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

  it("is idempotent for the same report", async () => {
    const container = memoryContainer();
    const db = recordingDb();
    const ctx = { db, reports: reportsWriter(container), secrets: [] };
    const first = await storeSpatialReport(ctx, PACKAGE_ID, report("a"), VERDICT);
    const again = await storeSpatialReport(ctx, PACKAGE_ID, report("a"), VERDICT);
    assert.equal(first.sha256, report("a").sha256);
    assert.equal(again.sha256, report("a").sha256);
    assert.equal(
      db.statements.filter((s) => s.sql.includes("INSERT INTO spatial_reports")).length,
      2,
    );
  });

  it("keeps the report an earlier attempt stored when a re-render differs", async () => {
    // Attempt 1 stored "a"; a newer worker re-renders "b" for the same verdict. The blob is not
    // replaced, and the job goes on with "a" (bytes, pages and floors as its row describes them).
    const container = memoryContainer();
    const db = recordingDb();
    const ctx = { db, reports: reportsWriter(container), secrets: [] };
    const stored = report("a");
    await storeSpatialReport(ctx, PACKAGE_ID, stored, VERDICT, "job-1");
    const rerender = { ...report("b"), pages: 31, checksPage: 5, floors: [] };
    const kept = await storeSpatialReport(ctx, PACKAGE_ID, rerender, VERDICT, "job-1");
    assert.equal(kept.sha256, stored.sha256);
    assert.deepEqual(kept.bytes, stored.bytes);
    assert.equal(kept.pages, stored.pages);
    assert.equal(kept.checksPage, stored.checksPage);
    assert.deepEqual(kept.floors, stored.floors);
    assert.equal(kept.name, stored.name);
    const blob = container.blobs.get(reportBlobName(PACKAGE_ID, stored.name));
    assert.equal(sha(blob?.data ?? new Uint8Array()), stored.sha256);
    assert.equal(
      db.statements.filter((s) => s.sql.includes("INSERT INTO spatial_reports")).length,
      1,
    );
    const audits = db.statements.filter((s) => s.sql.includes("INSERT INTO audit_log"));
    assert.deepEqual(
      audits.map((a) => a.values[1]),
      ["report.store", "report.kept"],
    );
    const details = JSON.parse(String(audits[1]?.values[3])) as Record<string, unknown>;
    assert.equal(details.sha256, stored.sha256);
    assert.equal(details.renderedSha256, rerender.sha256);
  });

  it("ends the job when no row of this verdict describes the stored report", async () => {
    const container = memoryContainer();
    const ctx = { db: recordingDb(), reports: reportsWriter(container), secrets: [] };
    // A blob stored by an attempt whose database write never happened.
    const orphan = report("a");
    await reportsWriter(container).write(
      reportBlobName(PACKAGE_ID, orphan.name),
      orphan.bytes,
      orphan.sha256,
    );
    await assert.rejects(
      storeSpatialReport(ctx, PACKAGE_ID, report("b"), VERDICT),
      (error: unknown) =>
        error instanceof TerminalJobError &&
        error.auditAction === "report.conflict" &&
        error.details.storedSha256 === orphan.sha256,
    );
  });

  it("ends the job when the stored report does not match its row", async () => {
    const container = memoryContainer();
    const db = recordingDb();
    const ctx = { db, reports: reportsWriter(container), secrets: [] };
    const stored = report("a");
    await storeSpatialReport(ctx, PACKAGE_ID, stored, VERDICT);
    // The blob's bytes changed under the same metadata (never written by the station).
    const blob = container.blobs.get(reportBlobName(PACKAGE_ID, stored.name));
    assert.ok(blob);
    blob.data = Buffer.from("%PDF-1.7 tampered");
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
