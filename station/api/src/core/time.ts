// Contract timestamps: UTC, whole seconds, RFC 3339 with Z (2026-10-17T14:02:11Z).

/** Formats a date as a contract DateTime, truncating to whole seconds. */
export function toApiDateTime(date: Date): string {
  if (Number.isNaN(date.getTime())) {
    throw new RangeError("invalid date");
  }
  return date.toISOString().replace(/\.\d{3}Z$/, "Z");
}
