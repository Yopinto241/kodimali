"use client";

import { useEffect } from "react";

export function GlobalInteractions() {
  useEffect(() => {
    const root = document.documentElement;
    const move = (event: PointerEvent) => {
      root.style.setProperty("--pointer-x", `${event.clientX}px`);
      root.style.setProperty("--pointer-y", `${event.clientY}px`);
    };
    const ripple = (event: PointerEvent) => {
      if (event.button !== 0 || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
      const node = document.createElement("span");
      node.className = "global-water-ripple";
      node.style.left = `${event.clientX}px`;
      node.style.top = `${event.clientY}px`;
      document.body.appendChild(node);
      node.addEventListener("animationend", () => node.remove(), { once: true });
    };
    window.addEventListener("pointermove", move, { passive: true });
    window.addEventListener("pointerdown", ripple, { passive: true });
    return () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerdown", ripple); };
  }, []);
  return null;
}
