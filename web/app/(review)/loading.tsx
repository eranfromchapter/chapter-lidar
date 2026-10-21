// Loading state of a review page (web-review §6.7): the topbar without a title and a card of
// static skeleton rows. No animation.

import { Card } from "@/components/hub/Card";

const WIDTHS = ["40%", "25%", "15%"];

export default function Loading() {
  return (
    <>
      <header className="topbar" aria-busy="true">
        <span className="topbar__title" />
      </header>
      <main className="page" id="main" aria-busy="true">
        <span className="visually-hidden" role="status">
          Loading
        </span>
        <Card padding="none">
          {[0, 1, 2, 3, 4].map((row) => (
            <div key={row} className="skeleton-row">
              {WIDTHS.map((width) => (
                <span key={width} className="skeleton-bar" style={{ width }} />
              ))}
            </div>
          ))}
        </Card>
      </main>
    </>
  );
}
