// Ids of the drawn scenario (test/support/scenarios.ts), on their own so the end-to-end specs can
// name pages without loading the fixture packages.

/** Deal ids of the drawn projects. */
export const DEALS = {
  westEnd: "4417203",
  valley: "4417318",
  shawnee: "4416950",
  blocked: "4416871",
  east81: "4416602",
} as const;

/** Package ids of the drawn scenario (fixture ids are shared between fixtures). */
export const IDS = {
  westEnd1: "5d236b10-70f2-42f9-8f3f-7e56547a3146",
  valley1: "7a1c2e3f-4b5d-4c6e-8f70-81a2b3c4d5e6",
  shawnee1: "1b2c3d4e-5f60-4a71-8b82-93a4b5c6d7e8",
  shawnee2: "2c3d4e5f-6071-4b82-9c93-a4b5c6d7e8f9",
  blocked1: "3d4e5f60-7182-4c93-8da4-b5c6d7e8f9a0",
  east811: "4e5f6071-8293-4da4-9eb5-c6d7e8f9a0b1",
  checking: "5f607182-93a4-4eb5-8fc6-d7e8f9a0b1c2",
  checkError: "60718293-a4b5-4fc6-9ad7-e8f9a0b1c2d3",
  twoFloors: "718293a4-b5c6-4ad7-8be8-f9a0b1c2d3e4",
  stopped1: "8293a4b5-c6d7-4be8-9cf9-a0b1c2d3e4f5",
  stopped2: "93a4b5c6-d7e8-4cf9-8da0-b1c2d3e4f5a6",
  legacy: "a4b5c6d7-e8f9-4da0-9eb1-c2d3e4f5a6b7",
} as const;
