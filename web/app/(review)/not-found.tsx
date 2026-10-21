// Not found inside the shell (web-review §6.7): a project or package the station does not know.

import type { Metadata } from "next";
import { NotFoundCard } from "@/components/NotFoundCard";

export const metadata: Metadata = { title: "Not found · Capture review" };

export default function ReviewNotFound() {
  return (
    <>
      <header className="topbar">
        <h1 className="topbar__title">Not found</h1>
      </header>
      <main className="page" id="main">
        <NotFoundCard />
      </main>
    </>
  );
}
