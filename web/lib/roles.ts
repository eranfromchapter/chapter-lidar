// Station app roles (contract/openapi/station.yaml securitySchemes.entra) and what each may do
// in the review screen. The station enforces the same roles on every call; these checks gate
// the UI and the server-side entry points (server actions and route handlers).

export const STATION_ROLES = ["capture", "bim", "admin"] as const;
export type StationRole = (typeof STATION_ROLES)[number];

/** Known station roles from a `roles` claim value. Unknown values are dropped. */
export function rolesFrom(value: unknown): StationRole[] {
  if (!Array.isArray(value)) {
    return [];
  }
  return STATION_ROLES.filter((role) => value.includes(role));
}

/** bim and admin may download files, preview plans and read or log modeling decisions. */
export function canReview(roles: readonly StationRole[]): boolean {
  return roles.includes("bim") || roles.includes("admin");
}

/** True when the user has any station role at all. */
export function hasStationAccess(roles: readonly StationRole[]): boolean {
  return roles.length > 0;
}

/** Role shown next to the signed-in name in the header. */
export function roleLabel(roles: readonly StationRole[]): string {
  if (roles.includes("admin")) {
    return "Admin";
  }
  if (roles.includes("bim")) {
    return "BIM operator";
  }
  if (roles.includes("capture")) {
    return "Capture operator";
  }
  return "No station role";
}
