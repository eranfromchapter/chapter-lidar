-- Up Migration
-- The station's spatial report of each package's current verdict (the PDF itself is in the
-- `reports` blob container). One row per package; a new verdict replaces the row, older blobs
-- stay. Written by the worker after the checks (onReportRendered); read by the API
-- (GET /packages/{packageId}/spatial-report and PackageSummary.report).
--
-- verdict_id has no foreign key: re-running the checks replaces the package's verdict row, and
-- the API serves the report only while verdict_id is the current verdict. floors holds the
-- per-capture totals the report computed (ReportFloor: captureId, areaKey, roomsScanned,
-- roomsUnlabeled, floorAreaSqFt), in capture-record order.

CREATE TABLE spatial_reports (
  package_id uuid PRIMARY KEY REFERENCES packages (package_id),
  verdict_id uuid NOT NULL,
  file_name text NOT NULL
    CONSTRAINT spatial_reports_file_name_valid
    CHECK (file_name ~ '^spatial-report-[0-9a-f-]{36}\.pdf$'),
  blob_name text NOT NULL
    CONSTRAINT spatial_reports_blob_name_length CHECK (char_length(blob_name) BETWEEN 1 AND 1024),
  sha256 station_sha256 NOT NULL,
  bytes bigint NOT NULL CONSTRAINT spatial_reports_bytes_positive CHECK (bytes > 0),
  pages integer NOT NULL CONSTRAINT spatial_reports_pages_positive CHECK (pages >= 1),
  checks_page integer NOT NULL
    CONSTRAINT spatial_reports_checks_page_positive CHECK (checks_page >= 1),
  floors jsonb NOT NULL CONSTRAINT spatial_reports_floors_array CHECK (jsonb_typeof(floors) = 'array'),
  -- = the verdict's evaluatedAt.
  generated_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT spatial_reports_file_name_matches_verdict
    CHECK (file_name = 'spatial-report-' || verdict_id::text || '.pdf'),
  CONSTRAINT spatial_reports_checks_page_in_report CHECK (checks_page <= pages)
);

CREATE TRIGGER spatial_reports_set_updated_at
  BEFORE UPDATE ON spatial_reports
  FOR EACH ROW EXECUTE FUNCTION station_set_updated_at();

COMMENT ON TABLE spatial_reports IS 'Spatial report PDF of each package''s current verdict.';
