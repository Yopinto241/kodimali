"use client";

import { useState } from "react";

export function GuestRequestForm({ listingId }: { listingId: string }) {
  const [customerName, setCustomerName] = useState("");
  const [customerPhoneNumber, setCustomerPhoneNumber] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [requestReference, setRequestReference] = useState<string | null>(null);
  const [errors, setErrors] = useState<{
    customerName?: string;
    customerPhoneNumber?: string;
    form?: string;
  }>({});

  function validateForm() {
    const nextErrors: {
      customerName?: string;
      customerPhoneNumber?: string;
    } = {};

    if (!customerName.trim()) {
      nextErrors.customerName = "Andika jina lako kamili.";
    }
    if (!customerPhoneNumber.trim()) {
      nextErrors.customerPhoneNumber = "Weka namba ya simu au WhatsApp.";
    }

    setErrors(nextErrors);
    return Object.keys(nextErrors).length === 0;
  }

  async function submitRequest() {
    if (!validateForm()) {
      return;
    }

    setSubmitting(true);
    setErrors({});
    try {
      const response = await fetch("/api/guest-requests", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          listing_id: listingId,
          customer_name: customerName,
          customer_phone_number: customerPhoneNumber,
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
          Wakala atakupigia au kukutumia WhatsApp kuthibitisha upatikanaji.
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
        Tuma Ombi
      </h2>
      <p className="section-copy mt-3 text-sm">
        Tuma jina na namba ya simu tu. Baada ya hapo, wakala anayehusika atakufuata
        kwa simu au WhatsApp.
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
          <span className="field-label">Namba ya simu / WhatsApp</span>
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
              Taarifa hii hutumika kurudi kwako kuhusu upatikanaji wa mali.
            </span>
          )}
        </label>
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
            Ombi likishatumwa, wakala atakuthibitishia bei, upatikanaji, na hatua ya
            kuona mali hiyo.
          </p>
        </div>
      </div>
    </div>
  );
}
