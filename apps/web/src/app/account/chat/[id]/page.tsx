import { ListingChatWorkspace } from "@/components/listing-chat-workspace";
import { PageShell } from "@/components/page-shell";

export default async function ListingChatPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  return <PageShell className="account-shell pb-20"><ListingChatWorkspace conversationId={id} /></PageShell>;
}
