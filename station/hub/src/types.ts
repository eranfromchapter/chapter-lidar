// HUB operations the station uses for publishing and for the property check.

/** A HUB sales deal with its confirmed property address. */
export interface HubDeal {
  /** HUB sales deal id (never a project record id). */
  readonly dealId: string;
  readonly projectName?: string;
  /** Single-line address exactly as shown by the HUB. */
  readonly address: string;
}

/** One document of a project's Files tab, as the document search returns it. */
export interface HubDocument {
  readonly name: string;
  /** Folder in the Files tab, when the HUB returns it. */
  readonly folder?: string;
  readonly documentId?: string;
}

export interface HubUpload {
  readonly dealId: string;
  /** Target folder, for example Capture/floor-1/<captureId>/r1. */
  readonly folder: string;
  /** File name shown in the Files tab. */
  readonly name: string;
  readonly contentType: string;
  readonly data: Uint8Array;
}

export interface HubUploadResult {
  /** HUB document id, when the upload response carries one. */
  readonly documentId?: string;
}

/** HUB access for the station worker. Implementations throw HubError. */
export interface HubApi {
  /** The deal with a confirmed address, or null when the HUB has none with this dealId. */
  getDeal(dealId: string): Promise<HubDeal | null>;
  /** Uploads one file into a folder of the deal's project Files tab. */
  uploadDocument(upload: HubUpload): Promise<HubUploadResult>;
  /** Documents of the deal's project whose name matches. */
  searchDocuments(dealId: string, name: string): Promise<readonly HubDocument[]>;
}

/** The little logging the publisher does (a pino-style logger fits). */
export interface HubLogger {
  info(details: Record<string, unknown>, message: string): void;
  warn(details: Record<string, unknown>, message: string): void;
}
