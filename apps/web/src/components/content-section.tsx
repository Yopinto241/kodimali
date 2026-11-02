import { UiText } from "@/components/ui-text";
import type { ReactNode } from "react";

export function ContentSection({
  title,
  children,
}: {
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="surface-card p-6 sm:p-8">
      <h2 className="font-heading text-2xl font-semibold text-brand-ink">
        <UiText text={title} />
      </h2>
      <div className="section-copy mt-4 space-y-3 text-base">{children}</div>
    </section>
  );
}
