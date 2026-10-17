// Upload sessions, server-side file checks and sealing (contract/openapi/station.yaml operations
// createUploadSession, completeFile and sealPackage). Roles: capture, admin.
//
// POST /packages                         open or resume a session; one create-only SAS target
//                                         (30 minutes) per file that is not verified
// POST /packages/:packageId/files/complete
//                                         stream the stored blob, compute SHA-256 and size,
//                                         record verified / sha256_mismatch / bytes_mismatch /
//                                         not_uploaded
// POST /packages/:packageId/seal         register the manifest (stored as
//                                         Source Register/{visitId}/manifest.json), queue one
//                                         checks job, status checks_queued
//
// Immutability: a verified file never gets an upload target again and its registry row is frozen
// (DB trigger); targets are create-only, so an existing blob cannot be overwritten or deleted
// through one. A mismatched blob cannot be replaced either, so its next target is a new blob
// (see storage/originals.ts). Every write is audited in the same transaction.

import { createHash } from "node:crypto";
import {
  formatErrors,
  validateCaptureRecord,
  validateManifest,
  type PackageManifest,
} from "@chapter/capture-contract";
import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { audit } from "../../core/audit.js";
import { requirePrincipal, type Role } from "../../core/auth.js";
import type { Queryable } from "../../core/db.js";
import { ProblemError, validationErrors } from "../../core/problem.js";
import { toApiDateTime } from "../../core/time.js";
import { createAzureOriginalsStorage } from "../../storage/azure-blob.js";
import {
  BlobExistsError,
  OriginalsStorageError,
  firstBlobName,
  manifestBlobName,
  nextAttemptBlobName,
  unconfiguredOriginals,
  type OriginalsStorage,
  type UploadGrant,
} from "../../storage/originals.js";
import { manifestMismatchErrors, sessionRequestErrors } from "./rules.js";
import {
  completeFileRequestSchema,
  packageIdParamsSchema,
  sealRequestSchema,
  uploadSessionRequestSchema,
  type CompleteFileRequest,
  type PackageIdParams,
  type UploadSessionRequest,
} from "./schemas.js";
import {
  FILE_COLUMNS,
  declarationOf,
  fileCheckResultView,
  inDeclaredOrder,
  packageView,
  selectFiles,
  selectPackage,
  type FileRow,
  type FileStatus,
  type PackageStatus,
} from "./views.js";

export const UPLOAD_ROLES: readonly Role[] = ["capture", "admin"];

/** Largest capture record the station parses at sealing. */
export const MAX_CAPTURE_RECORD_BYTES = 4 * 1024 * 1024;

interface SessionFile {
  readonly path: string;
  readonly status: FileStatus;
  readonly blobName: string;
  /** True when the file gets an upload target. */
  readonly grant: boolean;
}

interface OpenedSession {
  readonly created: boolean;
  readonly status: PackageStatus;
  readonly files: SessionFile[];
}

function resolveStorage(app: FastifyInstance): OriginalsStorage {
  const services = app.services;
  if (services.originals !== undefined) {
    return services.originals;
  }
  // Throws (and so stops startup) on an unusable connection string.
  const created = createAzureOriginalsStorage(app.config.storage);
  if (created === undefined) {
    app.log.warn("originals storage is not configured: upload routes answer 503");
  }
  const storage = created ?? unconfiguredOriginals(app.config.storage.originalsContainer);
  services.originals = storage;
  return storage;
}

/** Runs a storage call; storage failures become 503 storage_unavailable (logged, no secrets). */
async function storageCall<T>(
  request: FastifyRequest,
  operation: string,
  fn: () => Promise<T>,
): Promise<T> {
  try {
    return await fn();
  } catch (error) {
    if (error instanceof OriginalsStorageError && !(error instanceof BlobExistsError)) {
      request.log.error(
        {
          storage: {
            operation,
            code: error.code,
            status: error.statusCode,
            message: error.message,
          },
        },
        "originals storage failed",
      );
      throw new ProblemError(503, "storage_unavailable", {
        detail: "The originals storage is unavailable. Try again later.",
      });
    }
    throw error;
  }
}

function isUniqueViolation(error: unknown, constraint: string): boolean {
  if (typeof error !== "object" || error === null) {
    return false;
  }
  const { code, constraint: name } = error as { code?: unknown; constraint?: unknown };
  return code === "23505" && name === constraint;
}

function targetView(grant: UploadGrant): Record<string, unknown> {
  return {
    url: grant.url,
    method: grant.method,
    headers: { ...grant.headers },
    expiresAt: toApiDateTime(grant.expiresAt),
  };
}

function sha256Hex(data: Buffer): string {
  return createHash("sha256").update(data).digest("hex");
}

function notFound(code: "package_not_found" | "file_not_found", detail: string): ProblemError {
  return new ProblemError(404, code, { detail });
}

function sealedConflict(): ProblemError {
  return new ProblemError(409, "package_sealed", {
    detail: "The package is sealed; its files can no longer change.",
  });
}

async function openSession(
  tx: Queryable,
  request: FastifyRequest,
  body: UploadSessionRequest,
): Promise<OpenedSession> {
  const principal = requirePrincipal(request);
  const packageId = body.packageId;
  const sessionJson = JSON.stringify(body);

  const inserted = await tx.query(
    `INSERT INTO packages
       (package_id, visit_id, deal_id, revision, supersedes_package_id, session_request,
        created_by_id, created_by_name)
     VALUES ($1, $2, $3, $4, $5, $6::jsonb, $7, $8)
     ON CONFLICT (package_id) DO NOTHING
     RETURNING package_id`,
    [
      packageId,
      body.visitId,
      body.dealId,
      body.revision,
      body.supersedesPackageId ?? null,
      sessionJson,
      principal.userId,
      principal.name,
    ],
  );

  if (inserted.rowCount === 1) {
    const blobNames = body.files.map((file) => firstBlobName(packageId, file.path));
    await tx.query(
      `INSERT INTO package_files
         (package_id, path, role, capture_id, area_key, sha256, bytes, blob_name)
       SELECT $1, f.path, f.role, f.capture_id, f.area_key, f.sha256, f.bytes, f.blob_name
         FROM unnest($2::text[], $3::text[], $4::uuid[], $5::text[], $6::text[], $7::bigint[],
                     $8::text[])
           AS f(path, role, capture_id, area_key, sha256, bytes, blob_name)`,
      [
        packageId,
        body.files.map((file) => file.path),
        body.files.map((file) => file.role),
        body.files.map((file) => file.captureId ?? null),
        body.files.map((file) => file.areaKey ?? null),
        body.files.map((file) => file.sha256),
        body.files.map((file) => file.bytes),
        blobNames,
      ],
    );
    await audit(
      request,
      "package.create",
      { type: "package", id: packageId },
      {
        visitId: body.visitId,
        dealId: body.dealId,
        revision: body.revision,
        ...(body.supersedesPackageId === undefined
          ? {}
          : { supersedesPackageId: body.supersedesPackageId }),
        files: body.files.length,
        uploadTargets: body.files.length,
        container: request.server.services.originals?.container,
      },
      tx,
    );
    return {
      created: true,
      status: "uploading",
      files: body.files.map((file, index) => ({
        path: file.path,
        status: "pending",
        blobName: blobNames[index] ?? firstBlobName(packageId, file.path),
        grant: true,
      })),
    };
  }

  const existing = await tx.query<{ status: PackageStatus; same: boolean }>(
    `SELECT status, session_request = $2::jsonb AS same
       FROM packages WHERE package_id = $1 FOR UPDATE`,
    [packageId, sessionJson],
  );
  const row = existing.rows[0];
  if (row === undefined || !row.same) {
    throw new ProblemError(409, "package_conflict", {
      detail: "A package with this packageId exists with a different upload session body.",
    });
  }

  const rows = await tx.query<FileRow>(
    `SELECT ${FILE_COLUMNS} FROM package_files WHERE package_id = $1 FOR UPDATE`,
    [packageId],
  );
  const byPath = new Map(rows.rows.map((file) => [file.path, file]));
  const uploading = row.status === "uploading";
  const retried: string[] = [];
  const files: SessionFile[] = [];
  for (const declared of body.files) {
    const file = byPath.get(declared.path);
    if (file === undefined) {
      throw new Error(`declared file missing from the registry: package ${packageId}`);
    }
    let blobName = file.blob_name ?? firstBlobName(packageId, file.path);
    let status = file.status;
    if (uploading && (status === "sha256_mismatch" || status === "bytes_mismatch")) {
      // The rejected blob cannot be replaced (immutability): the next target is a new blob.
      blobName = nextAttemptBlobName(packageId, file.path, blobName);
      await tx.query(
        `UPDATE package_files
            SET status = 'pending', actual_sha256 = NULL, actual_bytes = NULL,
                checked_at = NULL, blob_name = $3
          WHERE package_id = $1 AND path = $2`,
        [packageId, file.path, blobName],
      );
      status = "pending";
      retried.push(file.path);
    }
    files.push({ path: file.path, status, blobName, grant: uploading && status !== "verified" });
  }

  await audit(
    request,
    "package.resume",
    { type: "package", id: packageId },
    {
      status: row.status,
      uploadTargets: files.filter((file) => file.grant).length,
      newAttempts: retried,
    },
    tx,
  );
  return { created: false, status: row.status, files };
}

interface LocatedFile {
  readonly packageStatus: PackageStatus;
  readonly file: FileRow;
}

async function locateFile(
  db: Queryable,
  packageId: string,
  path: string,
  lock: boolean,
): Promise<LocatedFile> {
  const result = await db.query<{ package_status: PackageStatus } & Partial<FileRow>>(
    `SELECT p.status AS package_status,
            f.path, f.role, f.capture_id, f.area_key, f.sha256, f.bytes, f.status,
            f.actual_sha256, f.actual_bytes, f.checked_at, f.blob_name
       FROM packages p
       LEFT JOIN package_files f ON f.package_id = p.package_id AND f.path = $2
      WHERE p.package_id = $1
      ${lock ? "FOR UPDATE OF p" : ""}`,
    [packageId, path],
  );
  const row = result.rows[0];
  if (row === undefined) {
    throw notFound("package_not_found", "No package with this packageId.");
  }
  if (row.path === undefined || row.path === null) {
    throw notFound("file_not_found", "The package has no declared file with this path.");
  }
  const { package_status: packageStatus, ...file } = row;
  return { packageStatus, file: file as FileRow };
}

function checkStatus(
  file: FileRow,
  digest: { sha256: string; bytes: number } | undefined,
): FileStatus {
  if (digest === undefined) {
    return "not_uploaded";
  }
  if (digest.bytes !== file.bytes) {
    return "bytes_mismatch";
  }
  return digest.sha256 === file.sha256 ? "verified" : "sha256_mismatch";
}

async function sendPackage(
  app: FastifyInstance,
  reply: FastifyReply,
  packageId: string,
  status: 200 | 202,
): Promise<FastifyReply> {
  const row = await selectPackage(app.db, packageId);
  if (row === undefined) {
    throw notFound("package_not_found", "No package with this packageId.");
  }
  const files = await selectFiles(app.db, packageId);
  return reply.code(status).send(packageView(row, files));
}

export default async function uploadRoutes(app: FastifyInstance): Promise<void> {
  const storage = resolveStorage(app);

  app.post<{ Body: UploadSessionRequest }>(
    "/packages",
    {
      config: { roles: UPLOAD_ROLES },
      schema: { body: uploadSessionRequestSchema },
    },
    async (request, reply) => {
      const body = request.body;
      const errors = sessionRequestErrors(body);
      if (errors.length > 0) {
        throw new ProblemError(422, "invalid_upload_session", {
          detail: "The upload session request breaks a contract rule.",
          errors,
        });
      }

      let session: OpenedSession;
      try {
        session = await app.db.transaction((tx) => openSession(tx, request, body));
      } catch (error) {
        if (isUniqueViolation(error, "packages_visit_revision_key")) {
          throw new ProblemError(409, "revision_exists", {
            detail: "Another package is registered for this visitId and revision.",
          });
        }
        throw error;
      }

      const files = await storageCall(request, "issue upload targets", () =>
        Promise.all(
          session.files.map(async (file) =>
            file.grant
              ? {
                  path: file.path,
                  status: file.status,
                  upload: targetView(await storage.grantUpload(file.blobName)),
                }
              : { path: file.path, status: file.status },
          ),
        ),
      );

      if (session.created) {
        reply.header("location", `/v1/packages/${body.packageId}`);
      }
      return reply.code(session.created ? 201 : 200).send({
        packageId: body.packageId,
        visitId: body.visitId,
        dealId: body.dealId,
        revision: body.revision,
        status: session.status,
        files,
      });
    },
  );

  app.post<{ Params: PackageIdParams; Body: CompleteFileRequest }>(
    "/packages/:packageId/files/complete",
    {
      config: { roles: UPLOAD_ROLES },
      schema: { params: packageIdParamsSchema, body: completeFileRequestSchema },
    },
    async (request) => {
      const { packageId } = request.params;
      const { path } = request.body;

      const current = await locateFile(app.db, packageId, path, false);
      if (current.packageStatus !== "uploading") {
        throw sealedConflict();
      }
      if (current.file.status === "verified") {
        return fileCheckResultView(current.file);
      }
      const blobName = current.file.blob_name ?? firstBlobName(packageId, path);

      // Read and hash outside the transaction: large blobs take a while.
      const digest = await storageCall(request, "hash uploaded blob", () =>
        storage.digest(blobName),
      );

      const checked = await app.db.transaction(async (tx) => {
        const located = await locateFile(tx, packageId, path, true);
        if (located.packageStatus !== "uploading") {
          throw sealedConflict();
        }
        const file = located.file;
        if (file.status === "verified") {
          return file;
        }
        if ((file.blob_name ?? firstBlobName(packageId, path)) !== blobName) {
          throw new ProblemError(409, "upload_target_changed", {
            detail:
              "A new upload target was issued for this file during the check. Upload to it and report the file again.",
          });
        }
        const status = checkStatus(file, digest);
        const updated = await tx.query<FileRow>(
          `UPDATE package_files
              SET status = $3::text, actual_sha256 = $4, actual_bytes = $5, checked_at = now(),
                  verified_at = CASE WHEN $3::text = 'verified' THEN now() ELSE NULL END
            WHERE package_id = $1 AND path = $2
            RETURNING ${FILE_COLUMNS}`,
          [packageId, path, status, digest?.sha256 ?? null, digest?.bytes ?? null],
        );
        const row = updated.rows[0];
        if (row === undefined) {
          throw new Error("file check update matched no row");
        }
        await audit(
          request,
          status === "verified" ? "file.verify" : "file.reject",
          { type: "package", id: packageId },
          {
            path,
            blobName,
            status,
            expectedSha256: file.sha256,
            expectedBytes: file.bytes,
            ...(digest === undefined
              ? {}
              : { actualSha256: digest.sha256, actualBytes: digest.bytes }),
          },
          tx,
        );
        return row;
      });
      return fileCheckResultView(checked);
    },
  );

  // The seal body is stored byte for byte, so this route keeps the raw JSON body. The parser
  // override is encapsulated in this child context and applies to the seal route only.
  await app.register(async (scope) => {
    const rawBodies = new WeakMap<FastifyRequest, Buffer>();
    const parseJson = scope.getDefaultJsonParser("error", "error");
    scope.removeContentTypeParser("application/json");
    scope.addContentTypeParser("application/json", { parseAs: "buffer" }, (request, body, done) => {
      const raw = Buffer.isBuffer(body) ? body : Buffer.from(body);
      rawBodies.set(request, raw);
      parseJson(request, raw.toString("utf8"), done);
    });

    scope.post<{ Params: PackageIdParams; Body: Record<string, unknown> }>(
      "/packages/:packageId/seal",
      {
        config: { roles: UPLOAD_ROLES },
        schema: { params: packageIdParamsSchema, body: sealRequestSchema },
      },
      async (request, reply) => {
        const { packageId } = request.params;
        const raw = rawBodies.get(request);
        if (raw === undefined) {
          throw new Error("seal: raw body was not captured");
        }

        const validation = validateManifest(request.body);
        if (!validation.ok) {
          throw new ProblemError(422, "invalid_manifest", {
            detail: "The manifest does not match manifest.schema.json.",
            errors: validationErrors(validation.errors),
          });
        }
        const manifest: PackageManifest = validation.value;
        const manifestJson = JSON.stringify(manifest);

        const pkg = await selectPackage(app.db, packageId);
        if (pkg === undefined) {
          throw notFound("package_not_found", "No package with this packageId.");
        }
        if (pkg.status !== "uploading") {
          return resealOrConflict(app, reply, packageId, manifestJson);
        }

        const files = inDeclaredOrder(pkg, await selectFiles(app.db, packageId));
        const mismatches = manifestMismatchErrors(
          manifest,
          {
            packageId,
            visitId: pkg.visit_id,
            revision: pkg.revision,
            ...(pkg.supersedes_package_id === null
              ? {}
              : { supersedesPackageId: pkg.supersedes_package_id }),
          },
          files.map(declarationOf),
        );
        if (mismatches.length > 0) {
          throw new ProblemError(422, "manifest_mismatch", {
            detail:
              "The manifest must list exactly the files of the upload session with the same role, capture, SHA-256 and size.",
            errors: mismatches,
          });
        }

        const byPath = new Map(files.map((file) => [file.path, file]));
        const unverified = manifest.files.flatMap((entry, index) => {
          const file = byPath.get(entry.path);
          return file !== undefined && file.status !== "verified"
            ? [{ pointer: `/files/${index}`, message: `file is ${file.status}, not verified` }]
            : [];
        });
        if (unverified.length > 0) {
          throw new ProblemError(409, "files_not_verified", {
            detail: "Every file must be uploaded and verified before the package is sealed.",
            errors: unverified,
          });
        }

        const records = files.filter((file) => file.role === "capture_record");
        const recordFile = records[0];
        if (records.length !== 1 || recordFile === undefined) {
          throw new ProblemError(422, "capture_record_missing", {
            detail: "The package must contain exactly one capture_record file.",
          });
        }
        if (recordFile.bytes > MAX_CAPTURE_RECORD_BYTES) {
          throw new ProblemError(422, "invalid_capture_record", {
            detail: `The capture record is larger than ${MAX_CAPTURE_RECORD_BYTES} bytes.`,
          });
        }
        const recordBlob = await storageCall(request, "read capture record", () =>
          storage.read(
            recordFile.blob_name ?? firstBlobName(packageId, recordFile.path),
            MAX_CAPTURE_RECORD_BYTES,
          ),
        );
        if (
          recordBlob === undefined ||
          recordBlob.sha256 !== recordFile.sha256 ||
          recordBlob.bytes !== recordFile.bytes
        ) {
          request.log.error(
            { packageId, path: recordFile.path },
            "integrity: a verified capture record no longer matches its fingerprint",
          );
          throw new ProblemError(500, "integrity_error", {
            detail: "A verified file no longer matches its fingerprint.",
          });
        }
        let captureRecord: unknown;
        try {
          captureRecord = JSON.parse(recordBlob.data.toString("utf8"));
        } catch {
          throw new ProblemError(422, "invalid_capture_record", {
            detail: "The capture record file is not valid JSON.",
          });
        }
        const recordValidation = validateCaptureRecord(captureRecord);
        if (!recordValidation.ok) {
          throw new ProblemError(422, "invalid_capture_record", {
            detail: `The capture record does not match capture-record.schema.json: ${formatErrors(
              recordValidation.errors.slice(0, 10),
            ).replace(/\n/g, "; ")}`,
          });
        }

        const manifestBlob = manifestBlobName(packageId, manifest.visitId);
        try {
          await storageCall(request, "store manifest", () =>
            storage.createOnce(manifestBlob, raw, "application/json"),
          );
        } catch (error) {
          if (error instanceof BlobExistsError) {
            throw new ProblemError(409, "manifest_conflict", {
              detail: "A different manifest is already stored for this package.",
            });
          }
          throw error;
        }

        const manifestSha256 = sha256Hex(raw);
        const outcome = await app.db.transaction(async (tx) => {
          const locked = await tx.query<{ status: PackageStatus; same: boolean | null }>(
            `SELECT status, manifest = $2::jsonb AS same
               FROM packages WHERE package_id = $1 FOR UPDATE`,
            [packageId, manifestJson],
          );
          const row = locked.rows[0];
          if (row === undefined) {
            throw notFound("package_not_found", "No package with this packageId.");
          }
          if (row.status !== "uploading") {
            if (row.same === true) {
              return "already_sealed" as const;
            }
            throw new ProblemError(409, "package_sealed", {
              detail: "The package is already sealed with a different manifest.",
            });
          }
          const pending = await tx.query(
            `SELECT 1 FROM package_files WHERE package_id = $1 AND status <> 'verified' LIMIT 1`,
            [packageId],
          );
          if ((pending.rowCount ?? 0) > 0) {
            throw new ProblemError(409, "files_not_verified", {
              detail: "Every file must be uploaded and verified before the package is sealed.",
            });
          }
          await tx.query(
            `UPDATE packages
                SET status = 'checks_queued', manifest = $2::jsonb, manifest_sha256 = $3,
                    sealed_at = $4::timestamptz, registered_at = now(), capture_record = $5::jsonb
              WHERE package_id = $1`,
            [
              packageId,
              manifestJson,
              manifestSha256,
              manifest.sealedAt,
              JSON.stringify(recordValidation.value),
            ],
          );
          const job = await tx.query<{ job_id: string }>(
            `INSERT INTO jobs (type, package_id) VALUES ('checks', $1) RETURNING job_id`,
            [packageId],
          );
          await audit(
            request,
            "package.seal",
            { type: "package", id: packageId },
            {
              manifestSha256,
              manifestBlob,
              sealedAt: manifest.sealedAt,
              files: manifest.files.length,
              jobId: job.rows[0]?.job_id,
              status: "checks_queued",
            },
            tx,
          );
          return "sealed" as const;
        });

        return sendPackage(app, reply, packageId, outcome === "sealed" ? 202 : 200);
      },
    );
  });
}

async function resealOrConflict(
  app: FastifyInstance,
  reply: FastifyReply,
  packageId: string,
  manifestJson: string,
): Promise<FastifyReply> {
  const result = await app.db.query<{ same: boolean | null }>(
    `SELECT manifest = $2::jsonb AS same FROM packages WHERE package_id = $1`,
    [packageId, manifestJson],
  );
  if (result.rows[0]?.same !== true) {
    throw new ProblemError(409, "package_sealed", {
      detail: "The package is already sealed with a different manifest.",
    });
  }
  return sendPackage(app, reply, packageId, 200);
}
