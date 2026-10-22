"use client";

// The plan preview image (web-review §6.4.4). The PNG is streamed through this app's preview
// route, never from a signed link. When it cannot be loaded the box says so instead of showing
// a broken image (also when the error happened before hydration).

import { useEffect, useRef, useState } from "react";

export interface PlanPreviewProps {
  readonly src: string;
  readonly alt: string;
}

export function PlanPreview({ src, alt }: PlanPreviewProps) {
  const [failed, setFailed] = useState(false);
  const image = useRef<HTMLImageElement>(null);
  useEffect(() => {
    const element = image.current;
    if (element !== null && element.complete && element.naturalWidth === 0) {
      setFailed(true);
    }
  }, [src]);
  if (failed) {
    return (
      <p className="plan-preview__message" role="status" style={{ margin: 0 }}>
        The plan preview could not be loaded. Download plan.png instead.
      </p>
    );
  }
  // A plain img: the preview route answers with the PNG bytes of this package only.
  return <img ref={image} src={src} alt={alt} onError={() => setFailed(true)} />;
}
