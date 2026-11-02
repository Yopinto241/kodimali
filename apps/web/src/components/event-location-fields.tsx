"use client";
import { UiSelect, UiText } from "@/components/ui-text";
import { useEffect, useRef, useState } from "react";
import { useLanguage } from "@/components/language-provider";
import { getBrowserSupabase } from "@/lib/supabase-browser";
type Option = {
  id: string;
  name: string;
  location_type?: string;
  parent_id?: string | null;
};
const levels = ["region", "district", "ward", "area"];
export function EventLocationFields({
  value,
  onChange,
  inputName,
  required = false,
  onLabelChange,
}: {
  value: string;
  onChange: (id: string) => void;
  inputName?: string;
  required?: boolean;
  onLabelChange?: (label: string) => void;
}) {
  const { language } = useLanguage();
  const sw = language === "sw";
  const [selected, setSelected] = useState<string[]>(["", "", "", ""]);
  const [options, setOptions] = useState<Option[][]>([[], [], [], []]);
  const [error, setError] = useState("");
  const [loading, setLoading] = useState(false);
  const latest = useRef(0);
  const ownValue = useRef("");
  const initial = useRef(true);
  useEffect(() => {
    if (!initial.current && ownValue.current === value) return;
    initial.current = false;
    ownValue.current = value;
    const request = ++latest.current;
    setLoading(true);
    setError("");
    void (async () => {
      const db = getBrowserSupabase();
      const country = await db
        .from("locations")
        .select("id")
        .eq("location_type", "country")
        .eq("is_active", true)
        .limit(1)
        .maybeSingle();
      if (country.error || !country.data)
        throw new Error(
          sw ? "Imeshindwa kupakia maeneo." : "Could not load locations.",
        );
      const countryId = String((country.data as { id: string }).id);
      const chain: Option[] = [];
      let id = value;
      while (id && chain.length < 5) {
        const r = await db
          .from("locations")
          .select("id,name,location_type,parent_id")
          .eq("id", id)
          .maybeSingle();
        if (r.error || !r.data)
          throw new Error(
            sw ? "Chagua eneo tena." : "Please choose your location again.",
          );
        const item = r.data as Option;
        chain.unshift(item);
        id = item.parent_id ?? "";
      }
      const ids = levels.map(
        (level) => chain.find((item) => item.location_type === level)?.id ?? "",
      );
      const all = await Promise.all(
        levels.map(async (level, i) => {
          const parent =
            i === 0 ? countryId : i === 3 ? ids[2] || ids[1] : ids[i - 1];
          if (!parent) return [];
          const r = await fetch(
            `/api/locations?locationType=${level}&parentId=${parent}`,
          );
          if (!r.ok)
            throw new Error(
              sw ? "Imeshindwa kupakia maeneo." : "Could not load locations.",
            );
          return (await r.json()) as Option[];
        }),
      );
      if (request === latest.current) {
        setSelected(ids);
        setOptions(all);
      }
    })()
      .catch((e) => {
        if (request === latest.current) setError(e.message);
      })
      .finally(() => {
        if (request === latest.current) setLoading(false);
      });
  }, [value, sw]);
  async function choose(index: number, id: string) {
    const ids = selected.map((old, i) =>
      i < index ? old : i === index ? id : "",
    );
    const nextOptions = options.map((old, i) => (i <= index ? old : []));
    setSelected(ids);
    setOptions(nextOptions);
    const next = [...ids].reverse().find(Boolean) ?? "";
    ownValue.current = next;
    onChange(next);
    onLabelChange?.(
      ids
        .map((v, i) => options[i].find((o) => o.id === v)?.name)
        .filter(Boolean)
        .join(" / "),
    );
    if (index === 3 || (!id && index !== 2)) return;
    const request = ++latest.current;
    setLoading(true);
    setError("");
    try {
      const parent = id || selected[1];
      const r = await fetch(
        `/api/locations?locationType=${levels[index + 1]}&parentId=${parent}`,
      );
      if (!r.ok)
        throw new Error(
          sw ? "Imeshindwa kupakia maeneo." : "Could not load locations.",
        );
      const children = (await r.json()) as Option[];
      let directAreas: Option[] = [];
      if (index === 1) {
        const a = await fetch(
          `/api/locations?locationType=area&parentId=${id}`,
        );
        if (!a.ok)
          throw new Error(
            sw ? "Imeshindwa kupakia maeneo." : "Could not load locations.",
          );
        directAreas = (await a.json()) as Option[];
      }
      if (request === latest.current)
        setOptions((current) =>
          current.map((old, i) =>
            i === index + 1
              ? children
              : index === 1 && i === 3
                ? directAreas
                : old,
          ),
        );
    } catch (e) {
      if (request === latest.current) setError((e as Error).message);
    } finally {
      if (request === latest.current) setLoading(false);
    }
  }
  return (
    <div>
      <div className="grid gap-3 sm:grid-cols-2">
        {inputName ? (
          <input type="hidden" name={inputName} value={value} />
        ) : null}
        {levels.map((level, i) =>
          i === 0 || (i === 3 ? selected[1] : selected[i - 1]) ? (
            <label
              className="grid min-w-0 gap-2 text-sm font-semibold"
              key={level}
            >
              <span>
                {
                  (sw
                    ? ["Mkoa", "Wilaya", "Kata (si lazima)", "Eneo (si lazima)"]
                    : [
                        "Region",
                        "District",
                        "Ward (optional)",
                        "Area (optional)",
                      ])[i]
                }
              </span>
              <UiSelect
                aria-label={
                  (sw
                    ? ["Mkoa", "Wilaya", "Kata (si lazima)", "Eneo (si lazima)"]
                    : [
                        "Region",
                        "District",
                        "Ward (optional)",
                        "Area (optional)",
                      ])[i]
                }
                className="field-input"
                value={selected[i]}
                disabled={loading}
                required={required && i < 2}
                onChange={(e) => void choose(i, e.target.value)}
              >
                <option value=""><UiText text={sw ? "Chagua" : "Choose"} /></option>
                {options[i].map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.name}
                  </option>
                ))}
              </UiSelect>
            </label>
          ) : null,
        )}
      </div>
      {loading ? (
        <p className="mt-2 text-sm" role="status">
          <UiText text={sw ? "Inapakia maeneo..." : "Loading locations..."} />
        </p>
      ) : null}
      {error ? (
        <p className="event-error mt-2" role="alert">
          <UiText text={error} />
        </p>
      ) : null}
    </div>
  );
}
