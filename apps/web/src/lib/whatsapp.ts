export function normalizeWhatsAppNumber(phone?: string | null): string | null {
  if (!phone || !/^[+\d ().-]+$/.test(phone.trim())) return null;
  let digits = phone.replace(/\D/g, "");
  if (/^0+$/.test(digits)) return null;
  if (digits.startsWith("00")) digits = digits.slice(2);
  if (digits.length === 10 && digits.startsWith("0")) digits = "255" + digits.slice(1);
  else if (digits.length === 9 && /^[67]/.test(digits)) digits = "255" + digits;
  if (!/^[1-9]\d{7,14}$/.test(digits) || (digits.startsWith("255") && digits.length !== 12)) return null;
  return digits;
}
export function whatsAppUrl(phone?: string | null) {
  const number = normalizeWhatsAppNumber(phone);
  return number ? `https://wa.me/${number}` : null;
}
