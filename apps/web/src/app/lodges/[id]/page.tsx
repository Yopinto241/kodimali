import { notFound } from "next/navigation";
import { LodgeDiscovery } from "@/components/lodge-discovery";
export const metadata = { title: "Lodge details | KODIMALI" };
export default async function Page({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  if (!/^[0-9a-f-]{36}$/i.test(id)) notFound();
  return <LodgeDiscovery id={id} />;
}
