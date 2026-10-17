"use client";

import { useEffect } from "react";

/** Scrolls the element with this id into view once, after the page renders. */
export function ScrollToTarget({ targetId }: { readonly targetId: string }) {
  useEffect(() => {
    const element = document.getElementById(targetId);
    if (element !== null && typeof element.scrollIntoView === "function") {
      element.scrollIntoView({ block: "center" });
    }
  }, [targetId]);
  return null;
}
