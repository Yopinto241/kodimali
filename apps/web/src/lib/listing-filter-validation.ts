export function priceFilterError(min: string, max: string): string | null {
  if ([min, max].some((value) => value.trim() && (!Number.isFinite(Number(value)) || Number(value) < 0))) return "Enter a valid price of zero or more.";
  if (min.trim() && max.trim() && Number(min) > Number(max)) return "Maximum price must be greater than or equal to minimum price.";
  return null;
}

export function validateListingFilterForm(form: HTMLFormElement) {
  const minimum = form.querySelector<HTMLInputElement>('input[name="minPrice"]');
  const maximum = form.querySelector<HTMLInputElement>('input[name="maxPrice"]');
  const invalid = [minimum, maximum].find((input) => input && !input.validity.valid);
  const message = invalid ? "Enter a valid price of zero or more." : priceFilterError(minimum?.value ?? "", maximum?.value ?? "");
  if (!message) return null;
  return { message, input: invalid ?? maximum ?? minimum };
}

export function revealListingFilterError(form: HTMLFormElement, problem: NonNullable<ReturnType<typeof validateListingFilterForm>>) {
  const panel = problem.input?.closest("details");
  if (panel) panel.open = true;
  form.dispatchEvent(new CustomEvent("kodimali-filter-error", { detail: problem.message }));
  problem.input?.focus();
}
