"use client";

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
            <Link href="/" className="footer-brand">KODIMALI</Link>
            <p className="footer-tagline">{sw ? "Pata mali, huduma na wataalamu wa matukio sehemu moja." : "Find properties, services and event professionals in one place."}</p>
          </div>
          <nav className="footer-primary-actions" aria-label={sw ? "Hatua muhimu" : "Primary actions"}>
            <Link href="/listings">{sw ? "Tafuta mali" : "Find a property"}<span> →</span></Link>
            <Link href="/account">{sw ? "Akaunti yangu" : "My account"}<span> →</span></Link>
            <Link href="/manage">{sw ? "Simamia" : "Manage"}<span> →</span></Link>
          </nav>
        </div>
        <div className="footer-directory">
          <section><h2 className="footer-heading">{sw ? "Gundua" : "Explore"}</h2><nav className="footer-links">{explore.map(([href,label]) => <Link key={href} href={href}>{t(label)}</Link>)}</nav></section>
          <section><h2 className="footer-heading">{sw ? "Taarifa" : "Information"}</h2><nav className="footer-links">{information.map(([href,label]) => <Link key={href} href={href}>{t(label)}</Link>)}</nav></section>
          <section><h2 className="footer-heading">{sw ? "Wasiliana nasi" : "Contact us"}</h2><address className="footer-contacts">{contacts.map(([href,label,labelEn,value]) => <a key={href} href={href} target={href.startsWith("http") ? "_blank" : undefined} rel={href.startsWith("http") ? "noreferrer" : undefined}><span>{sw ? label : labelEn}</span><strong>{value}</strong></a>)}</address></section>
        </div>
        <div className="footer-bottom"><span>© {new Date().getFullYear()} KODIMALI</span><span>{sw ? "Tanzania na Afrika Mashariki" : "Tanzania and East Africa"}</span></div>
      </div>
    </footer>
  );
}
