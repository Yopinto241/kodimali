"use client";
import { UiNav, UiText } from "@/components/ui-text";

import Link from "next/link";
import { useLanguage } from "@/components/language-provider";

const explore = [
  ["/", "footer.home"], ["/listings", "footer.all"], ["/events", "nav.events"],
  ["/category/house", "footer.houses"], ["/category/apartment", "footer.apartments"],
  ["/category/car", "footer.cars"], ["/compare", "footer.compare"], ["/map", "footer.map"],
] as const;
const information = [
  ["/advertise", "footer.advertise"], ["/download", "footer.download"],
  ["/safety", "footer.safety"], ["/privacy", "footer.privacy"],
  ["/terms", "footer.terms"], ["/delete-account", "footer.delete"],
] as const;
const contacts = [
  ["tel:0628621737", "Simu", "Phone", "0628 621 737"],
  ["https://wa.me/255684684972", "WhatsApp", "WhatsApp", "0684 684 972"],
  ["https://instagram.com/kodimali1", "Instagram", "Instagram", "@kodimali1"],
  ["https://facebook.com/search/top?q=kodimali%20tanzania", "Facebook", "Facebook", "Kodimali Tanzania"],
] as const;

export function SiteFooter() {
  const { language, t } = useLanguage();
  const sw = language === "sw";
  return (
    <footer className="site-footer">
      <div className="app-shell">
        <div className="footer-intro">
          <div>
            <Link prefetch={false} href="/" className="footer-brand">KODIMALI</Link>
            <p className="footer-tagline"><UiText text={sw ? "Pata mali, huduma na wataalamu wa matukio sehemu moja." : "Find properties, services and event professionals in one place."} /></p>
          </div>
          <UiNav className="footer-primary-actions" aria-label={sw ? "Hatua muhimu" : "Primary actions"}>
            <Link prefetch={false} href="/listings"><UiText text={sw ? "Tafuta mali" : "Find a property"} /><span> →</span></Link>
            <Link prefetch={false} href="/account"><UiText text={sw ? "Akaunti yangu" : "My account"} /><span> →</span></Link>
            <Link prefetch={false} href="/manage"><UiText text={sw ? "Simamia" : "Manage"} /><span> →</span></Link>
          </UiNav>
        </div>
        <div className="footer-directory">
          <section><h2 className="footer-heading"><UiText text={sw ? "Gundua" : "Explore"} /></h2><nav className="footer-links">{explore.map(([href,label]) => <Link prefetch={false} key={href} href={href}>{t(label)}</Link>)}</nav></section>
          <section><h2 className="footer-heading"><UiText text={sw ? "Taarifa" : "Information"} /></h2><nav className="footer-links">{information.map(([href,label]) => <Link prefetch={false} key={href} href={href}>{t(label)}</Link>)}</nav></section>
          <section><h2 className="footer-heading"><UiText text={sw ? "Wasiliana nasi" : "Contact us"} /></h2><address className="footer-contacts">{contacts.map(([href,label,labelEn,value]) => <a key={href} href={href} target={href.startsWith("http") ? "_blank" : undefined} rel={href.startsWith("http") ? "noreferrer" : undefined}><span>{sw ? label : labelEn}</span><strong>{value}</strong></a>)}</address></section>
        </div>
        <div className="footer-bottom"><span>© {new Date().getFullYear()} KODIMALI</span><span><UiText text={sw ? "Tanzania na Afrika Mashariki" : "Tanzania and East Africa"} /></span></div>
      </div>
    </footer>
  );
}
