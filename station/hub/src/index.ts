// @chapter/station-hub: HUB publishing for the station worker. The HUB client (upload,
// document search, deal lookup), the publication plan (folders, 45 MiB rule, station links), the
// verdict report PDF and HubPublisher (idempotent, retried, verified). The fake HUB for tests is
// in "@chapter/station-hub/fake".

export {
  HubError,
  MAX_ERROR_MESSAGE,
  publicationErrorOf,
  scrub,
  type HubFailure,
  type PublicationError,
} from "./errors.js";
export {
  ADDRESS_MAX_LENGTH,
  HUB_MAX_RESPONSE_BYTES,
  HUB_REQUEST_TIMEOUT_MS,
  HUB_UPLOAD_TIMEOUT_MS,
  LiveHubApi,
  type LiveHubApiOptions,
} from "./live.js";
export {
  DEAL_ID_MAX_LENGTH,
  HUB_PUBLISH_MAPPING,
  dealPath,
  isDealId,
  readItems,
  readPath,
  type HubPublishMapping,
} from "./mapping.js";
export {
  HUB_UPLOAD_ROLES,
  MANIFEST_CONTENT_TYPE,
  MAX_HUB_UPLOAD_BYTES,
  REPORT_CONTENT_TYPE,
  captureFolder,
  planPublication,
  reportName,
  stationLink,
  visitFolder,
  type PackageFileRecord,
  type PlanOptions,
  type PlannedFile,
  type PlannedLink,
  type PlannedUpload,
  type PublicationPlan,
  type PublishPackage,
} from "./plan.js";
export {
  DEFAULT_BASE_DELAY_MS,
  DEFAULT_MAX_ATTEMPTS,
  DEFAULT_MAX_DELAY_MS,
  HubPublisher,
  isRetryable,
  type HubPublisherOptions,
  type PublishRequest,
  type PublishResult,
} from "./publisher.js";
export {
  REPORT_NOT_CERTIFICATION,
  REPORT_TITLE,
  outcomeInPlainWords,
  pdfSafeText,
  renderVerdictReport,
  type ReportFile,
  type ReportFileLocation,
  type ReportInput,
} from "./report.js";
export {
  MemoryPublicationStore,
  fileKey,
  mergeFile,
  type PublicationState,
  type PublicationStatus,
  type PublicationStore,
  type PublishedFile,
} from "./store.js";
export type {
  HubApi,
  HubDeal,
  HubDocument,
  HubLogger,
  HubUpload,
  HubUploadResult,
} from "./types.js";
