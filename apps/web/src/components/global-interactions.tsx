"use client";

import { useEffect } from "react";

export function GlobalInteractions() {
  useEffect(() => {
    const root = document.documentElement;
    const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
    const move = (event: PointerEvent) => {
      root.style.setProperty("--pointer-x", `${event.clientX}px`);
      root.style.setProperty("--pointer-y", `${event.clientY}px`);
    };
    const ripple = (event: PointerEvent) => {
      if (event.button !== 0 || reducedMotion.matches) return;
      const node = document.createElement("span");
      node.className = "global-water-ripple";
      node.style.left = `${event.clientX}px`;
      node.style.top = `${event.clientY}px`;
      document.body.appendChild(node);
      node.addEventListener("animationend", () => node.remove(), { once: true });
    };
    window.addEventListener("pointermove", move, { passive: true });
    window.addEventListener("pointerdown", ripple, { passive: true });

    const dismissOpenMenus = (event: PointerEvent) => {
      const target = event.target as Node;
      document.querySelectorAll<HTMLDetailsElement>("details[open]").forEach((detail) => {
        if (!detail.contains(target)) detail.open = false;
      });
    };
    const keepOneMenuOpen = (event: Event) => {
      const opened = event.target as HTMLDetailsElement;
      if (!opened.open) return;
      document.querySelectorAll<HTMLDetailsElement>("details[open]").forEach((detail) => {
        if (detail !== opened) detail.open = false;
      });
    };
    document.addEventListener("pointerdown", dismissOpenMenus);
    document.addEventListener("toggle", keepOneMenuOpen, true);

    return () => {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerdown", ripple);
      document.removeEventListener("pointerdown", dismissOpenMenus);
      document.removeEventListener("toggle", keepOneMenuOpen, true);
    };
  }, []);
  return null;
}
