export type LodgeRow = Record<string, unknown>;
export type LodgeField = {
  name: string;
  label: string;
  type?: string;
  required?: boolean;
  options?: string[];
};
import definitions from "../../../../packages/flutter_core/lodge-forms.json";
export const lodgeFormTitles: Record<string, string> = definitions.titles;
export const lodgePermissions = definitions.permissions;
export const lodgePermissionLabels: Record<string, string> =
  definitions.permissionLabels;
export const lodgeSections = definitions.sections;
export const lodgeSectionPermission: Record<string, string> =
  definitions.sectionPermissions;
export const lodgeForms = definitions.forms as Record<string, LodgeField[]>;
export function lodgeFormData(
  form: HTMLFormElement,
  action: string,
  initial: LodgeRow = {},
): LodgeRow {
  const data = new FormData(form),
    result: LodgeRow = {};
  for (const f of lodgeForms[action] ?? []) {
    const raw = String(data.get(f.name) ?? "").trim();
    if (f.type === "checkbox") result[f.name] = data.has(f.name);
    else if (f.type === "rooms" || f.type === "permissions") {
      const values = data.getAll(f.name).map(String);
      if (values.length) result[f.name] = values;
    } else if (f.type === "array")
      result[f.name] = raw
        .split(",")
        .map((x) => x.trim())
        .filter(Boolean);
    else if (raw)
      result[f.name] =
        f.type === "number"
          ? Number(raw)
          : f.type === "datetime-local"
            ? new Date(raw).toISOString()
            : raw;
  }
  if (initial.id) result.id = initial.id;
  if (action === "set_staff") result.profile_id = initial.profile_id;
  return result;
}
