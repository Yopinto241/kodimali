import type { NextConfig } from "next";

const nextConfig: NextConfig = {
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
