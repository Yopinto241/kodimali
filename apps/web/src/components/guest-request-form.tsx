"use client";

import { useState } from "react";

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
  const [customerName, setCustomerName] = useState("");
  const [customerEmail, setCustomerEmail] = useState("");
  const [customerPhoneNumber, setCustomerPhoneNumber] = useState("");
  const [requestedStartAt, setRequestedStartAt] = useState("");
  const [requestedEndAt, setRequestedEndAt] = useState("");
  const [guestCount, setGuestCount] = useState("");
  const [requestMessage, setRequestMessage] = useState("");
  const [requestedServiceCodes, setRequestedServiceCodes] = useState<string[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [requestReference, setRequestReference] = useState<string | null>(null);
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
      (!customerEmail.trim() || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(customerEmail.trim()))
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
    if (isApartment) {
      if (!requestedStartAt || !requestedEndAt) {
        nextErrors.requestedDates = "Chagua tarehe za kuingia na kutoka.";
      } else if (new Date(requestedStartAt).getTime() >= new Date(requestedEndAt).getTime()) {
        nextErrors.requestedDates = "Tarehe ya kutoka lazima iwe baada ya kuingia.";
      }
    }

    setErrors(nextErrors);
    return Object.keys(nextErrors).length === 0;
  }

  function toggleService(key: string) {
    setRequestedServiceCodes((current) =>
      current.includes(key) ? current.filter((item) => item !== key) : [...current, key],
    );
  }

  async function submitRequest() {
    if (!validateForm()) {
      return;
    }

    setSubmitting(true);
    setErrors({});
    try {
      const parsedGuestCount = guestCount ? Number.parseInt(guestCount, 10) : undefined;
      if (isApartment) {
        const availabilityResponse = await fetch("/api/check-availability", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            listingId,
            requestedStartAt: `${requestedStartAt}T00:00:00.000Z`,
            requestedEndAt: `${requestedEndAt}T00:00:00.000Z`,
          }),
        });
        const availabilityPayload = await availabilityResponse.json();
        if (!availabilityResponse.ok) {
          throw new Error(availabilityPayload.error ?? "Availability check failed");
        }
        if (availabilityPayload.available !== true) {
          throw new Error(
            availabilityPayload.reason ?? "Apartment haipatikani kwa tarehe ulizochagua.",
          );
        }
      }

      const response = await fetch("/api/guest-requests", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          listing_id: listingId,
          customer_name: customerName,
          customer_email: customerEmail || undefined,
          customer_phone_number: customerPhoneNumber || undefined,
          requested_start_at: isApartment
            ? `${requestedStartAt}T00:00:00.000Z`
            : undefined,
          requested_end_at: isApartment
            ? `${requestedEndAt}T00:00:00.000Z`
            : undefined,
          guest_count: Number.isFinite(parsedGuestCount) ? parsedGuestCount : undefined,
          request_message: requestMessage || undefined,
          requested_service_codes: requestedServiceCodes,
        }),
      });
      const payload = await response.json();
      if (!response.ok) {
        throw new Error(payload.error ?? "Request failed");
      }
      setRequestReference(payload.requestReference ?? null);
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
      <div className="surface-card rounded-[20px] p-6">
        <span className="status-badge status-active">Request sent</span>
        <p className="mt-4 font-heading text-2xl font-semibold text-brand-ink">
          Ombi lako limetumwa kwa wakala.
        </p>
        <p className="section-copy mt-3 text-base">
          Wakala atakujibu kwa email au simu kuthibitisha upatikanaji.
        </p>
        <p className="mt-4 text-sm font-bold text-brand-navy">
          Reference: {requestReference}
        </p>
      </div>
    );
  }

  return (
    <div className="surface-card rounded-[20px] p-6">
      <p className="eyebrow">Secure request</p>
      <h2 className="mt-3 font-heading text-2xl font-semibold text-brand-ink">
        {isApartment ? "Book Apartment" : "Tuma Ombi"}
      </h2>
      <p className="section-copy mt-3 text-sm">
        {isApartment
          ? "Chagua tarehe za kukaa, acha email yako, na chagua huduma unazotaka wakala athibitishe."
          : "Tuma jina lako na uache email au namba ya simu. Wakala atakufuata kwa email au simu."}
      </p>
      <p className="mt-3 text-sm font-semibold text-brand-ink">{listingTitle}</p>
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
          <span className="field-label">{isApartment ? "Email" : "Email (optional)"}</span>
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
                : "Optional, but useful for international guests and written follow-up."}
            </span>
          )}
        </label>
        <label className="grid gap-2">
          <span className="field-label">Namba ya simu / WhatsApp (optional)</span>
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
                : "Optional. Add phone, email, or both so the agent can reach you."}
            </span>
          )}
        </label>
        {isApartment ? (
          <>
            <div className="grid gap-4 sm:grid-cols-2">
              <label className="grid gap-2">
                <span className="field-label">Check-in</span>
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
                  type="date"
                />
              </label>
              <label className="grid gap-2">
                <span className="field-label">Check-out</span>
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
                  type="date"
                />
              </label>
            </div>
            {errors.requestedDates ? (
              <span className="field-error">{errors.requestedDates}</span>
            ) : null}
            <label className="grid gap-2">
              <span className="field-label">Guests (optional)</span>
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
            {availableServices.length > 0 ? (
              <div className="grid gap-2">
                <span className="field-label">Services to confirm</span>
                <div className="flex flex-wrap gap-2">
                  {availableServices.map((service) => {
                    const selected = requestedServiceCodes.includes(service.key);
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
              <span className="field-label">Message (optional)</span>
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
          {submitting ? "Inatuma..." : "Tuma Ombi"}
        </button>
        {errors.form ? <p className="field-error">{errors.form}</p> : null}
        <div className="soft-panel p-4">
          <p className="text-sm font-semibold text-brand-ink">Kinachofuata</p>
          <p className="field-help mt-2">
            {isApartment
              ? "Baada ya booking request, wakala atathibitisha tarehe, huduma, bei, na hatua inayofuata kwa email au simu."
              : "Ombi likishatumwa, wakala atakuthibitishia bei, upatikanaji, na hatua ya kuona mali hiyo."}
          </p>
        </div>
      </div>
    </div>
  );
}
