import { cookies } from "next/headers";
import { HOME_TITLE, HOME_DESCRIPTION, SITE_URL, pageMetadata } from "@/lib/seo";
import { StructuredData } from "@/components/structured-data";
import type { Metadata } from "next";
import { SiteFooter } from "@/components/site-footer";
import { SiteHeader } from "@/components/site-header";
import { FirstVisitWelcome } from "@/components/first-visit-welcome";
import { LanguageProvider } from "@/components/language-provider";
import { GlobalInteractions } from "@/components/global-interactions";
import { MobileBottomNav } from "@/components/mobile-bottom-nav";
import { NavigationProgress } from "@/components/navigation-progress";
import { PublicSiteChrome } from "@/components/public-site-chrome";
import "./globals.css";
import { bodyFont, headingFont } from "./fonts";

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  ...pageMetadata(HOME_TITLE, HOME_DESCRIPTION, "/"),
  title: { default: HOME_TITLE, template: "%s | KODIMALI" },
  icons: { icon: "/icon.png", apple: "/apple-icon.png", shortcut: "/favicon.ico" },
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const language = (await cookies()).get("kodimali_language")?.value === "en" ? "en" : "sw";
  return (
    <html
      lang={language}
      className={`${bodyFont.variable} ${headingFont.variable} h-full antialiased`}
    >
      <body className="min-h-full font-sans">
        <LanguageProvider initialLanguage={language}>
          <NavigationProgress>
          <StructuredData data={[
            { "@context": "https://schema.org", "@type": "Organization", "@id": `${SITE_URL}/#organization`, name: "KODIMALI", url: SITE_URL, logo: `${SITE_URL}/icon.png`, telephone: "+255628621737" },
            { "@context": "https://schema.org", "@type": "WebSite", "@id": `${SITE_URL}/#website`, name: "KODIMALI", url: SITE_URL, description: HOME_DESCRIPTION, inLanguage: ["sw-TZ", "en"], publisher: { "@id": `${SITE_URL}/#organization` } },
          ]} />
          <GlobalInteractions />
          <PublicSiteChrome><FirstVisitWelcome /><SiteHeader /></PublicSiteChrome>
          <div className="page-frame">{children}</div>
          <PublicSiteChrome><SiteFooter /><MobileBottomNav /></PublicSiteChrome>
          </NavigationProgress>
        </LanguageProvider>
      </body>
    </html>
  );
}
