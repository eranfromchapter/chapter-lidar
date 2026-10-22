# Third-party notices

## Inter

`src/report/brand-assets.generated.ts` embeds Inter Regular and Inter SemiBold (TrueType, cut
down to the WinAnsi characters), copied byte for byte from
`ios/Packages/PlanExport/Sources/PlanExport/ChapterBrandAssets.swift` (made by
`tools/brand/generate_plan_brand.py`) by `scripts/generate-brand-assets.mjs`
(`npm run brand-assets`). Every spatial report PDF the station renders embeds subsets of them.

Copyright 2020 The Inter Project Authors (https://github.com/rsms/inter)

This Font Software is licensed under the SIL Open Font License, Version 1.1. This license is
available with a FAQ at: https://openfontlicense.org (formerly http://scripts.sil.org/OFL).
The copyright and license fields are kept in the name table of each font in
`brand-assets.generated.ts`.

## Chapter logo

`LOGO_PATHS` in `src/report/brand-assets.generated.ts` (the path data of
`web/public/brand/chapter-logo.svg`, as published on hellochapter.com) is the Chapter logo, a
trademark of Chapter, and is not covered by any open license.

## Libraries with LGPL code in the worker image

The worker image installs these npm packages unmodified; the station calls each only through its
public API (`src/report/photos.ts`), and each can be replaced by installing another build of the
same package.

- `@img/sharp-libvips-*` 1.3.4 (libvips and the libraries it is built with,
  LGPL-3.0-or-later; https://github.com/lovell/sharp-libvips): the native library of
  `sharp@0.35.5` (Apache-2.0), which reduces the site photos.
- `libheif-js` 1.23.5 (libheif compiled to JavaScript and WebAssembly, LGPL-3.0;
  https://github.com/catdad-experiments/libheif-js), loaded by `heic-decode@2.1.0` (ISC): decodes
  iPhone HEIC photos, which the prebuilt sharp cannot read (HEVC).

## Fonts used only by the tests

`test/report-visual` rasterizes report pages with Tinos and Cousine (`@fontsource/tinos`,
`@fontsource/cousine`, SIL Open Font License 1.1, devDependencies) in place of the PDF standard
fonts Times-Roman and Courier, so the snapshots are the same on every platform. They are never
embedded in a report or installed in the worker image.
