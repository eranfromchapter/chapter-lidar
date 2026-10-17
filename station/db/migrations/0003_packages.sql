-- Up Migration
-- Intake packages (one row per package revision of a site visit) and their files.
--
-- A package is created by POST /packages (status uploading) with the manifest's file list and
-- sealed by POST /packages/{packageId}/seal, which stores the manifest and capture record.
-- What was declared or sealed never changes afterwards (guard triggers below).

CREATE TABLE packages (
  -- App-generated; the manifest's packageId.
  package_id uuid PRIMARY KEY,
  visit_id uuid NOT NULL,
  deal_id station_deal_id NOT NULL,
  revision integer NOT NULL CONSTRAINT packages_revision_positive CHECK (revision >= 1),
  -- packageId of the previous revision; not a foreign key because the previous revision may
  -- never have been uploaded to the station.
  supersedes_package_id uuid,
  status text NOT NULL DEFAULT 'uploading'
    CONSTRAINT packages_status_valid CHECK (
      status IN ('uploading', 'checks_queued', 'checking', 'verdict_ready', 'check_error')
    ),
  -- Upload session request body, kept to tell a resumed session (same body) from a conflict.
  session_request jsonb NOT NULL
    CONSTRAINT packages_session_request_object CHECK (jsonb_typeof(session_request) = 'object'),
  created_by_id station_actor_id NOT NULL,
  created_by_name station_actor_name,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  -- Set together at sealing.
  manifest jsonb,
  manifest_sha256 station_sha256,
  -- The manifest's sealedAt (when the phone sealed the package).
  sealed_at timestamptz,
  -- When the station accepted the seal.
  registered_at timestamptz,
  -- Parsed capture record file of the package.
  capture_record jsonb,
  CONSTRAINT packages_supersedes_rule
    CHECK ((revision = 1) = (supersedes_package_id IS NULL)),
  CONSTRAINT packages_supersedes_not_self
    CHECK (supersedes_package_id IS DISTINCT FROM package_id),
  CONSTRAINT packages_sealed_rule CHECK (
    (status = 'uploading') = (manifest IS NULL)
    AND (manifest IS NULL) = (manifest_sha256 IS NULL)
    AND (manifest IS NULL) = (sealed_at IS NULL)
    AND (manifest IS NULL) = (registered_at IS NULL)
  ),
  CONSTRAINT packages_manifest_object
    CHECK (manifest IS NULL OR jsonb_typeof(manifest) = 'object'),
  CONSTRAINT packages_capture_record_rule
    CHECK (capture_record IS NULL OR (manifest IS NOT NULL AND jsonb_typeof(capture_record) = 'object')),
  CONSTRAINT packages_visit_revision_key UNIQUE (visit_id, revision)
);

CREATE INDEX packages_deal_id_created_at_idx ON packages (deal_id, created_at DESC);
CREATE INDEX packages_status_idx ON packages (status) WHERE status <> 'verdict_ready';

CREATE TRIGGER packages_set_updated_at
  BEFORE UPDATE ON packages
  FOR EACH ROW EXECUTE FUNCTION station_set_updated_at();

CREATE FUNCTION station_packages_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status <> 'uploading' THEN
      RAISE EXCEPTION 'package % is sealed and cannot be deleted', OLD.package_id
        USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.package_id IS DISTINCT FROM OLD.package_id
     OR NEW.visit_id IS DISTINCT FROM OLD.visit_id
     OR NEW.deal_id IS DISTINCT FROM OLD.deal_id
     OR NEW.revision IS DISTINCT FROM OLD.revision
     OR NEW.supersedes_package_id IS DISTINCT FROM OLD.supersedes_package_id
     OR NEW.session_request IS DISTINCT FROM OLD.session_request
     OR NEW.created_by_id IS DISTINCT FROM OLD.created_by_id
     OR NEW.created_by_name IS DISTINCT FROM OLD.created_by_name
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'package % identity fields are immutable', OLD.package_id
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF OLD.manifest IS NOT NULL AND (
       NEW.manifest IS DISTINCT FROM OLD.manifest
       OR NEW.manifest_sha256 IS DISTINCT FROM OLD.manifest_sha256
       OR NEW.sealed_at IS DISTINCT FROM OLD.sealed_at
       OR NEW.registered_at IS DISTINCT FROM OLD.registered_at) THEN
    RAISE EXCEPTION 'package % is sealed: its manifest is immutable', OLD.package_id
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF OLD.capture_record IS NOT NULL
     AND NEW.capture_record IS DISTINCT FROM OLD.capture_record THEN
    RAISE EXCEPTION 'package % capture record is immutable once stored', OLD.package_id
      USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER packages_guard
  BEFORE UPDATE OR DELETE ON packages
  FOR EACH ROW EXECUTE FUNCTION station_packages_guard();

COMMENT ON TABLE packages IS
  'Intake packages: one row per package revision (packageId) of a site visit.';

CREATE TABLE package_files (
  package_id uuid NOT NULL REFERENCES packages (package_id),
  path station_relative_path NOT NULL,
  role station_file_role NOT NULL,
  capture_id uuid,
  area_key station_area_key,
  -- Declared by the app (manifest values).
  sha256 station_sha256 NOT NULL,
  bytes bigint NOT NULL CONSTRAINT package_files_bytes_nonnegative CHECK (bytes >= 0),
  status text NOT NULL DEFAULT 'pending'
    CONSTRAINT package_files_status_valid CHECK (
      status IN ('pending', 'verified', 'sha256_mismatch', 'bytes_mismatch', 'not_uploaded')
    ),
  -- Computed by the station from the stored blob at the last check.
  actual_sha256 station_sha256,
  actual_bytes bigint
    CONSTRAINT package_files_actual_bytes_nonnegative CHECK (actual_bytes >= 0),
  checked_at timestamptz,
  verified_at timestamptz,
  -- Name of the blob in the originals container.
  blob_name text
    CONSTRAINT package_files_blob_name_length
    CHECK (blob_name IS NULL OR char_length(blob_name) BETWEEN 1 AND 1024),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (package_id, path),
  CONSTRAINT package_files_capture_pair
    CHECK ((capture_id IS NULL) = (area_key IS NULL)),
  CONSTRAINT package_files_visit_role_rule
    CHECK ((role IN ('capture_record', 'field_controls')) = (capture_id IS NULL)),
  -- COALESCE: a CHECK that evaluates to NULL would pass, so unknown cases count as false.
  CONSTRAINT package_files_status_rule CHECK (COALESCE(
    CASE status
      WHEN 'pending' THEN checked_at IS NULL AND verified_at IS NULL
      WHEN 'verified' THEN
        actual_sha256 IS NOT NULL AND actual_bytes IS NOT NULL
        AND actual_sha256 = sha256 AND actual_bytes = bytes
        AND checked_at IS NOT NULL AND verified_at IS NOT NULL
      WHEN 'sha256_mismatch' THEN
        actual_sha256 IS NOT NULL AND actual_sha256 <> sha256 AND actual_bytes IS NOT NULL
        AND checked_at IS NOT NULL AND verified_at IS NULL
      WHEN 'bytes_mismatch' THEN
        actual_bytes IS NOT NULL AND actual_bytes <> bytes AND actual_sha256 IS NOT NULL
        AND checked_at IS NOT NULL AND verified_at IS NULL
      WHEN 'not_uploaded' THEN
        actual_sha256 IS NULL AND actual_bytes IS NULL
        AND checked_at IS NOT NULL AND verified_at IS NULL
    END, false)
  )
);

CREATE INDEX package_files_capture_idx ON package_files (package_id, capture_id)
  WHERE capture_id IS NOT NULL;

CREATE TRIGGER package_files_set_updated_at
  BEFORE UPDATE ON package_files
  FOR EACH ROW EXECUTE FUNCTION station_set_updated_at();

CREATE FUNCTION station_package_files_guard() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status = 'verified' THEN
      RAISE EXCEPTION 'verified file % of package % cannot be deleted', OLD.path, OLD.package_id
        USING ERRCODE = 'restrict_violation';
    END IF;
    RETURN OLD;
  END IF;

  IF NEW.package_id IS DISTINCT FROM OLD.package_id
     OR NEW.path IS DISTINCT FROM OLD.path
     OR NEW.role IS DISTINCT FROM OLD.role
     OR NEW.capture_id IS DISTINCT FROM OLD.capture_id
     OR NEW.area_key IS DISTINCT FROM OLD.area_key
     OR NEW.sha256 IS DISTINCT FROM OLD.sha256
     OR NEW.bytes IS DISTINCT FROM OLD.bytes
     OR NEW.created_at IS DISTINCT FROM OLD.created_at THEN
    RAISE EXCEPTION 'declared fields of file % of package % are immutable', OLD.path, OLD.package_id
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF OLD.status = 'verified' AND (
       NEW.status IS DISTINCT FROM OLD.status
       OR NEW.actual_sha256 IS DISTINCT FROM OLD.actual_sha256
       OR NEW.actual_bytes IS DISTINCT FROM OLD.actual_bytes
       OR NEW.checked_at IS DISTINCT FROM OLD.checked_at
       OR NEW.verified_at IS DISTINCT FROM OLD.verified_at
       OR NEW.blob_name IS DISTINCT FROM OLD.blob_name) THEN
    RAISE EXCEPTION 'file % of package % is verified and immutable', OLD.path, OLD.package_id
      USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER package_files_guard
  BEFORE UPDATE OR DELETE ON package_files
  FOR EACH ROW EXECUTE FUNCTION station_package_files_guard();

COMMENT ON TABLE package_files IS
  'Files of a package as declared in the upload session, with the server-side check result.';
