import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  // Resolve public metadata/notFound before committing an HTTP status. The document-navigation logo remains active while users wait.
  htmlLimitedBots: /.*/,
  async redirects() {
    return [
      { source: "/:path*", has: [{ type: "host", value: "www.kodimali.com" }], destination: "https://kodimali.com/:path*", permanent: true },
      { source: "/:path*", has: [{ type: "host", value: "kodimali.com" }, { type: "header", key: "x-forwarded-proto", value: "http" }], destination: "https://kodimali.com/:path*", permanent: true },
      { source: "/category/events", destination: "/events", permanent: true },
    ];
  },
  async headers() {
    return ["/account/:path*", "/admin/:path*", "/manage/:path*", "/owner/:path*", "/agent", "/login", "/register", "/compare", "/map", "/events/plan", "/api/:path*", "/listing/:id/book", "/listing/:id/chat", "/listing/:id/contact"].map(source => ({ source, headers: [{ key: "X-Robots-Tag", value: "noindex, follow" }] }));
  },
  images: {
    formats: ["image/avif", "image/webp"],
    minimumCacheTTL: 86400,
    qualities: [60, 72, 85],
    remotePatterns: [
      {
        protocol: "https",
        hostname: "tlhoajedyaeaaqtrjqqh.supabase.co",
        pathname: "/storage/v1/object/**",
      },
    ],
  },
};

export default nextConfig;
