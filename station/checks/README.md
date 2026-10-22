# @chapter/station-checks

Station acceptance checks (F8). Runs the intake guide's "when the station receives the package"
checklist on one package and returns a contract `Verdict`: `ready`, `limited` or `blocked`. Every
finding names the file, the rule, the measured value and the next action. The verdict is an
automated check; it does not certify any model or measurement.

```ts
import { runChecks } from "@chapter/station-checks";
import { loadPackageFromDirectory } from "@chapter/station-checks/node";

const pkg = loadPackageFromDirectory("/path/to/package"); // or packageFromFiles(map) in memory
const verdict = runChecks(pkg, hubAddress, { evaluatedAt: "2026-10-17T16:00:00Z" });
```

`runChecks` is pure (no I/O, no clock). Pass `evaluatedAt`; it defaults to the manifest
`sealedAt`. `verdictId` defaults to a UUID derived from package, HUB address, time and rule set.
`packageFromFiles` throws `PackageLoadError` when there is no valid Chapter manifest.

Outcome rule: any blocker -> blocked; else any limitation -> limited; else ready.

The rule set is evaluator `chapter-capture-station/checks` 1.1.0 (13 rules; read by people as
"station-checks v1.1.0"). The verdict lists the rules in this table's order.

| #   | Rule id                 | Blocker                                                                                                     | Limitation                                                                                         |
| --- | ----------------------- | ----------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| 1   | `manifest.fingerprints` | listed file missing, or sha256/size differs                                                                 | (unlisted files are info)                                                                          |
| 2   | `files.parseable`       | file empty, or not readable as its role's format (JSON roles also schema-valid)                             |                                                                                                    |
| 3   | `property.address`      | address differs from the HUB address after normalization; no HUB address; files of another visit or capture |                                                                                                    |
| 4   | `units.scale`           | a control differs from the capture model by more than 3% of the control                                     | over max(1%, 25.4 mm) up to 3%; scale not verifiable (no controls, no model)                       |
| 5   | `orientation.up`        |                                                                                                             | GLB not +Y up or no horizontal floor; LAS Z extent vs ceiling; DXF not millimetres                 |
| 5b  | `orientation.compass`   |                                                                                                             | a capture's compass reading not verified (capture record 1.1.0); no next action                    |
| 6   | `companions.resolve`    | glTF geometry buffer missing or short                                                                       | glTF image, OBJ material library or MTL texture missing                                            |
| 7   | `dxf.content`           |                                                                                                             | mesh, surface, solid or point entities; no plan entities                                           |
| 8   | `las.header`            |                                                                                                             | version, point format, counts or extents differ from the data (point cloud is optional)            |
| 9   | `coverage.rooms`        |                                                                                                             | captured room without a labelled photo; omitted or inaccessible room                               |
| 10  | `geometry.plausibility` |                                                                                                             | ceiling outside 2.0-6.0 m, door width outside 0.6-1.5 m, sill below 0 (skipped when scale blocked) |
| 11  | `floors.registration`   |                                                                                                             | captures not linked by at least 2 shared landmarks: floor alignment not established                |
| 12  | `evidence.independence` |                                                                                                             | field controls recorded as derived from package files                                              |

Scale: the field control is the reference, `diff = |model - control|`, compared with
`capture-model.json` only (DXF, CSV and meshes are exports of the same capture, not independent
evidence). A control is matched to the extent of the rooms named at the start of its `from` and
`to` text (whole capture otherwise) along the capture's principal wall direction; axis A and B
take the perpendicular assignment with the smaller worst difference. Values are rounded to
1e-6 mm before comparison.

Compass (5b, compass spec 8.2): each capture of a capture record 1.1.0 is graded by the
contract's `compassState`, the evaluator the plan sheet, the spatial report and the web use. A
verified or approximate reading is info ("True north from the compass.", "North is
approximate."); any other is the limitation "Plan orientation is not verified; north is not
shown." with the reason as the measured value (a reading outside the scan names its time and the
scan's). The next action is None: a reading cannot be added to a finished scan, so the verdict
lists no next action for it. A capture scanned before the app read the compass has none of the
compass fields (`scannedBeforeCompass`): every capture of a capture record 1.0.0, and in a 1.1.0
record a capture carried over from a revision written before the compass, or scanned by a build
that does not read it (the app writes a reading or `headingIssue` for every capture it scans
with the compass). Owner question Q-B: with
`COMPASS_LIMITATION_FOR_LEGACY_RECORDS` false (the default) such a capture is not graded: a 1.0.0
record gets one info finding, "No compass reading recorded; orientation not verified" (the drawn
sample's wording, without a full stop), and each such capture of a 1.1.0 record the same finding
for that capture; the check is not applicable when no capture is graded, and the outcome is
unchanged. True grades those captures like the others (no compass reading), which makes every
package of an app before the compass, and every revision carrying such a floor over, Limited. No
capture record: not applicable, no finding.
