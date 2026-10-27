"use client";

import { useRouter } from "next/navigation";

type Category = { id: string; slug: string; name: string };

export function CategoryRouteSelect({ categories, value, label }: { categories: Category[]; value: string; label: string }) {
  const router = useRouter();
  return (
    <label className="category-route-picker">
      <span>{label}</span>
      <select value={value} aria-label={label} onChange={(event) => {
        const next = event.target.value;
        router.push(next === "events" ? "/events" : `/category/${next}`);
      }}>
        {categories.map((category) => <option key={category.id} value={category.slug}>{category.name}</option>)}
        <option value="events">Sherehe na Matukio</option>
      </select>
    </label>
  );
}
