import { notFound } from "next/navigation";
import { LodgeWorkspace } from "@/components/lodge-workspace";
import { lodgeSections } from "@/lib/lodge-forms";
export default async function Page({
  params,
}: {
  params: Promise<{ id: string; section: string }>;
}) {
  const { id, section } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id) || !lodgeSections.includes(section))
    notFound();
  return (
    <LodgeWorkspace key={`${id}/${section}`} lodgeId={id} section={section} />
  );
}
