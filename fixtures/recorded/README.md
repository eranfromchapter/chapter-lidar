# Recorded fixtures

**Status: EMPTY. No real recording is committed yet.** This folder stays empty until the one
human recording scan has been made. Only the `.gitkeep` file is tracked here. Do not add
placeholder or sample scans.

## Purpose

The synthetic fixtures in `fixtures/generator/` are the main test data. This folder is for one
real scan, made with the debug build on a real device, so the RoomPlan and depth readers can be
checked against real output.

## Who and what

- One person, one iPhone Pro with LiDAR, one build of Chapter Capture with the debug build
  options on.
- One simple rectangular room: four straight walls, a flat ceiling, no stairs, no arches, no
  sloped ceiling. An empty bedroom or a plain bathroom is a good choice.
- Use a neutral room label. Do not use a property address, client name, project name or
  person's name in the folder name, the files or the PR.

## Steps

1. **Measure first, with a steel tape, before any scan.** Write these values in millimetres on
   paper:
   - Distance A: the longest wall-to-wall distance at floor level, along one wall.
   - Distance B: the longest wall-to-wall distance at floor level, along a wall that meets wall A
     at a right angle.
   - Ceiling height: floor to ceiling, measured near the middle of the room.
2. **Measure A and B twice each.** The two readings must match within 5 mm. If they do not, measure
   again. Do not use a phone measuring app for these values.
3. **Start a new capture** in the debug build for the room, with the neutral room label from above.
4. **Walk the room slowly** along the walls, then point the phone at the ceiling and at each corner.
   Keep the room lit. Keep the phone steady.
5. **Stop the scan** when all four walls and the ceiling have been captured.
6. **Tap "Export raw originals"** in the debug build. Wait until the export has finished.
7. **Move the exported folder to your laptop** by AirDrop or cable. Do not send it through Slack,
   email or a shared drive.
8. **Check that the folder holds exactly the four files below.** The names are fixed. If the
   debug build writes other names, fix the build, not the names here.

   | File                  | Source       | Content                                                       |
   | --------------------- | ------------ | ------------------------------------------------------------- |
   | `raw-roomplan.json`   | debug export | Raw RoomPlan `CapturedRoom` JSON (Codable)                    |
   | `depth-samples.bin`   | debug export | Depth samples from the scan, binary                           |
   | `camera-poses.json`   | debug export | Camera intrinsics and per-frame camera poses                  |
   | `field-controls.json` | you, by hand | The three tape values from step 1, method `tape`, millimetres |

9. **Write `field-controls.json` by hand** with the three tape values from step 1 and method
   `tape`. Check the file against the field-controls schema in `contract/schema/` before you copy
   it into the folder.
10. **Remove personal information.** Open `raw-roomplan.json` and `camera-poses.json` in a text
    editor. Remove any address, person's name, email address, phone number or device owner name.
    Make no other edits. If you cannot remove an item, stop and ask. Do not commit the folder.
    Do not add photos, screenshots, logs or any other file.
11. **Copy the folder into this directory** and name it `<yyyy-mm-dd>-<room-slug>`, where the date
    is the scan date and the slug uses lowercase letters, digits and hyphens only. Example:
    `fixtures/recorded/2026-11-03-bedroom-a/`.
12. **Run the PII scan** from the repository root. It must report no findings:

    ```bash
    node fixtures/generator/scripts/scan-pii.mjs fixtures
    ```

13. **Run the format check** from the repository root:

    ```bash
    npm run format:check
    ```

14. **Open a PR** from a branch named `recording/<yyyy-mm-dd>-<room-slug>`. Commit with the message
    `test(fixtures): add recorded room scan <yyyy-mm-dd>-<room-slug>`. In the PR body, give the
    room label, scan date, device model and the three tape values in millimetres. Do not put an
    address or a name in the PR body.

## After the scan

- Keep the original export in a private folder outside the repository.
- The recorded folder is a test input only. It is not a client file and it does not replace the
  synthetic fixtures.
