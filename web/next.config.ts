import type { NextConfig } from "next";

/** Routes that redirect to a short-lived signed link: the link must not leak as a referrer. */
const SIGNED_LINK_ROUTES = [
  "/packages/:packageId/files/download",
  "/packages/:packageId/report/download",
];

const nextConfig: NextConfig = {
  reactStrictMode: true,
  poweredByHeader: false,
  // The station API URL and every secret are read at request time on the server only
  // (lib/config.ts). Nothing here is exposed to the browser.
  async headers() {
    return [
      {
        source: "/:path*",
        headers: [
          { key: "X-Content-Type-Options", value: "nosniff" },
          { key: "Referrer-Policy", value: "same-origin" },
          { key: "X-Frame-Options", value: "DENY" },
        ],
      },
      // Later entries win over earlier ones for the same header.
      ...SIGNED_LINK_ROUTES.map((source) => ({
        source,
        headers: [{ key: "Referrer-Policy", value: "no-referrer" }],
      })),
    ];
  },
};

export default nextConfig;
