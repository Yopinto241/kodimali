import type { ReactNode } from "react";

export function PageShell({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <main
      className={`app-shell min-h-[calc(100vh-76px)] py-6 sm:py-8 md:py-10 ${className}`.trim()}
    >
      {children}
    </main>
  );
}
