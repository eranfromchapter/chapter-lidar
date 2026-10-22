// @chapter/station-hub: HUB publishing for the station worker. The HUB client (upload,
// document search, deal lookup), the publication plan (folders, 45 MiB rule, station links), the
// station's spatial report PDF and HubPublisher (idempotent, retried, verified). The fake HUB
// for tests is in "@chapter/station-hub/fake".

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
  SPATIAL_REPORT_ROLE,
  isRetryable,
  reportFilesOf,
  type HubPublisherOptions,
  type PublishRequest,
  type PublishResult,
} from "./publisher.js";
export {
  REPORT_NOT_CERTIFICATION,
  REPORT_STATEMENT_CHECKS,
  REPORT_STATEMENT_FULL,
  REPORT_STATEMENT_SHORT,
  REPORT_TITLE,
  coverSentence,
  outcomeInPlainWords,
  pdfSafeText,
  renderSpatialReport,
  renderVerdictReport,
  type RenderedReport,
  type ReportFile,
  type ReportFileLocation,
  type ReportFloor,
  type ReportInput,
  type SpatialReportInput,
} from "./report.js";
export { DEFAULT_REPORT_TIME_ZONE, isTimeZone } from "./report/format.js";
export type { ReportFloorSource, ReportModel, ReportPhoto } from "./report/input.js";
export { PHOTO_FULL, PHOTO_SMALL, reducePhoto } from "./report/photos.js";
export {
  PHOTO_BUDGET_BYTES,
  loadReportSources,
  type ReportSources,
  type SourceFile,
  type SourceRequest,
} from "./report/sources.js";
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
