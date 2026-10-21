// The page of the review screen without the shell (sign-in, not found and errors outside it,
// web-review §6.7): the HUB "chapter" wordmark in ink, the "Capture review" eyebrow and a card.

import type { ReactNode } from "react";

export function SoloPage({ children }: { readonly children: ReactNode }) {
  return (
    <main className="solo" id="main">
      <div className="solo__column">
        <div className="solo__brand">
          <img
            className="solo__wordmark"
            src="/brand/chapter-wordmark.svg"
            alt="Chapter"
            width={122}
            height={28}
          />
          <span className="solo__eyebrow">Capture review</span>
        </div>
        {children}
      </div>
    </main>
  );
}
