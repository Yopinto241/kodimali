"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useRef, useState } from "react";

const instagram = "https://www.instagram.com/kodimali1/";

function Icon({ kind }: { kind: "listings" | "instagram" | "whatsapp" | "account" }) {
  if (kind === "instagram") return <svg viewBox="0 0 24 24" aria-hidden><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.4" cy="6.7" r="1" className="fill-current stroke-0"/></svg>;
  if (kind === "whatsapp") return <svg viewBox="0 0 24 24" aria-hidden><path d="M20 11.6a8 8 0 0 1-11.8 7L4 20l1.4-4A8 8 0 1 1 20 11.6Z"/><path d="M9 8.2c.3 2.8 2 4.6 4.9 5.7l1.2-1.4 2.1 1c-.3 1.6-1.3 2.4-2.7 2.3-4-.4-7.5-3.7-7.9-7.7 0-1.4.8-2.3 2.2-2.6l1 2.1L9 8.2Z"/></svg>;
  if (kind === "account") return <svg viewBox="0 0 24 24" aria-hidden><circle cx="12" cy="8" r="4"/><path d="M4.8 20c.8-4 3.1-6 7.2-6s6.4 2 7.2 6"/></svg>;
  return <svg viewBox="0 0 24 24" aria-hidden><rect x="3" y="4" width="7" height="7" rx="1.5"/><rect x="14" y="4" width="7" height="7" rx="1.5"/><rect x="3" y="15" width="7" height="5" rx="1.5"/><rect x="14" y="15" width="7" height="5" rx="1.5"/></svg>;
}

export function MobileBottomNav() {
  const pathname = usePathname();
  const [hidden, setHidden] = useState(false);
  const lastY = useRef(0);
  const frame = useRef<number | null>(null);

  useEffect(() => {
    lastY.current = window.scrollY;
    const update = () => {
      frame.current = null;
      const currentY = Math.max(0, window.scrollY);
      const delta = currentY - lastY.current;
      if (currentY < 64) setHidden(false);
      else if (delta > 7) setHidden(true);
      else if (delta < -4) setHidden(false);
      lastY.current = currentY;
    };
    const onScroll = () => {
      if (frame.current === null) frame.current = requestAnimationFrame(update);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (frame.current !== null) cancelAnimationFrame(frame.current);
    };
  }, []);

  return <nav className={`mobile-bottom-nav ${hidden ? "is-hidden" : ""}`} aria-label="Mobile shortcuts" aria-hidden={hidden}>
    <Link href="/listings" className={pathname.startsWith("/listings") || pathname.startsWith("/category/") ? "is-active" : ""}><Icon kind="listings"/><span>Listings</span></Link>
    <a href="https://wa.me/255684684972" target="_blank" rel="noreferrer"><Icon kind="whatsapp"/><span>WhatsApp</span></a>
    <Link href="/" className={`mobile-bottom-brand ${pathname === "/" ? "is-active" : ""}`} aria-label="Home"><Image src="/icon.png" alt="" width={44} height={44}/><span className="sr-only">Home</span></Link>
    <a href={instagram} target="_blank" rel="noreferrer"><Icon kind="instagram"/><span>Instagram</span></a>
    <Link href="/account" className={pathname.startsWith("/account") || pathname === "/login" || pathname === "/register" ? "is-active" : ""}><Icon kind="account"/><span>Account</span></Link>
  </nav>;
}
