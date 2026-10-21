// A cell text that may break only between its phrases ("Revision 1 · sealed Oct 17, 2026",
// "Floor 1 / plan-sheet.pdf"), never inside one ("re-seal", "1.4 KB"). The text content is
// unchanged. With `maxNowrap`, a phrase longer than that many characters may break between its
// words (narrow columns keep "584 KB" whole but let "+ primary closet" wrap).

import { Fragment } from "react";

export function Phrases({
  text,
  separator = " · ",
  maxNowrap,
}: {
  readonly text: string;
  readonly separator?: " · " | " / ";
  readonly maxNowrap?: number;
}) {
  const parts = text.split(separator);
  const mark = separator.trimEnd();
  return (
    <>
      {parts.map((part, index) => {
        const last = index === parts.length - 1;
        const whole = maxNowrap === undefined || part.length <= maxNowrap;
        return (
          <Fragment key={index}>
            <span className={whole ? "phrase" : undefined}>
              {part}
              {last ? "" : mark}
            </span>
            {last ? "" : " "}
          </Fragment>
        );
      })}
    </>
  );
}
