-- Up Migration
-- Shared trigger functions and contract value domains for every station table.
-- Domains mirror contract/schema (manifest.schema.json $defs) so the registry cannot hold a
-- value the contract rejects.

CREATE FUNCTION station_set_updated_at() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION station_set_updated_at() IS
  'BEFORE UPDATE trigger: sets updated_at to now().';

CREATE FUNCTION station_reject_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% on % is not allowed: the table is append-only', TG_OP, TG_TABLE_NAME
    USING ERRCODE = 'restrict_violation';
END;
$$;

COMMENT ON FUNCTION station_reject_change() IS
  'Trigger for append-only tables: rejects UPDATE, DELETE and TRUNCATE.';

-- HUB deal id, as returned by the HUB.
CREATE DOMAIN station_deal_id AS text
  CHECK (char_length(VALUE) BETWEEN 1 AND 64);

-- Lowercase hex SHA-256.
CREATE DOMAIN station_sha256 AS text
  CHECK (VALUE ~ '^[0-9a-f]{64}$');

-- Floor or area key of a capture, for example floor-1.
CREATE DOMAIN station_area_key AS text
  CHECK (char_length(VALUE) <= 64 AND VALUE ~ '^[a-z0-9]+(-[a-z0-9]+)*$');

-- Package-relative path: forward slashes, no leading or trailing slash, no empty, '.' or '..'
-- segments, no backslash or control characters U+0001-U+001F (text cannot hold U+0000).
CREATE DOMAIN station_relative_path AS text
  CHECK (
    char_length(VALUE) BETWEEN 1 AND 1024
    AND VALUE !~ '^/'
    AND VALUE !~ '//'
    AND VALUE !~ '/$'
    AND VALUE !~ '(^|/)\.{1,2}(/|$)'
    AND VALUE !~ '[\x01-\x1f\\]'
  );

-- Closed set of manifest file roles (manifest.schema.json $defs/role).
CREATE DOMAIN station_file_role AS text
  CHECK (VALUE IN (
    'capture_record',
    'raw_roomplan_json',
    'raw_depth',
    'capture_model',
    'plan_dxf',
    'rooms_csv',
    'plan_pdf',
    'spatial_report_pdf',
    'plan_png',
    'plan_svg',
    'mesh_glb',
    'mesh_obj',
    'mesh_mtl',
    'texture',
    'point_cloud_las',
    'photo',
    'field_controls'
  ));

-- Entra object id or display name of a person or service.
CREATE DOMAIN station_actor_id AS text
  CHECK (char_length(VALUE) BETWEEN 1 AND 128);

CREATE DOMAIN station_actor_name AS text
  CHECK (char_length(VALUE) BETWEEN 1 AND 200);
