// Package data shared by the package detail and decision log pages.

import type { Verdict } from "@chapter/capture-contract";
import type { StationClient } from "./station";
import type { StationPackage } from "./station-types";

export interface PackageBase {
  readonly pkg: StationPackage;
  /** Property address: the capture record's, else the HUB project's. */
  readonly address: string;
}

/** The package and its address. Station errors (404, 403, ...) propagate. */
export async function loadPackageBase(
  station: StationClient,
  packageId: string,
): Promise<PackageBase> {
  const pkg = await station.getPackage(packageId);
  const address =
    pkg.captureRecord?.address.formatted ??
    (await station.getProject(pkg.dealId)).address.formatted;
  return { pkg, address };
}

/** The verdict once the package reports verdict_ready; null while checks are pending. */
export async function loadVerdict(
  station: StationClient,
  pkg: StationPackage,
): Promise<Verdict | null> {
  if (pkg.status !== "verdict_ready") {
    return null;
  }
  return station.getVerdict(pkg.packageId);
}
