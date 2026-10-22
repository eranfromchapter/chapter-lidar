// The page list of a report and the page numbers other pages print (spec 4.2).

import type { ReportPhoto } from "../input.js";

/** A row of the contents list. */
export type ContentsRow =
  | { readonly kind: "schedule" }
  | { readonly kind: "checks" }
  | { readonly kind: "record" }
  | { readonly kind: "floor"; readonly floor: number }
  | { readonly kind: "room"; readonly room: number };

/** One row of a schedule page. */
export type ScheduleRow =
  | { readonly kind: "floor"; readonly floor: number }
  | { readonly kind: "room"; readonly room: number; readonly height: number }
  | { readonly kind: "skipped"; readonly floor: number; readonly skipped: number }
  | { readonly kind: "unavailable"; readonly floor: number }
  | { readonly kind: "subtotal"; readonly floor: number }
  | { readonly kind: "empty" };

/** A slice of one capture checks table row. */
export interface CheckSlice {
  readonly row: number;
  readonly continued: boolean;
  /** First and last (exclusive) finding block of the row on this page, with line ranges. */
  readonly blocks: ReadonlyArray<{
    readonly block: number;
    readonly fromLine: number;
    readonly toLine: number;
    readonly fromAction: number;
    readonly toAction: number;
  }>;
  /** True when the row's last part is on this page. */
  readonly ends: boolean;
}

/** A slice of the right column of a checks page: one section and items in it. */
export interface RightSlice {
  readonly section: number;
  readonly continued: boolean;
  readonly fromItem: number;
  readonly toItem: number;
}

/** One row of a room's items table on a page: a group row or an item row. */
export type ItemLine =
  | { readonly kind: "group"; readonly group: number; readonly continued: boolean }
  | { readonly kind: "item"; readonly item: number };

/** A block of the package record pages. */
export type RecordBlock =
  | { readonly kind: "kicker"; readonly text: string }
  | { readonly kind: "recordRow"; readonly row: number }
  | { readonly kind: "capturesHeader" }
  | { readonly kind: "captureRow"; readonly capture: number }
  | { readonly kind: "filesIntro" }
  | { readonly kind: "filesHeader" }
  | { readonly kind: "fileRow"; readonly file: number };

export type PageSpec =
  | { readonly kind: "cover" }
  | {
      readonly kind: "contents";
      readonly columns: ReadonlyArray<readonly ContentsRow[]>;
      readonly note: boolean;
    }
  | { readonly kind: "plan"; readonly floor: number; readonly contents?: readonly ContentsRow[] }
  | {
      readonly kind: "schedule";
      readonly rows: readonly ScheduleRow[];
      readonly first: boolean;
      readonly last: boolean;
    }
  | {
      readonly kind: "checks";
      readonly first: boolean;
      readonly table: readonly CheckSlice[];
      readonly tableHeader: boolean;
      readonly tableEnds: boolean;
      readonly right: readonly RightSlice[];
    }
  | {
      readonly kind: "room";
      readonly room: number;
      readonly first: boolean;
      readonly lines: readonly ItemLine[];
      /** Continuation note, when the list is split. */
      readonly note?: string;
    }
  | {
      readonly kind: "photos";
      readonly floor: number;
      /** Room number (visit-wide), or undefined for "Other site photos". */
      readonly room?: number;
      readonly photos: readonly ReportPhoto[];
      readonly firstNumber: number;
      readonly continued: boolean;
    }
  | { readonly kind: "record"; readonly first: boolean; readonly blocks: readonly RecordBlock[] };

/** Page numbers of the report, known once the page list is final. */
export class PageIndex {
  readonly total: number;
  readonly #first = new Map<string, number>();
  readonly #last = new Map<string, number>();

  constructor(readonly pages: readonly PageSpec[]) {
    this.total = pages.length;
    pages.forEach((page, i) => {
      const n = i + 1;
      for (const key of keysOf(page)) {
        if (!this.#first.has(key)) {
          this.#first.set(key, n);
        }
        this.#last.set(key, n);
      }
    });
  }

  #get(key: string): number {
    return this.#first.get(key) ?? 0;
  }

  get schedule(): number {
    return this.#get("schedule");
  }

  get checks(): number {
    return this.#get("checks");
  }

  get record(): number {
    return this.#get("record");
  }

  get contents(): number {
    return this.#get("contents");
  }

  plan(floor: number): number {
    return this.#get(`plan:${floor}`);
  }

  /** First page of a room (its room page). */
  room(room: number): number {
    return this.#get(`room:${room}`);
  }

  /** "5–6" (room page to last photo page), or "5". */
  roomRange(room: number): string {
    const first = this.#first.get(`room:${room}`) ?? 0;
    const last = this.#last.get(`room:${room}`) ?? first;
    return last > first ? `${first}–${last}` : String(first);
  }
}

function keysOf(page: PageSpec): string[] {
  switch (page.kind) {
    case "cover":
      return ["cover"];
    case "contents":
      return ["contents"];
    case "plan":
      return [`plan:${page.floor}`];
    case "schedule":
      return ["schedule"];
    case "checks":
      return ["checks"];
    case "room":
      return [`room:${page.room}`];
    case "photos":
      return page.room === undefined ? [`other:${page.floor}`] : [`room:${page.room}`];
    case "record":
      return ["record"];
  }
}
