// Package read routes (contract/openapi/station.yaml):
//
//   GET /v1/packages?dealId&visitId          listPackages   capture, bim, admin
//   GET /v1/packages/{packageId}             getPackage     capture, bim, admin
//   GET /v1/packages/{packageId}/verdict     getVerdict     capture, bim, admin
//   GET /v1/packages/{packageId}/files/download?path=
//                                            getFileDownloadLink   bim, admin
//
// Reads only: nothing here writes the registry. The one exception to "nothing is audited" is
// the download link: every link handed out is audited (download.ts). A packageId that is not a
// contract UUID is answered 404 (these operations document no 400 for it).

import { validateVerdict } from "@chapter/capture-contract";
import type { FastifyInstance } from "fastify";
import { ProblemError } from "../../core/problem.js";
import { DOWNLOAD_ROLES, issueDownloadLink } from "./download.js";
import {
  fileDownloadQuerySchema,
  isContractUuid,
  listPackagesQuerySchema,
  type FileDownloadQuery,
  type ListPackagesQuery,
  type PackageParams,
} from "./schemas.js";
import { getPackage, getVerdict, listPackages } from "./store.js";

const READ_ROLES = ["capture", "bim", "admin"] as const;

function packageNotFound(): ProblemError {
  return new ProblemError(404, "not_found", { detail: "No package with this id." });
}

export default async function packageRoutes(app: FastifyInstance): Promise<void> {
  app.get<{ Querystring: ListPackagesQuery }>(
    "/packages",
    { config: { roles: READ_ROLES }, schema: { querystring: listPackagesQuerySchema } },
    async (request) => {
      const { dealId, visitId } = request.query;
      return { packages: await listPackages(app.db, dealId, visitId) };
    },
  );

  app.get<{ Params: PackageParams }>(
    "/packages/:packageId",
    { config: { roles: READ_ROLES } },
    async (request) => {
      const { packageId } = request.params;
      if (!isContractUuid(packageId)) {
        throw packageNotFound();
      }
      const found = await getPackage(app.db, packageId);
      if (found === undefined) {
        throw packageNotFound();
      }
      return found;
    },
  );

  app.get<{ Params: PackageParams }>(
    "/packages/:packageId/verdict",
    { config: { roles: READ_ROLES } },
    async (request) => {
      const { packageId } = request.params;
      if (!isContractUuid(packageId)) {
        throw packageNotFound();
      }
      const stored = await getVerdict(app.db, packageId);
      if (stored === undefined) {
        throw packageNotFound();
      }
      if (stored.status !== "verdict_ready" || stored.document === undefined) {
        throw new ProblemError(404, "verdict_not_ready", {
          detail: `The acceptance checks have not finished (package status ${stored.status}).`,
        });
      }
      // The verdict is written by the checks worker, not by this service: never serve a
      // document that breaks the contract.
      const checked = validateVerdict(stored.document);
      if (!checked.ok) {
        request.log.error(
          { packageId, errors: checked.errors.slice(0, 5).map((e) => e.instancePath || "/") },
          "stored verdict does not match the contract",
        );
        throw new ProblemError(500, "internal_error", {
          detail: "The station could not complete the request.",
        });
      }
      return checked.value;
    },
  );

  app.get<{ Params: PackageParams; Querystring: FileDownloadQuery }>(
    "/packages/:packageId/files/download",
    { config: { roles: DOWNLOAD_ROLES }, schema: { querystring: fileDownloadQuerySchema } },
    async (request) => issueDownloadLink(request, request.params.packageId, request.query.path),
  );
}
