// getSpatialReportLink (spatial-report §8.3, critique R-14, OpenAPI 1.1.0) matches
// contract/openapi/station.yaml: bim/admin get a read-only, 10-minute link to the report blob
// of the current verdict in the reports container; 404 report_not_ready while there is none
// (no row, a row of an older verdict, no current verdict); every link is audited without the
// URL. The worker fills spatial_reports in the plans phase; here rows are seeded. Runs against
// a throwaway Postgres and a disposable Azurite (it checks SAS signatures).

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { after, before, describe, it } from "node:test";
import { readLinkSignerFromConfig } from "../../src/routes/packages/download.js";
import { DOWNLOAD_LINK_TTL_MS } from "../../src/routes/packages/download.js";
import { testConfig } from "../core/helpers.js";
import { startAzurite, type TestAzurite } from "./azurite.js";
import { OpenApi } from "./openapi.js";
import {
  BROKEN_VERDICT_ID,
  PACKAGE_ID,
  QUEUED_ID,
  UNKNOWN_ID,
  VERDICT,
  seedRegistry,
  startStation,
  type TestStation,
} from "./support.js";

const OPERATION = "getSpatialReportLink";
const REPORTS_CONTAINER = "station-reports";
const REPORT_BODY = "%PDF-1.7\n% spatial report of the limited example verdict\n";
const REPORT_NAME = `spatial-report-${VERDICT.verdictId}.pdf`;
const REPORT_BLOB = `${PACKAGE_ID}/${REPORT_NAME}`;

const openapi = new OpenApi();
let azurite: TestAzurite;
let station: TestStation;
const produced = new Set<number>();

function sha256(text: string): string {
  return createHash("sha256").update(text).digest("hex");
}

async function insertReport(packageId: string, verdictId: string, blobName: string, body: string) {
  await station.db.query(
    `INSERT INTO spatial_reports
       (package_id, verdict_id, file_name, blob_name, sha256, bytes, pages, checks_page, floors,
        generated_at)
     VALUES ($1, $2, $3, $4, $5, $6, 28, 4, $7::jsonb, $8)`,
    [
      packageId,
      verdictId,
      `spatial-report-${verdictId}.pdf`,
      blobName,
      sha256(body),
      Buffer.byteLength(body),
      JSON.stringify([]),
      VERDICT.evaluatedAt,
    ],
  );
}

before(async () => {
  azurite = await startAzurite();
  const reports = azurite.service.getContainerClient(REPORTS_CONTAINER);
  await reports.createIfNotExists();
  await reports.getBlockBlobClient(REPORT_BLOB).upload(REPORT_BODY, Buffer.byteLength(REPORT_BODY));
  const config = testConfig({
    AZURE_STORAGE_CONNECTION_STRING: azurite.connectionString,
    STORAGE_REPORTS_CONTAINER: REPORTS_CONTAINER,
  });
  station = await startStation({
    services: {
      reportLinks: readLinkSignerFromConfig(config, undefined, config.storage.reportsContainer),
    },
  });
  await seedRegistry(station.db);
  await insertReport(PACKAGE_ID, VERDICT.verdictId, REPORT_BLOB, REPORT_BODY);
  // A report of an earlier verdict of BROKEN_VERDICT_ID: not the current one.
  await insertReport(
    BROKEN_VERDICT_ID,
    "0e1f2a3b-4c5d-4e6f-8a7b-9c0d1e2f3a4b",
    `${BROKEN_VERDICT_ID}/spatial-report-0e1f2a3b-4c5d-4e6f-8a7b-9c0d1e2f3a4b.pdf`,
    "%PDF-1.7 old",
  );
});

after(async () => {
  await station?.close();
  azurite?.stop();
});

async function call(packageId: string, roles: readonly ("capture" | "bim" | "admin")[] = ["bim"]) {
  const response = await station.app.inject({
    method: "GET",
    url: `/v1/packages/${packageId}/spatial-report`,
    headers: await station.auth(roles),
  });
  assert.deepEqual(openapi.responseErrors(OPERATION, response), [], response.body);
  produced.add(response.statusCode);
  return response;
}

describe("getSpatialReportLink", () => {
  it("is routed with the documented roles", () => {
    const op = openapi.operation(OPERATION);
    const route = station.app.routeAccess.find(
      (access) => access.url === op.routeUrl && access.method.split(",").includes(op.method),
    );
    assert.ok(route, `no route for ${op.method} ${op.routeUrl}`);
    assert.deepEqual([...route.roles].sort(), [...op.roles].sort());
  });

  it("200 for bim and admin: a working read-only link to the current verdict's report", async () => {
    for (const role of ["bim", "admin"] as const) {
      const started = Date.now();
      const response = await call(PACKAGE_ID, [role]);
      assert.equal(response.statusCode, 200, response.body);
      const { url, expiresAt, ...rest } = response.json() as Record<string, unknown>;
      assert.deepEqual(rest, {
        verdictId: VERDICT.verdictId,
        name: REPORT_NAME,
        sha256: sha256(REPORT_BODY),
        bytes: Buffer.byteLength(REPORT_BODY),
        pages: 28,
        checksPage: 4,
        generatedAt: VERDICT.evaluatedAt,
      });
      const expiry = Date.parse(String(expiresAt));
      assert.ok(Math.abs(expiry - (started + DOWNLOAD_LINK_TTL_MS)) < 5_000, String(expiresAt));
      const link = new URL(String(url));
      assert.equal(link.searchParams.get("sp"), "r");
      assert.equal(
        decodeURIComponent(link.pathname),
        `/devstoreaccount1/${REPORTS_CONTAINER}/${REPORT_BLOB}`,
      );
      const fetched = await fetch(link);
      assert.equal(fetched.status, 200);
      assert.equal(await fetched.text(), REPORT_BODY);
      assert.match(String(fetched.headers.get("content-disposition")), new RegExp(REPORT_NAME));
    }
  });

  it("audits every link without the URL or signature", async () => {
    const response = await call(PACKAGE_ID, ["admin"]);
    const { url, expiresAt } = response.json() as { url: string; expiresAt: string };
    const signature = new URL(url).searchParams.get("sig") ?? "";
    const rows = await station.db.query<{ target_id: string; details: Record<string, unknown> }>(
      `SELECT target_id, details FROM audit_log WHERE action = 'report.download_link'
        ORDER BY audit_id DESC LIMIT 1`,
    );
    assert.deepEqual(rows.rows[0], {
      target_id: PACKAGE_ID,
      details: { verdictId: VERDICT.verdictId, name: REPORT_NAME, expiresAt },
    });
    const all = await station.db.query("SELECT details::text AS d FROM audit_log");
    assert.ok(!all.rows.some((row) => String(row.d).includes(signature)));
    assert.ok(!station.logs.some((line) => line.includes(signature)));
  });

  it("404 report_not_ready without a report, with an older verdict's report, or without a verdict", async () => {
    for (const id of [QUEUED_ID, BROKEN_VERDICT_ID]) {
      const response = await call(id);
      assert.equal(response.statusCode, 404, id);
      assert.equal((response.json() as { code: string }).code, "report_not_ready");
    }
    // Checks running again: the verdict row stays but is not current.
    await station.db.query("UPDATE packages SET status = 'checking' WHERE package_id = $1", [
      PACKAGE_ID,
    ]);
    try {
      const response = await call(PACKAGE_ID);
      assert.equal((response.json() as { code: string }).code, "report_not_ready");
    } finally {
      await station.db.query("UPDATE packages SET status = 'verdict_ready' WHERE package_id = $1", [
        PACKAGE_ID,
      ]);
    }
  });

  it("404 not_found for an unknown or malformed package id", async () => {
    for (const id of [UNKNOWN_ID, "not-a-uuid", PACKAGE_ID.toUpperCase()]) {
      const response = await call(id);
      assert.equal(response.statusCode, 404, id);
      assert.equal((response.json() as { code: string }).code, "not_found");
    }
  });

  it("403 for the capture role and 401 without a token", async () => {
    const forbidden = await call(PACKAGE_ID, ["capture"]);
    assert.equal(forbidden.statusCode, 403);
    const anonymous = await station.app.inject({
      method: "GET",
      url: `/v1/packages/${PACKAGE_ID}/spatial-report`,
    });
    assert.equal(anonymous.statusCode, 401);
    assert.deepEqual(openapi.responseErrors(OPERATION, anonymous), []);
    produced.add(anonymous.statusCode);
  });

  it("produced every documented status", () => {
    const documented = Object.keys(
      openapi.operation(OPERATION).node.responses as Record<string, unknown>,
    ).sort();
    assert.deepEqual([...produced].map(String).sort(), documented);
  });
});

describe("spatial_reports rows", () => {
  it("must name the report after its verdict and keep the checks page within the report", async () => {
    await assert.rejects(
      station.db.query(
        `INSERT INTO spatial_reports
           (package_id, verdict_id, file_name, blob_name, sha256, bytes, pages, checks_page,
            floors, generated_at)
         VALUES ($1, $2, 'spatial-report-00000000-0000-4000-8000-000000000000.pdf', 'x', $3, 1,
                 1, 1, '[]', now())`,
        [QUEUED_ID, VERDICT.verdictId, sha256("x")],
      ),
      /spatial_reports_file_name_matches_verdict/,
    );
    await assert.rejects(
      station.db.query(
        `INSERT INTO spatial_reports
           (package_id, verdict_id, file_name, blob_name, sha256, bytes, pages, checks_page,
            floors, generated_at)
         VALUES ($1, $2, $3, 'x', $4, 1, 3, 4, '[]', now())`,
        [QUEUED_ID, VERDICT.verdictId, REPORT_NAME, sha256("x")],
      ),
      /spatial_reports_checks_page_in_report/,
    );
    await assert.rejects(
      station.db.query(
        `INSERT INTO spatial_reports
           (package_id, verdict_id, file_name, blob_name, sha256, bytes, pages, checks_page,
            floors, generated_at)
         VALUES ($1, $2, $3, 'x', $4, 1, 3, 1, '{}', now())`,
        [QUEUED_ID, VERDICT.verdictId, REPORT_NAME, sha256("x")],
      ),
      /spatial_reports_floors_array/,
    );
  });
});
