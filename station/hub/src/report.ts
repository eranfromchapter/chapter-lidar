// The station's report PDF is the spatial report (station/hub/src/report/): this module keeps
// the import path of the v1 verdict report for the publisher and older callers.

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
} from "./report/index.js";
