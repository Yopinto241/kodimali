"use client";
import { UiSelect, UiText } from "@/components/ui-text";

import { useNavigate } from "@/components/navigation-progress";

type Category = { id: string; slug: string; name: string };

export function CategoryRouteSelect({ categories, value, label }: { categories: Category[]; value: string; label: string }) {
  const navigate = useNavigate();
  return (
    <label className="category-route-picker">
      <span><UiText text={label} /></span>
      <UiSelect value={value} aria-label={label} onChange={(event) => {
        const next = event.target.value;
        navigate(next === "events" ? "/events" : `/category/${next}`);
      }}>
        {categories.map((category) => <option key={category.id} value={category.slug}><UiText text={category.name} /></option>)}
        <option value="events"><UiText text={"Sherehe na Matukio"} /></option>
      </UiSelect>
    </label>
  );
}
