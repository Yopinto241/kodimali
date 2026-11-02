"use client";
import { usePathname } from 'next/navigation';
import type { ReactNode } from 'react';

export function PublicSiteChrome({ children }: { children: ReactNode }) {
  const path = usePathname();
  if (path === '/manage' || path.startsWith('/manage/') && !path.startsWith('/manage/register/') || path === '/admin' || path === '/agent') return null;
  return children;
}
