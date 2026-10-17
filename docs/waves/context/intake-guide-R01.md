Prepared for Chapter sales representatives, capture teams, BIM operators and designers. This guide defines a recommended intake package and explains the source files documented in our previous project work. It does not certify any property model or measurement.

For a new project, request the capture details, available plan exports, one complete 3D mesh package, and separate site photographs. Add a point cloud when detailed scan comparison is needed. The exact package depends on the capture mode, available exports and project scope.

The package to request

1 Capture details. Property address, project ID, floor or area, Polycam link and capture ID, capture owner, capture date, device, capture mode, units and coverage notes. Obtain the original downloads as well as the viewer link.

2 Plans and measurements. When floorplan data is available, request the DXF, room measurement CSV, plan PDF and separate Spatial Report PDF. PNG or SVG plans help with quick review. Record missing exports rather than assuming every capture includes them.

3 A complete 3D mesh. Request one original GLB, glTF package, or OBJ package. Keep any accompanying geometry, material and texture files together. We do not need every mesh format for each job.

4 Site photographs and field controls. Collect labeled room and detail photographs separately, plus independently checked dimensions and levels. These support interpretation, renderings and verification of the model.

5 A point cloud when required. For detailed comparison with scan geometry, request LAS when available. Existing LAZ or other exports can be evaluated, but the installed conversion route must be checked before promising a Revit link.

What this enables

The package supports preliminary existing condition plans, editable Revit reconstruction, client design options and visual presentations. A mesh or linked point cloud is reference geometry. Native walls, doors, rooms and building systems still require modeling and review.

Permit preparation follows the agreed project workflow. Scan exports alone do not establish concealed conditions, structural capacity, field accuracy or a complete submission package.

File types and their roles

The status below is Chapter’s recommended request priority. Availability must be checked for the actual capture and account. File extensions alone do not establish what the geometry represents.

A mesh describes surfaces using small faces. A point cloud stores points in 3D space. Both can guide reconstruction; neither is automatically an editable building model.

  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  File or package                   When to request                      How Chapter uses it
  --------------------------------- ------------------------------------ -----------------------------------------------------------------------------------------------------------------------------------------------------------------
  Capture link and record           Every capture                        Find the correct source; track floor, owner, dates, settings, units and gaps. A link alone is not a complete archive.

  DXF floorplan                     When floorplan data exists           Extract or link vector plan geometry for walls, rooms and openings. Inspect whether the DXF contains a plan, mesh or points.

  CSV measurements                  With available plan data             Cross-check room labels, dimensions and reported areas. Reported floor area is not a verified construction quantity.

  Plan PDF and Spatial Report PDF   With available plan data             Readable plan reference plus a separate room report. A report may contain measurements and recognized objects; it is not a photo survey. [2]

  GLB or glTF package               Preferred 3D source when available   Review three-dimensional geometry and visual context. Keep glTF BIN and image companions. Check whether the export is a simplified plan model or textured mesh.

  OBJ plus MTL and textures         Alternative complete mesh            Review or convert geometry for supported applications. Keep original names and relative paths so material references survive.

  LAS or evaluated alternative      When scan comparison is needed       Index a suitable point cloud for Revit. LAZ needs a validated route; PTS and XYZ are alternatives. Identify point-cloud PLY versus splat PLY before use.

  JPG or PNG site photographs       Every site visit where practical     Record rooms, finishes, openings, ceilings and relevant equipment. Plan images and small material textures cannot replace these photographs.

  PNG or SVG plan previews          Supporting reference                 Fast visual review and annotations. Use richer geometric sources for reconstruction when available.
  ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

RVT, RCP and RCS are downstream working files in this process. Read AI transcripts, surveys and earlier drawings are separate inputs with their own source records. E57 is not currently listed as a supported Polycam export. [1]

How the files move through the workflow

1 Intake and source preservation

Archive the original download or ZIP without renaming its internal companions. Register each capture separately, then create working copies for extraction and conversion. Record export dates, processing versions where available, and file fingerprints so later changes can be traced.

2 Existing condition reconstruction in Revit

Use plan DXF and CSV to interpret room boundaries and plan dimensions. Use the 3D source to investigate heights, openings and visible objects. Compare those interpretations with photographs and independent field measurements before relying on them for design. Geometry may be reconstructed as native Revit elements or linked as a reference; the project record must state which occurred.

PDF geometry can support preliminary reconstruction when richer data is unavailable, as in some earlier projects. Check the drawing scale and document assumptions. Do not assign more accuracy to a model simply because it has been converted into Revit.

3 Point cloud route when needed

LAS or another supported and validated source → ReCap indexing → RCP with its referenced RCS files → Revit point cloud link. Revit 2027 documents RCP and RCS for indexed cloud insertion. Keep all linked files together during handoff. [4, 5]

Autodesk’s current ReCap table lists LAS, PTS and XYZ, but does not list LAZ or PLY. Validate the installed version or use a checked conversion. Keep the original, record the conversion, and compare point counts, extents, units and positioning. An exported point cloud may be derived from mesh data; do not label it raw sensor data without provenance. [3, 4]

4 Client design and presentation

Use the reviewed Revit model as the basis for proposed plans and BIM-linked presentations. Original scan meshes and photographs support existing condition review. Renderings also need intentional materials, lighting, furnishings and cameras. A scan texture or a generated design image does not establish an approved material specification.

Revit exports, presentation GLBs, Datasmith files and rendered images are derived outputs. Label their model revision and purpose. HUB and AIDM publication depends on the project’s configured and tested connections; possession of a GLB does not confirm those connections.

5 Design and construction updates

When client discussions change the scope, update the decision record and model revision. Capture changed site conditions when necessary. Issue subcontractor drawings, quantities, specifications and translated instructions from the reviewed project model and approved scope, with original scan evidence retained for traceability.

Capture and acceptance checklist

The sales or capture team supplies the sources. The BIM operator checks the package and records gaps. Field verification and professional review remain assigned project responsibilities. The following checks are recommended for each intake.

Before leaving the property

• Confirm the address and label every floor or area. Record omitted rooms, inaccessible spaces, obscured surfaces and separate exterior captures.

• Photograph each room and relevant details: openings, ceiling changes, cabinetry, fixtures, equipment and visible defects. Label the room and viewing direction. Avoid collecting unrelated personal information.

• Record independent controls appropriate to the scope. A practical starting set includes two long perpendicular distances on each floor, ceiling heights, relevant opening dimensions, floor-to-floor levels and shared landmarks between captures.

• Note the device, capture mode, date and operator. Verify that the intended exports and any original photographs are available before relying on the capture for later work.

When the station receives the package

• Open the files and check that they are nonempty and belong to the correct property and floor. Resolve any automatically generated address that conflicts with the confirmed project address.

• Check units, scale, up direction and orientation against known measurements. Register floors using shared controls; separate capture origins are not evidence of correct floor alignment.

• Verify that geometry covers the requested area, openings and heights are plausible, and mesh companion files resolve. Identify simplified geometry, reconstructed objects and uncertain surfaces.

• Record the source used for each modeling decision, the remaining uncertainty and the next verification action. Multiple exports from one capture can agree without providing an independent measurement.

If something is missing

Record one of three outcomes: ready for the stated preliminary task; usable with named limitations; or missing information prevents that task. Continue work that the available evidence supports, and request targeted measurements, photos, exports or recapture for the affected areas.

For LiDAR Space and Floorplan captures, Polycam documents original-device and Developer Mode restrictions on image access. Do not assume that photographs can be recovered later. Separate site photography is the dependable intake practice. [1, 6]

Files documented in our previous projects

These examples describe recorded source use. They distinguish original Polycam material from files produced later by Chapter. They are not statements that each project reached construction or submission readiness. Project names link to the local evidence records.

  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Project                      Sources used                                                     What the records establish
  ---------------------------- ---------------------------------------------------------------- -----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
  7360 SW 109 Terrace          Spatial Report PDF, supplied photographs and earlier plan PDF.   PDF vectors supported derived geometry and native Revit reconstruction. Original raw Polycam mesh or cloud use was not documented.

  1500 Bay Road 1462           Plan DXF, OBJ, LAZ, with CSV and PDF support.                    Original plan DXF and OBJ-derived 3D DXF were linked. LAZ → ReCap RCP/RCS → linked cloud. This was a reference starter, not completed native architectural BIM.

  131 East 81st Street Apt 9   OBJ ZIP with MTL and small PNG material assets.                  Corrected orientation and linked mesh reference in Revit. Tiny texture assets were not site photographs.

  618 Valley Street            Three original GLBs, room CSV and PDF reports.                   GLB geometry supported schematic walls, floors, openings and objects. Later mesh files were derived outputs.

  204 High Avenue              Two Polycam PDF reports and annotated plan PNGs.                 Calibrated report geometry supported native wall and opening reconstruction. Raw mesh or cloud inspection was not recorded.

  19 Ash Street                Viewer glTF, geometry BIN and JPEG textures for the exterior.    Blender reference and reconstruction work. Native Revit completion and independently verified scale were not established in the reviewed record.

  24 Shawnee Road              Original DXF and GLB, CSV, reports and plan PDFs.                Primary geometry supported native Revit reconstruction. A first-floor LAZ was header-checked only, not linked. Usable original room photographs and inter-floor controls remained gaps.
  ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

Other test material included supplied IFC models and synthetic Revit transfer fixtures. These should not be counted as additional projects modeled from original Polycam exports.

Request text and reference sources

Message for the sales or capture team

Please provide the Polycam package for the confirmed property address, with each floor or area labeled separately. Include the capture link and ID, capture date, operator, device, mode, units and any missing areas. Download the available DXF, CSV, plan PDF and Spatial Report. Include one complete original 3D mesh package: GLB, glTF with companions, or OBJ with MTL and textures. If detailed scan comparison is required, include LAS or the point-cloud export already available, and identify its format. Preserve the original ZIP and internal filenames. Also provide labeled site photographs and independently checked dimensions, ceiling heights and floor-to-floor controls. List anything unavailable rather than substituting a screenshot or unrelated export.

Suggested project folder structure

Keep separate folders for Original Polycam Exports, Site Photos, Field Measurements, Source Register, Working Conversions and Issued Outputs. Within the original export folder, group by floor and capture ID. Keep untouched packages separate from later Revit, GLB and presentation outputs.

Official documentation

Checked 17 October 2026. Vendor features and entitlements may change. These references support the format and conversion notes; Chapter’s intake checklist is a recommended working practice.

1 Polycam export formats and mode restrictions

2 Polycam Spatial Report contents and generation

3 Polycam API export formats and artifact definitions

4 Autodesk ReCap supported import and export formats

5 Autodesk Revit 2027 point cloud insertion

6 Polycam Polyform raw data guidance

Using this guide

Apply the checklist to the intended task and record exceptions. An accepted preliminary intake is not acceptance of all measurements or permission to issue final drawings. Reassess the sources when new captures, field checks or client decisions change the project.
