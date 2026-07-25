import type { Metadata } from "next";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import "./globals.css";
import { bodyFont, headingFont } from "./fonts";

export const metadata: Metadata = {
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL ?? "https://kodimali.co.tz",
  ),
  title: {
    default: "KODIMALI | Trusted rental marketplace",
    template: "%s | KODIMALI",
  },
  description:
    "One shared platform for verified rental agents, customers, and admins.",
  icons: {
    icon: "/icon.png",
    apple: "/apple-icon.png",
    shortcut: "/favicon.ico",
  },
  openGraph: {
    type: "website",
    siteName: "KODIMALI",
    title: "KODIMALI | Trusted rental marketplace",
    description:
      "Discover rentals, send trackable requests, and connect with verified agents.",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${bodyFont.variable} ${headingFont.variable} h-full antialiased`}
    >
      <body className="min-h-full font-sans">
        <SiteHeader />
        <div className="page-frame">{children}</div>
        <SiteFooter />
      </body>
    </html>
  );
}
