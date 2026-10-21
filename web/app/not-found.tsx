// Not found outside the shell (an unknown address; no session needed), in the review screen's
// HUB look instead of the Next.js default. Shows no data.

import type { Metadata } from "next";
import { NotFoundCard } from "@/components/NotFoundCard";
import { SoloPage } from "@/components/SoloPage";

export const metadata: Metadata = { title: "Not found · Capture review" };

export default function NotFound() {
  return (
    <SoloPage>
      <NotFoundCard />
    </SoloPage>
  );
}
