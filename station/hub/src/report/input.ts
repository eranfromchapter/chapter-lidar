// What the spatial report is made from and what rendering it returns.

import type {
  CaptureMode,
  CaptureModel,
  CaptureRecord,
  FieldControls,
  PhotoDirection,
  PhotoSubject,
  Verdict,
} from "@chapter/capture-contract";

/** Where one file of the package is after publishing. */
export type ReportFileLocation =
  | { readonly kind: "hub"; readonly folder: string; readonly name: string }
  | {
      readonly kind: "link";
      readonly url: string;
      readonly reason: "too_large" | "not_published";
    };

export interface ReportFile {
  readonly path: string;
  readonly role: string;
  readonly bytes: number;
  readonly sha256: string;
  readonly location: ReportFileLocation;
}

/** The capture model of one floor (capture) as the loader found it. */
export type ReportModel =
  | { readonly status: "ok"; readonly model: CaptureModel }
  | { readonly status: "absent" }
  | { readonly status: "unreadable" };

/** One floor or area of the visit, in capture-record order. */
export interface ReportFloorSource {
  readonly captureId: string;
  readonly areaKey: string;
  readonly model: ReportModel;
}

/** A site photo with its manifest labels and the reduced image (undefined: undecodable). */
export interface ReportPhoto {
  readonly path: string;
  readonly captureId?: string;
  readonly areaKey?: string;
  readonly room: string;
  readonly direction: PhotoDirection;
  readonly subject: PhotoSubject;
  readonly takenAt: string;
  /** Reduced JPEG (356 x 444 px, no metadata); undefined when the photo could not be read. */
  readonly image?: Uint8Array;
}

export interface SpatialReportInput {
  readonly verdict: Verdict;
  readonly packageId: string;
  readonly dealId: string;
  readonly captureRecord?: CaptureRecord;
  /** Where this report itself is filed in the HUB. */
  readonly reportLocation: { readonly folder: string; readonly name: string };
  readonly files: readonly ReportFile[];
  /** Largest uploaded size, for the explanation of linked files. */
  readonly maxUploadBytes: number;
  /** Web review base URL (REVIEW_BASE_URL): the QR code and "Review link" open the package. */
  readonly reviewBaseUrl: string;
  /** IANA zone of printed dates and times (REPORT_TIME_ZONE). Default America/New_York. */
  readonly timeZone?: string;
  /** Manifest sealedAt. */
  readonly sealedAt?: string;
  /** Number of manifest entries. Default: files.length minus the manifest itself. */
  readonly manifestFileCount?: number;
  /**
   * The floors with their capture models. Default: the capture record's captures with their
   * models absent.
   */
  readonly floors?: readonly ReportFloorSource[];
  /** Field controls; "invalid" when the file is present but does not match the contract. */
  readonly fieldControls?: FieldControls | "invalid";
  readonly photos?: readonly ReportPhoto[];
  /** True when the photo pages were left out for the size limit. */
  readonly photosOmitted?: boolean;
}

/** Kept for the F9 tests and callers of the v1 report. */
export type ReportInput = SpatialReportInput;

/** Per-floor figures the report computed, stored by the worker (spatial_reports.floors). */
export interface ReportFloor {
  readonly captureId: string;
  readonly areaKey: string;
  readonly roomsScanned: number;
  readonly roomsUnlabeled: number;
  /** Sum of the rooms' floor areas, square feet, rounded to 0.1 once. */
  readonly floorAreaSqFt: number;
}

export interface RenderedReport {
  readonly bytes: Buffer;
  readonly sha256: string;
  readonly pages: number;
  /** First capture checks page. */
  readonly checksPage: number;
  /** First package record page. */
  readonly recordPage: number;
  /** spatial-report-{verdictId}.pdf */
  readonly name: string;
  readonly floors: readonly ReportFloor[];
}

export type { CaptureMode };
