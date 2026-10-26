import type { Metadata } from "next";
import { cookies } from "next/headers";
import { ContentSection } from "@/components/content-section";
import { PageHero } from "@/components/page-hero";
import { PageShell } from "@/components/page-shell";

export const metadata: Metadata = {
  title: "Masharti | Terms of use | KODIMALI",
  description:
    "Booking, payment, cancellation and marketplace terms for KODIMALI.",
};

export default async function TermsPage() {
  const sw = (await cookies()).get("kodimali_language")?.value !== "en";
  return (
    <PageShell className="space-y-6 pb-20">
      <PageHero
        eyebrow={sw ? "Masharti ya matumizi" : "Terms of use"}
        title={
          sw
            ? "Masharti yaliyo wazi kwa booking salama."
            : "Clear terms for safer bookings."
        }
        description={
          sw
            ? "Hapa tunaeleza booking, malipo, cancellation, refund na wajibu wa kila upande."
            : "This page explains bookings, payments, cancellations, refunds, and each party's responsibilities."
        }
      />
      <ContentSection title={sw ? "Jukumu la KODIMALI" : "KODIMALI's role"}>
        <p>
          {sw
            ? "KODIMALI huunganisha wateja na wamiliki, mameneja au mawakala waliothibitishwa, na kutoa zana za kutafuta, kufanya booking, kulipa na kufuatilia huduma. Isiposemwa wazi kwenye muamala, KODIMALI si mmiliki wa mali wala mhusika wa mkataba wa upangishaji."
            : "KODIMALI connects customers with verified owners, managers, or agents and provides tools for discovery, booking, payment, and service tracking. Unless a transaction states otherwise, KODIMALI is not the asset owner or a party to the rental agreement."}
        </p>
      </ContentSection>
      <div id="booking-payments" className="scroll-mt-24">
        <ContentSection
          title={sw ? "Booking na malipo" : "Booking and payment"}
        >
          <p>
            {sw
              ? "Kwa listing inayoruhusu instant booking, mfumo hukagua muda uliochagua na kuushikilia kwa dakika 30. Hold si booking iliyolipwa; booking inathibitishwa baada ya malipo kukamilika. Hold huisha ikiwa malipo hayajakamilika kwa muda ulioonyeshwa."
              : "For an instant-bookable listing, the system checks the selected period and holds it for 30 minutes. A hold is not a paid booking; the booking is confirmed after payment succeeds. The hold expires when payment is not completed within the displayed time."}
          </p>
          <p>
            {sw
              ? "Kiasi kamili, madhumuni ya malipo, muda na listing vitaonyeshwa kabla ya kuidhinisha ombi la mobile money. Mfumo huzuia booking mbili zinazogongana kwa muda mmoja. Viewing ni hiari na si sharti la kufanya booking."
              : "The full amount, payment purpose, period, and listing are shown before you approve the mobile-money request. The system prevents overlapping bookings. A viewing is optional and is not required to book."}
          </p>
        </ContentSection>
      </div>
      <ContentSection
        title={sw ? "Cancellation na refund" : "Cancellation and refunds"}
      >
        <p>
          {sw
            ? "Uwezo wa kufanya cancellation na kiasi kinachoweza kurejeshwa hutegemea sera iliyoonyeshwa kwa booking husika, muda uliobaki kabla ya kuanza huduma, na kama huduma tayari imeanza. Ombi la refund hukaguliwa; si kila malipo hurudishwa moja kwa moja."
            : "Cancellation eligibility and any refundable amount depend on the policy shown for that booking, the time remaining before service starts, and whether service has begun. Refund requests are reviewed; payments are not automatically refundable."}
        </p>
        <p>
          {sw
            ? "Refund iliyoidhinishwa hurudishwa kwa njia ya awali ya malipo inapowezekana. Muda wa kuonekana kwa fedha hutegemea mtoa huduma wa malipo. Hifadhi uthibitisho wa malipo na mawasiliano ya booking kwa ajili ya ukaguzi."
            : "An approved refund is returned through the original payment method where possible. The time for funds to appear depends on the payment provider. Keep payment proof and booking communication for review."}
        </p>
      </ContentSection>
      <ContentSection
        title={sw ? "Kulipia mawasiliano" : "Paid contact access"}
      >
        <p>
          {sw
            ? "Malipo ya kufungua namba ya wakala ni ada ya kupata mawasiliano kwa muda ulioonyeshwa; si kodi, deposit wala booking. Ikiwa listing haipatikani au wakala hajibu, unaweza kuomba ukaguzi wa refund kupitia msaada wa KODIMALI."
            : "A payment to unlock an agent's number is a contact-access fee for the displayed period; it is not rent, a deposit, or a booking. If the listing is unavailable or the agent does not respond, you may request a refund review through KODIMALI support."}
        </p>
      </ContentSection>
      <ContentSection
        title={
          sw ? "Wajibu wa mmiliki au wakala" : "Owner or agent responsibilities"
        }
      >
        <p>
          {sw
            ? "Wamiliki, mameneja na mawakala lazima waweke taarifa sahihi, ruhusa halali, bei na availability ya sasa. Booking iliyothibitishwa lazima iheshimiwe. Mabadiliko yanayoweza kuathiri mteja yawasilishwe haraka kupitia mfumo."
            : "Owners, managers, and agents must provide accurate information, valid authorization, current prices, and availability. Confirmed bookings must be honored. Changes affecting a customer must be communicated promptly through the platform."}
        </p>
      </ContentSection>
      <ContentSection
        title={sw ? "Matukio na quotation" : "Events and quotations"}
      >
        <p>
          {sw
            ? "Kwa mpango wa tukio wenye watoa huduma wengi, quotation na mbadala wowote huwasilishwa kwanza. Makubaliano, deposit au malipo huanza tu baada ya mteja kuona na kukubali maelezo husika."
            : "For a multi-provider event plan, the quotation and any substitutions are presented first. An agreement, deposit, or payment begins only after the customer sees and accepts the relevant details."}
        </p>
      </ContentSection>
      <ContentSection
        title={sw ? "Usalama na migogoro" : "Safety and disputes"}
      >
        <p>
          {sw
            ? "KODIMALI inaweza kukagua, kuzuia au kuondoa akaunti, listing au muamala ili kulinda watumiaji. Ripoti tatizo kupitia msaada wa KODIMALI ukiambatanisha booking reference, uthibitisho wa malipo na maelezo muhimu."
            : "KODIMALI may review, restrict, or remove an account, listing, or transaction to protect users. Report a problem through KODIMALI support with the booking reference, payment evidence, and relevant details."}
        </p>
      </ContentSection>
    </PageShell>
  );
}
