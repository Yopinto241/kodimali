import type { Metadata } from "next";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { FirstVisitWelcome } from "@/components/first-visit-welcome";
import { LanguageProvider } from "@/components/language-provider";
import { GlobalInteractions } from "@/components/global-interactions";
import "./globals.css";
import { bodyFont, headingFont } from "./fonts";

export const metadata: Metadata = {
  metadataBase: new URL(
    process.env.NEXT_PUBLIC_SITE_URL ?? "https://kodimali.co.tz",
  ),
  title: {
    default: "KODIMALI | Tafuta na simamia mali",
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
    title: "KODIMALI | Tafuta na simamia mali",
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
        <LanguageProvider>
          <GlobalInteractions />
          <FirstVisitWelcome />
          <SiteHeader />
          <div className="page-frame">{children}</div>
          <SiteFooter />
        </LanguageProvider>
      </body>
    </html>
  );
}
