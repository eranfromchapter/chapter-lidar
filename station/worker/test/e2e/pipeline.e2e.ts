// F9 AC6: against the local stack a sealed fixture package reaches a stored verdict, a stored
// spatial report and a HUB publication within 120 s, and re-running the job is idempotent. A
// re-run by a worker whose render differs keeps the report stored first.
//
//   station/api/scripts/local-up.sh && npm run test:e2e --workspace station/worker
//
// The worker runs in process with HUB_MODE=live against the fake HUB server on a random
// loopback port. Rows of sealed packages are immutable, so nothing is deleted afterwards.

import assert from "node:assert/strict";
import { after, before, describe, it } from "node:test";
import { validateVerdict, type Verdict } from "@chapter/capture-contract";
import { startFakeHubServer, type FakeHubServer } from "@chapter/station-hub/fake";
import { startWorker, type StartedWorker } from "../../src/app.js";
import { loadConfig } from "../../src/config.js";
import { createLogger } from "../../src/logger.js";
import {
  AZURITE_CONNECTION_STRING,
  DATABASE_URL,
  FIXTURE_DEAL_ID,
  connectStack,
  seedSealedPackage,
  sha256,
  waitFor,
  type Stack,
} from "./support.js";

const REVIEW_BASE_URL = "http://localhost:3000";
const UPLOAD_ROLES = new Set(["plan_dxf", "rooms_csv", "plan_pdf", "plan_png"]);

let stack: Stack;
let server: FakeHubServer;
let worker: StartedWorker;
const logs: string[] = [];

interface JobState {
  job_id: string;
  type: string;
  status: string;
  attempts: number;
  last_error: string | null;
  finished_at: Date | null;
}

async function jobsOf(packageId: string): Promise<JobState[]> {
  const result = await stack.db.query<JobState>(
    `SELECT job_id, type, status, attempts, last_error, finished_at FROM jobs
      WHERE package_id = $1 ORDER BY created_at`,
    [packageId],
  );
  return result.rows;
}

async function packageStatus(packageId: string): Promise<string | undefined> {
  const result = await stack.db.query<{ status: string }>(
    `SELECT status FROM packages WHERE package_id = $1`,
    [packageId],
  );
  return result.rows[0]?.status;
}

async function publication(packageId: string) {
  const result = await stack.db.query<{
    status: string;
    verdict_id: string | null;
    attempts: number;
    files: Array<{ kind: string; name: string; folder: string | null; role: string; url?: string }>;
    error: unknown;
  }>(
    `SELECT status, verdict_id, attempts, files, error FROM hub_publications WHERE package_id = $1`,
    [packageId],
  );
  return result.rows;
}

async function spatialReport(packageId: string) {
  const result = await stack.db.query<{
    verdict_id: string;
    file_name: string;
    blob_name: string;
    sha256: string;
    bytes: number;
    pages: number;
    checks_page: number;
    floors: Array<{ areaKey: string; captureId: string; roomsScanned: number }>;
    generated_at: Date;
  }>(
    `SELECT verdict_id, file_name, blob_name, sha256, bytes, pages, checks_page, floors, generated_at
       FROM spatial_reports WHERE package_id = $1`,
    [packageId],
  );
  return result.rows;
}

async function verdicts(packageId: string) {
  const result = await stack.db.query<{
    verdict_id: string;
    outcome: string;
    document: unknown;
    evaluated_at: Date;
  }>(`SELECT verdict_id, outcome, document, evaluated_at FROM verdicts WHERE package_id = $1`, [
    packageId,
  ]);
  return result.rows;
}

/** Settled: no queued or running job for the package. */
async function settled(packageId: string): Promise<boolean> {
  return (await jobsOf(packageId)).every(
    (job) => job.status === "succeeded" || job.status === "failed",
  );
}

/** An in-process worker against the local stack and the fake HUB server. */
function startE2eWorker(workerId: string, reportTimeZone: string): StartedWorker {
  const config = loadConfig({
    NODE_ENV: "test",
    LOG_LEVEL: "info",
    DB_AUTH: "url",
    DATABASE_URL,
    AZURE_STORAGE_CONNECTION_STRING: AZURITE_CONNECTION_STRING,
    STORAGE_ORIGINALS_CONTAINER: "originals",
    STORAGE_REPORTS_CONTAINER: "reports",
    REPORT_TIME_ZONE: reportTimeZone,
    HUB_MODE: "live",
    HUB_BASE_URL: server.url,
    HUB_SERVICE_CREDENTIAL: server.hub.credential,
    REVIEW_BASE_URL,
    WORKER_ID: workerId,
    WORKER_POLL_INTERVAL_MS: "200",
    WORKER_RETRY_BASE_SECONDS: "1",
    WORKER_RETRY_MAX_SECONDS: "2",
    HUB_PUBLISH_RETRY_BASE_MS: "100",
    HUB_PUBLISH_RETRY_MAX_MS: "500",
  });
  return startWorker(
    config,
    createLogger("info", (line) => logs.push(line)),
  );
}

describe("station worker end to end (local stack)", { timeout: 300_000 }, () => {
  before(async () => {
    stack = await connectStack();
    server = await startFakeHubServer();
    worker = startE2eWorker("e2e-worker", "America/New_York");
  });

  after(async () => {
    await worker?.stop();
    await server?.close();
    await stack?.close();
    // Nothing the worker logged may carry the HUB credential.
    if (server !== undefined) {
      assert.ok(!logs.join("\n").includes(server.hub.credential));
    }
  });

  it("stores a verdict and publishes it to the HUB within 120 s; a re-run is idempotent", async () => {
    const startedAt = Date.now();
    const seeded = await seedSealedPackage(stack);
    const { packageId, visitId, checksJobId, manifest } = seeded;

    await waitFor(
      async () => {
        const rows = await publication(packageId);
        return rows[0]?.status === "published" && (await settled(packageId)) ? true : undefined;
      },
      120_000,
      "verdict and HUB publication",
    );
    const elapsed = Date.now() - startedAt;
    assert.ok(elapsed < 120_000, `took ${elapsed} ms`);

    // Stored verdict: ready, exactly as served by GET /packages/{id}/verdict, real evaluation time.
    assert.equal(await packageStatus(packageId), "verdict_ready");
    const stored = await verdicts(packageId);
    assert.equal(stored.length, 1);
    const first = stored[0]!;
    assert.equal(first.outcome, "ready");
    const checked = validateVerdict(first.document);
    assert.ok(checked.ok, "verdict document matches the contract");
    const verdict = checked.value as Verdict;
    assert.equal(verdict.packageId, packageId);
    assert.notEqual(verdict.evaluatedAt, manifest.sealedAt);
    const evaluated = Date.parse(verdict.evaluatedAt);
    assert.ok(evaluated >= Math.floor(startedAt / 1000) * 1000 && evaluated <= Date.now() + 1000);
    assert.match(verdict.evaluatedAt, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/);
    const property = verdict.checks.find((check) => check.ruleId === "property.address");
    assert.equal(property?.status, "passed");

    const runs = await stack.db.query<{ run_id: string; status: string; job_id: string }>(
      `SELECT run_id, status, job_id FROM check_runs WHERE package_id = $1`,
      [packageId],
    );
    assert.equal(runs.rows.length, 1);
    assert.equal(runs.rows[0]?.status, "completed");
    assert.equal(runs.rows[0]?.job_id, checksJobId);
    const results = await stack.db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM check_results WHERE run_id = $1`,
      [runs.rows[0]?.run_id],
    );
    assert.equal(results.rows[0]?.n, verdict.checks.length);

    const jobs = await jobsOf(packageId);
    assert.deepEqual(
      jobs.map((job) => `${job.type}:${job.status}`),
      ["checks:succeeded", "publish:succeeded"],
    );
    const firstPublishJobId = jobs[1]!.job_id;

    // HUB: report + manifest in Capture/<visitId>/r1, plan files per capture, with the dealId.
    const pub = (await publication(packageId))[0]!;
    assert.equal(pub.verdict_id, verdict.verdictId);
    assert.equal(pub.attempts, 1);
    assert.equal(pub.error, null);
    const visitFolder = `Capture/${visitId}/r1`;
    const planEntries = manifest.files.filter((entry) => UPLOAD_ROLES.has(entry.role));
    const expected = [
      `${visitFolder}/spatial-report-${verdict.verdictId}.pdf`,
      `${visitFolder}/manifest.json`,
      ...planEntries.map(
        (entry) => `Capture/${entry.areaKey}/${entry.captureId}/r1/${entry.path.split("/").pop()}`,
      ),
    ].sort();
    const ours = () =>
      server.hub.documents.filter(
        (doc) =>
          doc.folder === visitFolder ||
          planEntries.some((e) => doc.folder.includes(e.captureId ?? "-")),
      );
    assert.deepEqual(
      ours()
        .map((doc) => `${doc.folder}/${doc.name}`)
        .sort(),
      expected,
    );
    for (const request of server.hub.requestsOf("upload")) {
      assert.equal(request.dealId, FIXTURE_DEAL_ID);
      assert.ok(request.authorized);
    }
    const manifestDoc = ours().find((doc) => doc.name === "manifest.json");
    assert.ok(manifestDoc);
    const report = ours().find((doc) => doc.name.startsWith("spatial-report-"));
    assert.equal(
      Buffer.from(report?.data ?? [])
        .subarray(0, 5)
        .toString("latin1"),
      "%PDF-",
    );
    assert.equal(pub.files.filter((f) => f.kind === "uploaded").length, expected.length);
    const linked = pub.files.filter((f) => f.kind === "linked");
    assert.equal(linked.length, manifest.files.length - planEntries.length);
    for (const file of linked) {
      assert.ok(file.url?.startsWith(`${REVIEW_BASE_URL}/packages/${packageId}?file=`));
    }

    const audits = await stack.db.query<{ action: string }>(
      `SELECT action FROM audit_log WHERE target_type = 'package' AND target_id = $1 ORDER BY audit_id`,
      [packageId],
    );
    assert.deepEqual(
      audits.rows.map((row) => row.action),
      ["verdict.store", "report.store", "hub.publish"],
    );

    // The spatial report stored for the web review is the HUB document, byte for byte.
    const storedReports = await spatialReport(packageId);
    assert.equal(storedReports.length, 1);
    const row = storedReports[0]!;
    assert.equal(row.verdict_id, verdict.verdictId);
    assert.equal(row.file_name, `spatial-report-${verdict.verdictId}.pdf`);
    assert.equal(row.blob_name, `${packageId}/spatial-report-${verdict.verdictId}.pdf`);
    assert.equal(row.sha256, report?.sha256);
    assert.equal(row.bytes, report?.bytes);
    assert.ok(row.pages >= 5 && row.checks_page >= 2 && row.checks_page <= row.pages);
    assert.equal(row.generated_at.toISOString().replace(/\.\d{3}Z$/, "Z"), verdict.evaluatedAt);
    assert.ok(Array.isArray(row.floors) && row.floors.length === 1);
    assert.equal(row.floors[0]?.areaKey, manifest.files.find((f) => f.areaKey)?.areaKey);
    const blob = await stack.reports.getBlobClient(row.blob_name).downloadToBuffer();
    assert.equal(sha256(blob), report?.sha256);
    const reportEntry = pub.files.find((f) => f.name === row.file_name);
    assert.equal(reportEntry?.role, "spatial_report");

    // Re-run the checks job: it replaces its own run and upserts the one verdict row.
    const rerunAt = new Date();
    await stack.db.query(
      `UPDATE jobs SET status = 'queued', attempts = 0, run_after = now(), finished_at = NULL, last_error = NULL
        WHERE job_id = $1`,
      [checksJobId],
    );
    await waitFor(
      async () => {
        const all = await jobsOf(packageId);
        const checks = all.find((job) => job.job_id === checksJobId);
        const pubRow = (await publication(packageId))[0];
        const current = (await verdicts(packageId))[0];
        return checks?.status === "succeeded" &&
          (checks.finished_at?.getTime() ?? 0) >= rerunAt.getTime() - 1000 &&
          all.every((job) => job.status === "succeeded") &&
          pubRow?.status === "published" &&
          pubRow.verdict_id === current?.verdict_id
          ? true
          : undefined;
      },
      120_000,
      "the re-run checks job and its publication",
    );
    // Re-run the first publish job too.
    await stack.db.query(
      `UPDATE jobs SET status = 'queued', attempts = 0, run_after = now(), finished_at = NULL, last_error = NULL
        WHERE job_id = $1`,
      [firstPublishJobId],
    );
    await waitFor(
      async () => {
        const job = (await jobsOf(packageId)).find((j) => j.job_id === firstPublishJobId);
        return job?.status === "succeeded" ? true : undefined;
      },
      60_000,
      "the re-run publish job",
    );

    const after = await verdicts(packageId);
    assert.equal(after.length, 1, "one verdict row");
    const runsAfter = await stack.db.query<{ run_id: string; status: string }>(
      `SELECT run_id, status FROM check_runs WHERE package_id = $1`,
      [packageId],
    );
    assert.equal(runsAfter.rows.length, 1, "the job's run was replaced");
    assert.equal(runsAfter.rows[0]?.status, "completed");
    const resultsAfter = await stack.db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM check_results r JOIN check_runs c ON c.run_id = r.run_id WHERE c.package_id = $1`,
      [packageId],
    );
    assert.equal(resultsAfter.rows[0]?.n, verdict.checks.length);
    assert.equal((await publication(packageId)).length, 1);
    assert.equal((await publication(packageId))[0]?.status, "published");

    // No duplicate HUB uploads: every folder/name once; plan files and manifest uploaded once.
    const names = ours().map((doc) => `${doc.folder}/${doc.name}`);
    assert.equal(new Set(names).size, names.length, `duplicates: ${names.join(", ")}`);
    const nonReport = ours().filter((doc) => !doc.name.startsWith("spatial-report-"));
    assert.equal(nonReport.length, expected.length - 1);
    const verdictIds = new Set([verdict.verdictId, after[0]!.verdict_id]);
    const reports = ours().filter((doc) => doc.name.startsWith("spatial-report-"));
    assert.equal(reports.length, verdictIds.size, "one report per verdict");
    assert.equal(await packageStatus(packageId), "verdict_ready");

    // One spatial_reports row per package, for the current verdict; every report blob kept.
    const storedAfter = await spatialReport(packageId);
    assert.equal(storedAfter.length, 1);
    assert.equal(storedAfter[0]?.verdict_id, after[0]!.verdict_id);
    for (const id of verdictIds) {
      assert.ok(
        await stack.reports.getBlobClient(`${packageId}/spatial-report-${id}.pdf`).exists(),
        `report blob of ${id}`,
      );
    }
  });

  it("ends in check_error, not a verdict, when a stored file no longer matches its SHA-256", async () => {
    const seeded = await seedSealedPackage(stack, {
      tamperPath: (path) => path.endsWith("/plan.dxf"),
    });
    const { packageId, checksJobId, visitId } = seeded;
    await waitFor(
      async () =>
        (await packageStatus(packageId)) === "check_error" && (await settled(packageId))
          ? true
          : undefined,
      60_000,
      "check_error",
    );
    assert.equal((await verdicts(packageId)).length, 0);
    const jobs = await jobsOf(packageId);
    assert.equal(jobs.length, 1);
    assert.equal(jobs[0]?.status, "failed");
    assert.equal(jobs[0]?.attempts, 1, "integrity failures are not retried");
    assert.match(jobs[0]?.last_error ?? "", /SHA-256/);
    const runs = await stack.db.query<{ status: string; error: string; job_id: string }>(
      `SELECT status, error, job_id FROM check_runs WHERE package_id = $1`,
      [packageId],
    );
    assert.equal(runs.rows.length, 1);
    assert.equal(runs.rows[0]?.status, "failed");
    assert.equal(runs.rows[0]?.job_id, checksJobId);
    const audit = await stack.db.query<{ action: string; details: Record<string, unknown> }>(
      `SELECT action, details FROM audit_log WHERE target_type = 'package' AND target_id = $1`,
      [packageId],
    );
    assert.equal(audit.rows.length, 1);
    assert.equal(audit.rows[0]?.action, "package.integrity_error");
    assert.equal(audit.rows[0]?.details.reason, "sha256_mismatch");
    assert.match(String(audit.rows[0]?.details.path), /plan\.dxf$/);
    assert.equal((await publication(packageId)).length, 0);
    assert.equal((await spatialReport(packageId)).length, 0);
    assert.ok(!server.hub.documents.some((doc) => doc.folder.includes(visitId)));
  });

  it("retries while the HUB deal lookup fails and ends in check_error without a verdict", async () => {
    server.hub.failNext({ operation: "list_deals", status: 503, times: 1000 });
    try {
      const seeded = await seedSealedPackage(stack, { maxAttempts: 2 });
      const { packageId } = seeded;
      await waitFor(
        async () =>
          (await packageStatus(packageId)) === "check_error" && (await settled(packageId))
            ? true
            : undefined,
        60_000,
        "check_error after the HUB stayed unavailable",
      );
      assert.equal((await verdicts(packageId)).length, 0);
      const jobs = await jobsOf(packageId);
      assert.equal(jobs.length, 1);
      assert.equal(jobs[0]?.status, "failed");
      assert.equal(jobs[0]?.attempts, 2);
      assert.match(jobs[0]?.last_error ?? "", /HUB deal lookup failed: HUB answered 503/);
      assert.ok(!(jobs[0]?.last_error ?? "").includes(server.hub.credential));
    } finally {
      server.hub.clearFailures();
    }
  });

  it("links the phone's retired report of a legacy package and stores the station's report", async () => {
    const seeded = await seedSealedPackage(stack, { fixture: "legacy-1.0.0" });
    const { packageId, visitId, manifest } = seeded;
    await waitFor(
      async () => {
        const rows = await publication(packageId);
        return rows[0]?.status === "published" && (await settled(packageId)) ? true : undefined;
      },
      120_000,
      "the legacy package's publication",
    );
    const legacy = manifest.files.filter((entry) => entry.role === "spatial_report_pdf");
    assert.ok(legacy.length > 0, "the legacy fixture carries the phone's report");
    const pub = (await publication(packageId))[0]!;
    for (const entry of legacy) {
      const recorded = pub.files.find((f) => f.name === entry.path);
      assert.equal(recorded?.kind, "linked");
      assert.ok(
        !server.hub.documents.some(
          (doc) => doc.folder.includes(entry.captureId ?? "-") && doc.name === "spatial-report.pdf",
        ),
      );
    }
    const verdict = (await verdicts(packageId))[0]!;
    assert.ok(
      server.hub.documents.some(
        (doc) =>
          doc.folder === `Capture/${visitId}/r1` &&
          doc.name === `spatial-report-${verdict.verdict_id}.pdf`,
      ),
    );
    assert.equal((await spatialReport(packageId))[0]?.verdict_id, verdict.verdict_id);
  });

  it("recovers a job whose worker died (stale lock) and counts the attempt", async () => {
    const seeded = await seedSealedPackage(stack, { staleLock: true });
    const { packageId, checksJobId } = seeded;
    await waitFor(
      async () => {
        const pub = (await publication(packageId))[0];
        return pub?.status === "published" && (await settled(packageId)) ? true : undefined;
      },
      120_000,
      "verdict after stale lock recovery",
    );
    const checks = (await jobsOf(packageId)).find((job) => job.job_id === checksJobId);
    assert.equal(checks?.status, "succeeded");
    assert.equal(checks?.attempts, 2, "the dead worker's attempt counts");
    assert.equal((await verdicts(packageId)).length, 1);
  });

  it("keeps the stored report when a newer worker's render of the same verdict differs", async () => {
    // Attempt 1 stores the report, then the HUB refuses every upload: publish_failed. The job
    // is run again by a worker that prints times in another zone (as after a deploy): its
    // render differs, the stored report is not replaced, and the HUB gets the stored one.
    server.hub.failNext({ operation: "upload", status: 503, times: 1000 });
    let packageId: string;
    try {
      ({ packageId } = await seedSealedPackage(stack));
      await waitFor(
        async () =>
          (await publication(packageId))[0]?.status === "publish_failed" &&
          (await settled(packageId))
            ? true
            : undefined,
        120_000,
        "a publication that failed after the report was stored",
      );
    } finally {
      server.hub.clearFailures();
    }
    const stored = (await spatialReport(packageId))[0]!;
    const publishJob = (await jobsOf(packageId)).find((job) => job.type === "publish")!;
    assert.equal(publishJob.status, "failed");

    await worker.stop();
    worker = startE2eWorker("e2e-worker-tokyo", "Asia/Tokyo");
    try {
      await stack.db.query(
        `UPDATE jobs SET status = 'queued', attempts = 0, run_after = now(), finished_at = NULL, last_error = NULL
          WHERE job_id = $1`,
        [publishJob.job_id],
      );
      await waitFor(
        async () =>
          (await publication(packageId))[0]?.status === "published" && (await settled(packageId))
            ? true
            : undefined,
        120_000,
        "the publication by the newer worker",
      );
    } finally {
      await worker.stop();
      worker = startE2eWorker("e2e-worker", "America/New_York");
    }

    const after = await spatialReport(packageId);
    assert.equal(after.length, 1);
    assert.equal(after[0]?.sha256, stored.sha256, "the stored report's row is unchanged");
    const blob = await stack.reports.getBlobClient(stored.blob_name).downloadToBuffer();
    assert.equal(sha256(blob), stored.sha256, "the stored report is not replaced");
    const report = server.hub.documents.find((doc) => doc.name === stored.file_name);
    assert.equal(report?.sha256, stored.sha256, "the HUB holds the stored report");
    const audits = await stack.db.query<{ action: string; details: Record<string, unknown> }>(
      `SELECT action, details FROM audit_log WHERE target_type = 'package' AND target_id = $1 ORDER BY audit_id`,
      [packageId],
    );
    assert.deepEqual(
      audits.rows.map((row) => row.action),
      ["verdict.store", "report.store", "hub.publish_failed", "report.kept", "hub.publish"],
    );
    const kept = audits.rows.find((row) => row.action === "report.kept");
    assert.equal(kept?.details.sha256, stored.sha256);
    assert.notEqual(kept?.details.renderedSha256, stored.sha256);
  });
});
