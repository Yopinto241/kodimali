"use client";

import { useState } from "react";

import { getBrowserSupabase } from "@/lib/supabase-browser";

type ServiceOption = {
  key: string;
  label: string;
};

export function GuestRequestForm({
  listingId,
  listingTitle,
  categorySlug,
  availableServices,
}: {
  listingId: string;
  listingTitle: string;
  categorySlug?: string;
  availableServices: ServiceOption[];
}) {
  const isApartment = categorySlug === "apartment";
  const isVehicle = categorySlug === "car" || categorySlug === "motorcycle";
  const isHouse = categorySlug === "house";
  const isOffice = categorySlug === "office";
  const isHall =
    categorySlug === "meeting-hall" || categorySlug === "ceremony-hall";
  const isReservable =
    isApartment || isVehicle || isHouse || isOffice || isHall;
  const usesTime = isVehicle || isHall;
  const startLabel = isApartment
    ? "Tarehe ya kuingia"
    : isVehicle
      ? "Tarehe na muda wa kuchukua"
      : isHouse
        ? "Tarehe ya kuhamia"
        : isOffice
          ? "Tarehe ya kuanza"
          : "Tukio linaanza";
  const endLabel = isApartment
    ? "Tarehe ya kutoka"
    : isVehicle
      ? "Tarehe na muda wa kurudisha"
      : isHouse
        ? "Shikilia hadi"
        : isOffice
          ? "Muda unaishia"
          : "Tukio linaisha";
  const [customerName, setCustomerName] = useState("");
  const [customerEmail, setCustomerEmail] = useState("");
  const [customerPhoneNumber, setCustomerPhoneNumber] = useState("");
  const [requestedStartAt, setRequestedStartAt] = useState("");
  const [requestedEndAt, setRequestedEndAt] = useState("");
  const [guestCount, setGuestCount] = useState("");
  const [requestMessage, setRequestMessage] = useState("");
  const [requestedServiceCodes, setRequestedServiceCodes] = useState<string[]>(
    [],
  );
  const [submitting, setSubmitting] = useState(false);
  const [requestReference, setRequestReference] = useState<string | null>(null);
  const [bookingId, setBookingId] = useState<string | null>(null);
  const [instantReservation, setInstantReservation] = useState(false);
  const [errors, setErrors] = useState<{
    customerName?: string;
    customerEmail?: string;
    customerPhoneNumber?: string;
    requestedDates?: string;
    form?: string;
  }>({});

  function validateForm() {
    const nextErrors: {
      customerName?: string;
      customerEmail?: string;
      customerPhoneNumber?: string;
      requestedDates?: string;
    } = {};

    if (!customerName.trim()) {
      nextErrors.customerName = "Andika jina lako kamili.";
    }
    if (
      isApartment &&
      (!customerEmail.trim() ||
        !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail.trim()))
    ) {
      nextErrors.customerEmail = "Weka email sahihi.";
    } else if (
      customerEmail.trim() &&
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail.trim())
    ) {
      nextErrors.customerEmail = "Weka email sahihi.";
    }
    if (!isApartment && !customerEmail.trim() && !customerPhoneNumber.trim()) {
      nextErrors.customerPhoneNumber = "Weka email au namba ya simu.";
    }
    if (customerPhoneNumber.trim() && customerPhoneNumber.trim().length < 8) {
      nextErrors.customerPhoneNumber = "Weka namba sahihi.";
    }
    if (isReservable) {
      if (!requestedStartAt || !requestedEndAt) {
        nextErrors.requestedDates = `Chagua ${startLabel.toLowerCase()} na ${endLabel.toLowerCase()}.`;
      } else if (
        new Date(requestedStartAt).getTime() >=
        new Date(requestedEndAt).getTime()
      ) {
        nextErrors.requestedDates =
          "Tarehe ya kutoka lazima iwe baada ya kuingia.";
      }
    }

    setErrors(nextErrors);
    return Object.keys(nextErrors).length === 0;
  }

  function toggleService(key: string) {
    setRequestedServiceCodes((current) =>
      current.includes(key)
        ? current.filter((item) => item !== key)
        : [...current, key],
    );
  }

  async function submitRequest() {
    if (!validateForm()) {
      return;
    }

    setSubmitting(true);
    setErrors({});
    try {
      const parsedGuestCount = guestCount
        ? Number.parseInt(guestCount, 10)
        : undefined;
      if (isReservable) {
        const availabilityResponse = await fetch("/api/check-availability", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            listingId,
            requestedStartAt: new Date(
              usesTime ? requestedStartAt : `${requestedStartAt}T00:00:00`,
            ).toISOString(),
            requestedEndAt: new Date(
              usesTime ? requestedEndAt : `${requestedEndAt}T00:00:00`,
            ).toISOString(),
          }),
        });
        const availabilityPayload = await availabilityResponse.json();
        if (!availabilityResponse.ok) {
          throw new Error(
            availabilityPayload.error ?? "Availability check failed",
          );
        }
        if (availabilityPayload.available !== true) {
          throw new Error(
            availabilityPayload.reason ?? "Haipatikani kwa muda uliochagua.",
          );
        }
      }

      const guestPayload = {
        listing_id: listingId,
        customer_name: customerName,
        customer_email: customerEmail || undefined,
        customer_phone_number: customerPhoneNumber || undefined,
        requested_start_at: isReservable
          ? new Date(
              usesTime ? requestedStartAt : `${requestedStartAt}T00:00:00`,
            ).toISOString()
          : undefined,
        requested_end_at: isReservable
          ? new Date(
              usesTime ? requestedEndAt : `${requestedEndAt}T00:00:00`,
            ).toISOString()
          : undefined,
        guest_count: Number.isFinite(parsedGuestCount)
          ? parsedGuestCount
          : undefined,
        request_message: requestMessage || undefined,
        requested_service_codes: requestedServiceCodes,
      };
      const supabase = getBrowserSupabase();
      const { data: sessionData } = await supabase.auth.getSession();
      let payload: Record<string, unknown>;
      if (sessionData.session) {
        const { data, error } = await supabase.functions.invoke(
          "create-booking-request",
          {
            body: {
              listingId: guestPayload.listing_id,
              customerName: guestPayload.customer_name,
              customerEmail: guestPayload.customer_email,
              customerPhoneNumber: guestPayload.customer_phone_number,
              requestedStartAt: guestPayload.requested_start_at,
              requestedEndAt: guestPayload.requested_end_at,
              guestCount: guestPayload.guest_count,
              requestMessage: guestPayload.request_message,
              requestedServiceCodes: guestPayload.requested_service_codes,
            },
          },
        );
        if (error) throw error;
        payload = (data ?? {}) as Record<string, unknown>;
        setBookingId(
          typeof payload.bookingId === "string" ? payload.bookingId : null,
        );
        setInstantReservation(isReservable);
      } else {
        const response = await fetch("/api/guest-requests", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(guestPayload),
        });
        payload = await response.json();
        if (!response.ok) {
          throw new Error(String(payload.error ?? "Request failed"));
        }
      }
      setRequestReference(
        typeof payload.requestReference === "string"
          ? payload.requestReference
          : null,
      );
    } catch (caughtError) {
      setErrors({
        form:
          caughtError instanceof Error ? caughtError.message : "Request failed",
      });
    } finally {
      setSubmitting(false);
    }
  }

  if (requestReference) {
    return (
      <div
        id="booking"
        className="surface-card scroll-mt-28 rounded-[20px] p-6"
      >
        <span className="status-badge status-active">
          {instantReservation ? "Muda umehifadhiwa" : "Booking imetumwa"}
        </span>
        <p className="mt-4 font-heading text-2xl font-semibold text-brand-ink">
          {instantReservation
            ? "Muda uliochagua umehifadhiwa kwa dakika 30."
            : "Booking yako imetumwa kwa wakala."}
        </p>
        <p className="section-copy mt-3 text-base">
          {instantReservation
            ? "Kamilisha malipo ya reservation sasa kuthibitisha booking. Huhitaji viewing wala kusubiri agent."
            : "Wakala atakujibu kwa email au simu."}
        </p>
        <p className="mt-4 text-sm font-bold text-brand-navy">
          Reference: {requestReference}
        </p>
        {instantReservation && bookingId ? (
          <a
            className="button-primary mt-5 inline-flex"
            href={`/account/request/${bookingId}`}
          >
            Reserve na ulipe sasa
          </a>
        ) : null}
      </div>
    );
  }

  return (
    <div id="booking" className="surface-card scroll-mt-28 rounded-[20px] p-6">
      <p className="eyebrow">Booking</p>
      <h2 className="mt-3 font-heading text-2xl font-semibold text-brand-ink">
        Book {listingTitle}
      </h2>
      <p className="section-copy mt-3 text-sm">
        Chagua muda unaohitaji. Ikiwa muda huo uko wazi, tutauhifadhi kwa dakika
        30 ili ukamilishe malipo. Viewing si lazima na huhitaji kusubiri agent.
      </p>
      <p className="mt-3 text-sm font-semibold text-brand-ink">
        {listingTitle}
      </p>
      <div className="mt-5 grid gap-4">
        <label className="grid gap-2">
          <span className="field-label">Jina kamili</span>
          <input
            value={customerName}
            onChange={(event) => {
              setCustomerName(event.target.value);
              setErrors((current) => ({
                ...current,
                customerName: undefined,
                form: undefined,
              }));
            }}
            placeholder="Mfano: Amina Said"
            aria-invalid={Boolean(errors.customerName)}
            className="field-input"
          />
          {errors.customerName ? (
            <span className="field-error">{errors.customerName}</span>
          ) : null}
        </label>
        <label className="grid gap-2">
          <span className="field-label">
            {isApartment ? "Email" : "Email (si lazima)"}
          </span>
          <input
            value={customerEmail}
            onChange={(event) => {
              setCustomerEmail(event.target.value);
              setErrors((current) => ({
                ...current,
                customerEmail: undefined,
                form: undefined,
              }));
            }}
            placeholder="Mfano: guest@example.com"
            aria-invalid={Boolean(errors.customerEmail)}
            className="field-input"
            type="email"
          />
          {errors.customerEmail ? (
            <span className="field-error">{errors.customerEmail}</span>
          ) : (
            <span className="field-help">
              {isApartment
                ? "Hii ndiyo njia kuu ya mawasiliano kwa wageni wa ndani na wa kimataifa."
                : "Si lazima ikiwa umeweka simu; inasaidia kupata taarifa za booking kwa maandishi."}
            </span>
          )}
        </label>
        <label className="grid gap-2">
          <span className="field-label">
            Namba ya simu / WhatsApp (si lazima)
          </span>
          <input
            value={customerPhoneNumber}
            onChange={(event) => {
              setCustomerPhoneNumber(event.target.value);
              setErrors((current) => ({
                ...current,
                customerPhoneNumber: undefined,
                form: undefined,
              }));
            }}
            placeholder="Mfano: 07xx xxx xxx"
            aria-invalid={Boolean(errors.customerPhoneNumber)}
            className="field-input"
          />
          {errors.customerPhoneNumber ? (
            <span className="field-error">{errors.customerPhoneNumber}</span>
          ) : (
            <span className="field-help">
              {isApartment
                ? "Taarifa hii hutumika kwa WhatsApp au simu ikiwa umeiweka."
                : "Weka simu, email, au zote mbili ili upokee majibu ya booking."}
            </span>
          )}
        </label>
        {isReservable ? (
          <>
            <div className="booking-period-grid grid gap-4">
              <label className="min-w-0 grid gap-2">
                <span className="field-label">{startLabel}</span>
                <input
                  value={requestedStartAt}
                  onChange={(event) => {
                    setRequestedStartAt(event.target.value);
                    setErrors((current) => ({
                      ...current,
                      requestedDates: undefined,
                      form: undefined,
                    }));
                  }}
                  aria-invalid={Boolean(errors.requestedDates)}
                  className="field-input"
                  type={usesTime ? "datetime-local" : "date"}
                />
              </label>
              <label className="min-w-0 grid gap-2">
                <span className="field-label">{endLabel}</span>
                <input
                  value={requestedEndAt}
                  onChange={(event) => {
                    setRequestedEndAt(event.target.value);
                    setErrors((current) => ({
                      ...current,
                      requestedDates: undefined,
                      form: undefined,
                    }));
                  }}
                  aria-invalid={Boolean(errors.requestedDates)}
                  className="field-input"
                  type={usesTime ? "datetime-local" : "date"}
                />
              </label>
            </div>
            {errors.requestedDates ? (
              <span className="field-error">{errors.requestedDates}</span>
            ) : null}
            {isApartment ? (
              <label className="grid gap-2">
                <span className="field-label">Idadi ya wageni (si lazima)</span>
                <input
                  value={guestCount}
                  onChange={(event) => setGuestCount(event.target.value)}
                  className="field-input"
                  inputMode="numeric"
                  type="number"
                  min="1"
                  placeholder="Mfano: 2"
                />
              </label>
            ) : null}
            {isApartment && availableServices.length > 0 ? (
              <div className="grid gap-2">
                <span className="field-label">Services to confirm</span>
                <div className="flex flex-wrap gap-2">
                  {availableServices.map((service) => {
                    const selected = requestedServiceCodes.includes(
                      service.key,
                    );
                    return (
                      <button
                        key={service.key}
                        type="button"
                        onClick={() => toggleService(service.key)}
                        className={`rounded-full border px-4 py-2 text-sm font-semibold transition ${
                          selected
                            ? "border-brand-navy bg-brand-green-soft text-brand-navy"
                            : "border-brand-border-strong bg-brand-card-soft text-brand-navy"
                        }`}
                      >
                        {service.label}
                      </button>
                    );
                  })}
                </div>
              </div>
            ) : null}
            <label className="grid gap-2">
              <span className="field-label">Ujumbe (si lazima)</span>
              <textarea
                value={requestMessage}
                onChange={(event) => setRequestMessage(event.target.value)}
                className="field-input min-h-28"
                placeholder="Mfano: Late check-in, airport pickup, or family stay details"
              />
            </label>
          </>
        ) : null}
        <button
          type="button"
          onClick={submitRequest}
          disabled={submitting}
          className="btn btn-success"
        >
          {submitting ? "Inatuma booking..." : "Book"}
        </button>
        {errors.form ? <p className="field-error">{errors.form}</p> : null}
        <div className="soft-panel p-4">
          <p className="text-sm font-semibold text-brand-ink">Kinachofuata</p>
          <p className="field-help mt-2">
            {isApartment
              ? "Baada ya booking request, wakala atathibitisha tarehe, huduma, bei, na hatua inayofuata kwa email au simu."
              : "Booking ikishatumwa, mmiliki au msimamizi atathibitisha muda, bei na upatikanaji kabla ya malipo."}
          </p>
        </div>
      </div>
    </div>
  );
}
