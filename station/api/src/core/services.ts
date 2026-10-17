// Injectable services of the station (HUB client, blob storage, ...).
//
// Each feature area adds its service by declaration merging in its own module, so no area
// edits this file:
//
//   declare module "../core/services.js" {
//     interface StationServices {
//       hub: HubClient;
//     }
//   }
//
// buildServer({ services: { hub: fakeHub } }) injects test doubles; a route plugin creates the
// real service from app.config when none was injected.

// Intentionally empty: feature areas extend it through declaration merging.
// eslint-disable-next-line @typescript-eslint/no-empty-object-type
export interface StationServices {}
