// Empty query values mean no filter, rather than a numeric zero.
export function optionalNumber(value: string | string[] | undefined, nonNegative = false): number | undefined {
  if (typeof value !== "string" || !value.trim()) return undefined;
  const number = Number(value);
  return Number.isFinite(number) && (!nonNegative || number >= 0) ? number : undefined;
}
