-- Up Migration
-- Revision n+1 reuses the verified files of revision n (carry-over), and the phone describes the
-- revision it is preparing (next-revision notice). Contract: OpenAPI 1.1.0 createUploadSession
-- (carry-over, supersedes_mismatch) and putNextRevisionNotice.
--
-- A carried-over file is inserted already verified: same declared values as the verified file
-- of the superseded package, its blob_name (so one blob may now back several packages; nothing
-- deletes blobs, and any future clean-up must count references) and its check result.

ALTER TABLE package_files
  ADD COLUMN carried_over_from uuid REFERENCES packages (package_id),
  ADD CONSTRAINT package_files_carried_over_verified
    CHECK (carried_over_from IS NULL OR status = 'verified'),
  ADD CONSTRAINT package_files_carried_over_not_self
    CHECK (carried_over_from IS DISTINCT FROM package_id);

CREATE INDEX package_files_carried_over_from_idx ON package_files (carried_over_from)
  WHERE carried_over_from IS NOT NULL;

COMMENT ON COLUMN package_files.carried_over_from IS
  'The superseded package (revision n-1) whose verified file this one reuses; NULL when uploaded.';

-- Same rules as 0003, plus: carried_over_from is part of a verified file's frozen state.
CREATE OR REPLACE FUNCTION station_package_files_guard() RETURNS trigger
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
       OR NEW.blob_name IS DISTINCT FROM OLD.blob_name
       OR NEW.carried_over_from IS DISTINCT FROM OLD.carried_over_from) THEN
    RAISE EXCEPTION 'file % of package % is verified and immutable', OLD.path, OLD.package_id
      USING ERRCODE = 'restrict_violation';
  END IF;

  RETURN NEW;
END;
$$;

-- The phone's description of the next revision of a sealed package, while the operator works on
-- it (best effort, replaced on every PUT). Removed when an upload session opens for a package
-- that supersedes package_id. notice is the NextRevisionNoticeInput as sent (revision,
-- updatedAt of the phone, changes); updated_by_* is the signed-in user who sent it.
CREATE TABLE next_revision_notices (
  package_id uuid PRIMARY KEY REFERENCES packages (package_id),
  -- COALESCE: a missing key makes jsonb_typeof NULL, and a CHECK that is NULL would pass.
  notice jsonb NOT NULL
    CONSTRAINT next_revision_notices_notice_object CHECK (COALESCE(
      jsonb_typeof(notice) = 'object'
      AND jsonb_typeof(notice -> 'changes') = 'array'
      AND jsonb_typeof(notice -> 'revision') = 'number', false)
    ),
  updated_by_id station_actor_id NOT NULL,
  updated_by_name station_actor_name,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER next_revision_notices_set_updated_at
  BEFORE UPDATE ON next_revision_notices
  FOR EACH ROW EXECUTE FUNCTION station_set_updated_at();

COMMENT ON TABLE next_revision_notices IS
  'Next revision a sealed package''s visit is preparing on the phone (Package.nextRevision).';
