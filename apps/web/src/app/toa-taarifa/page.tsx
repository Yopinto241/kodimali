import type { Metadata } from "next";
import { CustomerReferralPortal } from "@/components/customer-referral-portal";
import { PageShell } from "@/components/page-shell";
import { ReferralPageHero } from "@/components/referral-page-hero";
export const metadata:Metadata={title:"Toa Taarifa"};
export default function ReferralPage(){return <><ReferralPageHero/><PageShell className="pb-20"><div id="referral-form" className="scroll-mt-28 py-12"><CustomerReferralPortal/></div></PageShell></>}
