"use client";

import { createElement, type ComponentProps, type ElementType } from "react";
import Link from "next/link";
import Image from "next/image";
import { useLanguage } from "@/components/language-provider";
import { translateUiText } from "@/lib/ui-translation";

export function UiText({ text }: { text: unknown }) {
  const { language } = useLanguage();
  if (typeof text === "boolean" || text == null) return null;
  return translateUiText(language, text);
}

function LocalizedElement({ element, ...props }: Record<string, unknown> & { element: ElementType }) {
  const { language } = useLanguage();
  const translated = { ...props };
  for (const key of ["placeholder", "title", "aria-label", "alt"]) {
    if (typeof translated[key] === "string") translated[key] = translateUiText(language, translated[key]);
  }
  return createElement(element, translated);
}

export function UiInput(props: ComponentProps<"input">) { return <LocalizedElement element="input" {...props} />; }
export function UiTextarea(props: ComponentProps<"textarea">) { return <LocalizedElement element="textarea" {...props} />; }
export function UiSelect(props: ComponentProps<"select">) { return <LocalizedElement element="select" {...props} />; }
export function UiButton(props: ComponentProps<"button">) { return <LocalizedElement element="button" {...props} />; }
export function UiNav(props: ComponentProps<"nav">) { return <LocalizedElement element="nav" {...props} />; }
export function UiDiv(props: ComponentProps<"div">) { return <LocalizedElement element="div" {...props} />; }
export function UiSection(props: ComponentProps<"section">) { return <LocalizedElement element="section" {...props} />; }
export function UiSpan(props: ComponentProps<"span">) { return <LocalizedElement element="span" {...props} />; }
export function UiA(props: ComponentProps<"a">) { return <LocalizedElement element="a" {...props} />; }
export function UiLink(props: ComponentProps<typeof Link>) { return <LocalizedElement element={Link} {...props} />; }
export function UiImage(props: ComponentProps<typeof Image>) { return <LocalizedElement element={Image} {...props} />; }
