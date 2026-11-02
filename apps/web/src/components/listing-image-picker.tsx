"use client";
import { useEffect, useRef, useState } from "react";
import { UiText } from "@/components/ui-text";
import { prepareListingImage } from "@/lib/listing-image";

export type ListingPhoto = { id: string; blob: Blob; preview: string; originalBytes: number };
export function ListingImagePicker({ photos, onChange, onBusy, disabled, limit }: {
  photos: ListingPhoto[]; onChange: (photos: ListingPhoto[]) => void;
  onBusy: (busy: boolean) => void; disabled: boolean; limit: number;
}) {
  const [processing, setProcessing] = useState(false);
  const [error, setError] = useState("");
  const urls = useRef(new Set<string>());
  useEffect(() => { const owned = urls.current; return () => { owned.forEach(URL.revokeObjectURL); }; }, []);
  async function select(files: File[]) {
    if (disabled || processing) return;
    if (files.length + photos.length > limit) { setError("Too many images. Remove an image before adding more."); return; }
    setProcessing(true); onBusy(true); setError("");
    const next = [...photos];
    try {
      for (const file of files) {
        const blob = await prepareListingImage(file);
        const preview = URL.createObjectURL(blob); urls.current.add(preview);
        next.push({ id: crypto.randomUUID(), blob, preview, originalBytes: file.size });
        onChange([...next]);
      }
    } catch { setError("This image could not be prepared. Please choose a JPG, PNG or WebP image smaller than 30 MB."); }
    finally { setProcessing(false); onBusy(false); }
  }
  return <fieldset className="soft-panel grid gap-3 p-4" disabled={disabled || processing}>
    <legend className="font-semibold"><UiText text="Listing images" /></legend>
    <p><UiText text="Images are compressed before upload. The first image is the cover." /> ({photos.length}/{limit})</p>
    <input aria-label="Listing images" type="file" accept="image/jpeg,image/png,image/webp" multiple onChange={(e) => { const files = Array.from(e.target.files ?? []); e.target.value = ""; void select(files); }} />
    {processing && <p role="status"><UiText text="Preparing images..." /></p>}
    {error && <p role="alert"><UiText text={error} /></p>}
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">{photos.map((photo, index) => <div key={photo.id} className="min-w-0 rounded-xl border p-2">
      {/* Local blob previews cannot use the remote image optimizer. */}
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img src={photo.preview} alt={`Image ${index + 1}`} className="aspect-square w-full rounded-lg object-cover" />
      <p className="text-sm">{Math.round(photo.originalBytes / 1024)} KB → {Math.round(photo.blob.size / 1024)} KB</p>
      {index === 0 ? <p><UiText text="Cover image" /></p> : <button type="button" className="underline" onClick={() => onChange([photo, ...photos.filter((p) => p.id !== photo.id)])}><UiText text="Use as cover" /></button>}
      <button type="button" className="mt-2 flex min-h-11 w-full items-center justify-center gap-2 rounded-lg border border-red-300 bg-white px-2 py-2 text-sm font-semibold text-red-800" onClick={() => { URL.revokeObjectURL(photo.preview); urls.current.delete(photo.preview); onChange(photos.filter((p) => p.id !== photo.id)); }}><span aria-hidden="true">×</span><UiText text="Remove image" /></button>
    </div>)}</div>
  </fieldset>;
}
