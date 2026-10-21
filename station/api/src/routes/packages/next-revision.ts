// The phone's description of the next revision (OpenAPI putNextRevisionNotice,
// PUT /v1/packages/{packageId}/next-revision, capture and admin).
//
// While the operator prepares revision n+1 of a sealed package on the phone, the app sends
// what it adds, changes or removes (best effort, debounced; the app ignores failures). The
// station keeps the latest notice per package, with who sent it, and returns it as
// Package.nextRevision. Opening the upload session of the package that supersedes it removes
// the notice (uploads/index.ts), so a notice never outlives the revision it announces.
//
// Answers: 200 with the stored notice; 404 not_found; 409 package_not_sealed while the package
// is uploading; 409 revision_exists when a package superseding it exists; 422 revision_mismatch
// when the notice's revision is not the package's revision + 1. Every store is audited.
//
// Lock order with createUploadSession: both lock the superseded package's row (FOR UPDATE here,
// FOR SHARE there), so a notice is never stored after the superseding session removed it.

import type { FastifyInstance } from "fastify";
import { audit } from "../../core/audit.js";
import { requirePrincipal, type Role } from "../../core/auth.js";
import { ProblemError } from "../../core/problem.js";
import { isContractUuid, nextRevisionNoticeInputSchema, type PackageParams } from "./schemas.js";
import {
  noticeView,
  type NextRevisionChange,
  type NextRevisionNotice,
  type PackageStatus,
} from "./store.js";

export const NEXT_REVISION_ROLES: readonly Role[] = ["capture", "admin"];

/** PUT body (OpenAPI NextRevisionNoticeInput). */
export interface NextRevisionNoticeInput {
  revision: number;
  updatedAt: string;
  changes: NextRevisionChange[];
}

/** Only the documented change fields, in a fixed order. */
function normalizeChange(change: NextRevisionChange): NextRevisionChange {
  return {
    kind: change.kind,
    subject: change.subject,
    title: change.title,
    detail: change.detail,
    ...(change.answersNextAction === undefined
      ? {}
      : { answersNextAction: change.answersNextAction }),
    ...(change.method === undefined ? {} : { method: change.method }),
  };
}

export function registerNextRevisionRoutes(app: FastifyInstance): void {
  app.put<{ Params: PackageParams; Body: NextRevisionNoticeInput }>(
    "/packages/:packageId/next-revision",
    {
      config: { roles: NEXT_REVISION_ROLES },
      schema: { body: nextRevisionNoticeInputSchema },
    },
    async (request): Promise<NextRevisionNotice> => {
      const principal = requirePrincipal(request);
      const { packageId } = request.params;
      if (!isContractUuid(packageId)) {
        throw new ProblemError(404, "not_found", { detail: "No package with this id." });
      }
      const body = request.body;
      const notice = {
        revision: body.revision,
        updatedAt: body.updatedAt,
        changes: body.changes.map(normalizeChange),
      };

      await app.db.transaction(async (tx) => {
        const locked = await tx.query<{ status: PackageStatus; revision: number }>(
          "SELECT status, revision FROM packages WHERE package_id = $1 FOR UPDATE",
          [packageId],
        );
        const pkg = locked.rows[0];
        if (pkg === undefined) {
          throw new ProblemError(404, "not_found", { detail: "No package with this id." });
        }
        if (pkg.status === "uploading") {
          throw new ProblemError(409, "package_not_sealed", {
            detail: "The package is still uploading; describe its next revision once it is sealed.",
          });
        }
        const superseding = await tx.query(
          "SELECT 1 FROM packages WHERE supersedes_package_id = $1 LIMIT 1",
          [packageId],
        );
        if ((superseding.rowCount ?? 0) > 0) {
          throw new ProblemError(409, "revision_exists", {
            detail: "A package that supersedes this one is already registered.",
          });
        }
        if (notice.revision !== pkg.revision + 1) {
          throw new ProblemError(422, "revision_mismatch", {
            detail: "The notice describes another revision than the next one of this package.",
            errors: [
              { pointer: "/revision", message: `must be ${pkg.revision + 1} (revision + 1)` },
            ],
          });
        }
        await tx.query(
          `INSERT INTO next_revision_notices (package_id, notice, updated_by_id, updated_by_name)
           VALUES ($1, $2::jsonb, $3, $4)
           ON CONFLICT (package_id) DO UPDATE
             SET notice = EXCLUDED.notice, updated_by_id = EXCLUDED.updated_by_id,
                 updated_by_name = EXCLUDED.updated_by_name`,
          [packageId, JSON.stringify(notice), principal.userId, principal.name],
        );
        await audit(
          request,
          "package.next_revision",
          { type: "package", id: packageId },
          {
            revision: notice.revision,
            updatedAt: notice.updatedAt,
            changes: notice.changes.length,
          },
          tx,
        );
      });
      return noticeView(notice, principal.name);
    },
  );
}
