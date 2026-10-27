"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";

const instagram = "https://www.instagram.com/kodimali1/";

function Icon({ kind }: { kind: "booking" | "instagram" | "account" }) {
  if (kind === "instagram") return <svg viewBox="0 0 24 24" aria-hidden><rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.4" cy="6.7" r="1" className="fill-current stroke-0"/></svg>;
  if (kind === "account") return <svg viewBox="0 0 24 24" aria-hidden><circle cx="12" cy="8" r="4"/><path d="M4.8 20c.8-4 3.1-6 7.2-6s6.4 2 7.2 6"/></svg>;
  return <svg viewBox="0 0 24 24" aria-hidden><rect x="4" y="5" width="16" height="15" rx="3"/><path d="M8 3v4m8-4v4M4 10h16m-12 4h3m2 0h3"/></svg>;
}

export function MobileBottomNav() {
  const pathname = usePathname();
  return <nav className="mobile-bottom-nav" aria-label="Mobile shortcuts">
    <Link href="/account#bookings" className={pathname.startsWith("/account") ? "is-active" : ""}><Icon kind="booking"/><span>Booking</span></Link>
    <a href={instagram} target="_blank" rel="noreferrer"><Icon kind="instagram"/><span>Instagram</span></a>
    <Link href="/listings" className={`mobile-bottom-brand ${pathname === "/listings" ? "is-active" : ""}`} aria-label="Listings"><Image src="/icon.png" alt="" width={44} height={44}/></Link>
    <a href={instagram} target="_blank" rel="noreferrer"><Icon kind="instagram"/><span>Instagram</span></a>
    <Link href="/account" className={pathname.startsWith("/account") || pathname === "/login" || pathname === "/register" ? "is-active" : ""}><Icon kind="account"/><span>Account</span></Link>
  </nav>;
}
