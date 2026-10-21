-- Up Migration
-- Read model of the review screen (web-review §9.1): what the package pages and lists need that
-- the registry did not keep.
--
-- - packages.field_controls: the package's field-controls file, parsed and contract-valid, stored
--   at sealing (NULL when the package has none or it does not match the contract; the checks
--   report that case). packages.manifest_bytes: size of the sealed manifest file. Both are
--   filled for packages sealed before this migration by scripts/backfill-review-read-model.ts,
--   and are immutable once set.
-- - Filling only these two columns is not a change of the package: updated_at stays, so the
--   "most recent change first" lists keep their order after the backfill.
-- - Indexes for the review lists (newest packages, decisions across packages, capture ids).

ALTER TABLE packages
  ADD COLUMN field_controls jsonb,
  ADD COLUMN manifest_bytes bigint,
  ADD CONSTRAINT packages_field_controls_rule CHECK (
    field_controls IS NULL OR (manifest IS NOT NULL AND jsonb_typeof(field_controls) = 'object')
  ),
  ADD CONSTRAINT packages_manifest_bytes_rule
    CHECK (manifest_bytes IS NULL OR (manifest IS NOT NULL AND manifest_bytes >= 0));

COMMENT ON COLUMN packages.field_controls IS
  'Field-controls file of the package, parsed at sealing (contract-valid only).';
COMMENT ON COLUMN packages.manifest_bytes IS 'Size in bytes of the sealed manifest file.';

-- Same rules as 0003, plus: field_controls and manifest_bytes are set once.
CREATE OR REPLACE FUNCTION station_packages_guard() RETURNS trigger
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

  IF OLD.field_controls IS NOT NULL
     AND NEW.field_controls IS DISTINCT FROM OLD.field_controls THEN
    RAISE EXCEPTION 'package % field controls are immutable once stored', OLD.package_id
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF OLD.manifest_bytes IS NOT NULL
     AND NEW.manifest_bytes IS DISTINCT FROM OLD.manifest_bytes THEN
    RAISE EXCEPTION 'package % manifest size is immutable once stored', OLD.package_id
      USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

CREATE FUNCTION station_packages_set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF (NEW.field_controls IS DISTINCT FROM OLD.field_controls
      OR NEW.manifest_bytes IS DISTINCT FROM OLD.manifest_bytes)
     AND (to_jsonb(NEW) - ARRAY['field_controls', 'manifest_bytes', 'updated_at'])
       = (to_jsonb(OLD) - ARRAY['field_controls', 'manifest_bytes', 'updated_at']) THEN
    NEW.updated_at := OLD.updated_at;
  ELSE
    NEW.updated_at := now();
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION station_packages_set_updated_at() IS
  'BEFORE UPDATE trigger of packages: sets updated_at to now(), except when only the review read model columns change.';

DROP TRIGGER packages_set_updated_at ON packages;
CREATE TRIGGER packages_set_updated_at
  BEFORE UPDATE ON packages
  FOR EACH ROW EXECUTE FUNCTION station_packages_set_updated_at();

CREATE INDEX packages_created_at_idx ON packages (created_at DESC, revision DESC);
CREATE INDEX package_files_capture_id_idx ON package_files (capture_id)
  WHERE capture_id IS NOT NULL;
CREATE INDEX modeling_decisions_decided_at_idx
  ON modeling_decisions (decided_at DESC, decision_id DESC);
