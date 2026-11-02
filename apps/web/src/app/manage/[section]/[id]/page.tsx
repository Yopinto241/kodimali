import { notFound } from 'next/navigation';
import { ManagePortal } from '@/components/manage-portal';

export default async function ManageRecordPage({ params, searchParams }: {
  params: Promise<{ section: string; id: string }>;
  searchParams: Promise<Record<string, string | string[] | undefined>>;
}) {
  const { section, id } = await params;
  if (!['users', 'listings'].includes(section) || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) notFound();
  const query = await searchParams;
  return <ManagePortal requestedSection={section as 'users' | 'listings'} recordId={id} preferredRole={query.workspace === 'agent' ? 'agent' : undefined} />;
}
