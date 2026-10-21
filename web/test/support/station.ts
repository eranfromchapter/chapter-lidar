// A viewer session for tests whose station client talks to the fake station
// (test/support/fake-station.ts) through the real station client.

import { createStationClient, type StationClient } from "@/lib/station";
import type { StationRole } from "@/lib/roles";
import { canReview } from "@/lib/roles";
import type { ViewerSession } from "@/lib/viewer";
import { STATION_URL, TEST_ACCESS_TOKEN, type FakeStation } from "./fake-station";

export {
  createFakeStation,
  STATION_URL,
  TEST_ACCESS_TOKEN,
  type FakeStation,
  type FakeStationData,
  type RecordedCall,
} from "./fake-station";

/** A viewer session with the given roles whose station client talks to the fake station. */
export function sessionFor(
  roles: StationRole[],
  station: FakeStation,
  name = "Dana BIM",
): ViewerSession {
  const client: StationClient = createStationClient({
    baseUrl: STATION_URL,
    accessToken: TEST_ACCESS_TOKEN,
    fetchImpl: station.fetch,
  });
  return {
    viewer: {
      name,
      userId: "11111111-1111-4111-8111-111111111111",
      roles,
      canReview: canReview(roles),
    },
    station: client,
  };
}
