/** Decode before upload so unsupported/corrupt files never become fake JPEGs. */
export async function prepareListingImage(file: File): Promise<Blob> {
  if (!file.size || file.size > 30 * 1024 * 1024) throw new Error("Choose an image smaller than 30 MB.");
  const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" });
  try {
    const scale = Math.min(1, 1920 / Math.max(bitmap.width, bitmap.height));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const context = canvas.getContext("2d");
    if (!context) throw new Error("Image processing unavailable");
    context.fillStyle = "#ffffff";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    let blob: Blob | null = null;
    for (const quality of [0.84, 0.76, 0.68]) {
      blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, "image/jpeg", quality));
      if (blob && blob.size <= 420 * 1024) break;
    }
    if (!blob || blob.type !== "image/jpeg" || blob.size > 30 * 1024 * 1024) throw new Error("Image processing failed");
    return blob;
  } finally { bitmap.close(); }
}
