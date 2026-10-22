// Pagination (spec 4): the page list of a report from its model, using measured text heights
// (pdfkit metrics of the embedded fonts, no drawing). Page-dependent strings (contents ranges,
// "page N", the schedule's Page column, n / N) only fill fixed cells or single lines, so the
// page numbers resolved afterwards never change the page count.

import type { Canvas } from "./layout/canvas.js";
import type { Model } from "./model.js";
import { paginateChecks } from "./pages/checks.js";
import type { ContentsRow, PageSpec } from "./pages/index-of-pages.js";
import { photoPages } from "./pages/photos.js";
import { CONTENTS_PAGE_ROWS, contentsCapacity, contentsRows } from "./pages/plan.js";
import { paginateRecord } from "./pages/record.js";
import { paginateRoom } from "./pages/room.js";
import { paginateSchedule } from "./pages/schedule.js";

export function paginate(canvas: Canvas, model: Model): PageSpec[] {
  const pages: PageSpec[] = [{ kind: "cover" }];
  const contents = contentsRows(model);
  const onPlan = contents.length <= contentsCapacity(canvas, model);
  if (!onPlan) {
    // Contents pages: three columns of rows each.
    const perPage = CONTENTS_PAGE_ROWS * 3;
    for (let start = 0; start < contents.length; start += perPage) {
      const chunk = contents.slice(start, start + perPage);
      const columns: ContentsRow[][] = [];
      for (let c = 0; c < chunk.length; c += CONTENTS_PAGE_ROWS) {
        columns.push(chunk.slice(c, c + CONTENTS_PAGE_ROWS));
      }
      const last = start + perPage >= contents.length;
      const lastColumn = columns[columns.length - 1] ?? [];
      pages.push({
        kind: "contents",
        columns,
        note: last && lastColumn.length < CONTENTS_PAGE_ROWS - 1,
      });
    }
  }
  model.floors.forEach((floor, i) => {
    pages.push({ kind: "plan", floor: floor.index, ...(onPlan && i === 0 ? { contents } : {}) });
  });
  pages.push(...paginateSchedule(canvas, model));
  pages.push(...paginateChecks(canvas, model));
  for (const floor of model.floors) {
    for (const room of floor.rooms) {
      pages.push(...paginateRoom(canvas, model, room));
      if (!model.photosOmitted) {
        pages.push(...photoPages(floor, room.photos, room));
      }
    }
    if (!model.photosOmitted) {
      pages.push(...photoPages(floor, floor.otherPhotos));
    }
  }
  pages.push(...paginateRecord(canvas, model));
  return pages;
}
