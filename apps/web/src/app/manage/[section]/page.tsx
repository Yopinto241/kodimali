import { notFound } from 'next/navigation';
import { ManagePortal } from '@/components/manage-portal';
import { isManageSection } from '@/lib/manage-routes';

export default async function ManagementPage({ params, searchParams }: {
  params: Promise<{ section: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { section } = await params;
  if (!isManageSection(section)) notFound();
  const query = await searchParams;
  return <ManagePortal requestedSection={section} preferredRole={query.workspace === 'agent' ? 'agent' : undefined} />;
}
