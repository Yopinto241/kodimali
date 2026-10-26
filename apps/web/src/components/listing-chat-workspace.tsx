"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useState } from "react";
import { getBrowserSupabase } from "@/lib/supabase-browser";
import { useLanguage } from "@/components/language-provider";

type Row = Record<string, unknown>;

export function ListingChatWorkspace({
  conversationId,
}: {
  conversationId: string;
}) {
  const supabase = getBrowserSupabase();
  const { language } = useLanguage();
  const sw = language === "sw";
  const [messages, setMessages] = useState<Row[]>([]);
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("Loading chat...");

  const load = useCallback(async () => {
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) throw new Error("Sign in to open this chat.");
    const { data: conversation, error: conversationError } = await supabase.rpc(
      "get_listing_chat_conversation",
      { p_conversation_id: conversationId } as never,
    );
    if (conversationError) throw conversationError;
    const conversationResult = conversation as unknown;
    if (
      !conversationResult ||
      (Array.isArray(conversationResult) && conversationResult.length === 0)
    )
      throw new Error("This chat is unavailable or access has expired.");
    const { data, error } = await supabase.rpc("get_listing_chat_messages", {
      p_conversation_id: conversationId,
    } as never);
    if (error) throw error;
    setMessages((data ?? []) as Row[]);
    setNotice("");
    await supabase.rpc("mark_listing_chat_read", {
      p_conversation_id: conversationId,
    } as never);
  }, [conversationId, supabase]);

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void load().catch((error) => setNotice(readError(error)));
    }, 0);
    return () => window.clearTimeout(timer);
  }, [load]);
  useEffect(() => {
    const channel = supabase
      .channel(`web-listing-chat-${conversationId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "listing_chat_messages",
          filter: `conversation_id=eq.${conversationId}`,
        },
        (payload) => {
          const row = payload.new as Row;
          setMessages((current) =>
            current.some((item) => item.id === row.id)
              ? current
              : [...current, row],
          );
        },
      )
      .subscribe();
    return () => {
      void supabase.removeChannel(channel);
    };
  }, [conversationId, supabase]);

  async function send(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!body.trim()) return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("send_listing_chat_message", {
        p_conversation_id: conversationId,
        p_body: body.trim(),
        p_client_message_id: crypto.randomUUID(),
      } as never);
      if (error) throw error;
      setBody("");
    } catch (error) {
      setNotice(readError(error));
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="surface-card mx-auto flex min-h-[70vh] max-w-4xl flex-col p-6 sm:p-8">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="eyebrow">Private conversation</p>
          <h1 className="mt-2 font-heading text-3xl font-semibold">
            Agent chat
          </h1>
        </div>
        <Link href="/account" className="btn btn-outline">
          Account
        </Link>
      </div>
      <div
        className="my-6 flex-1 space-y-3 overflow-y-auto rounded-3xl bg-brand-card-soft p-4"
        aria-live="polite"
      >
        {messages.length === 0 ? (
          <p className="text-sm text-muted">{notice || "No messages yet."}</p>
        ) : (
          messages.map((message) => (
            <article
              className="rounded-2xl bg-white p-4 shadow-sm"
              key={String(message.id)}
            >
              <p>{String(message.body ?? "")}</p>
              <p className="mt-1 text-xs text-muted">
                {new Date(String(message.created_at)).toLocaleString()}
              </p>
            </article>
          ))
        )}
      </div>
      <form className="flex gap-3" onSubmit={send}>
        <label className="sr-only" htmlFor="listing-chat-message">
          {sw ? "Ujumbe" : "Message"}
        </label>
        <input
          id="listing-chat-message"
          className="field-input min-w-0 flex-1"
          maxLength={2000}
          placeholder={sw ? "Andika ujumbe" : "Write a message"}
          value={body}
          onChange={(event) => setBody(event.target.value)}
        />
        <button className="btn btn-success" disabled={busy}>
          {sw ? "Tuma" : "Send"}
        </button>
      </form>
      {notice && messages.length > 0 ? (
        <p className="mt-3 text-sm text-muted" role="status">
          {notice}
        </p>
      ) : null}
    </section>
  );
}

function readError(error: unknown) {
  return error instanceof Error
    ? error.message
    : "The chat could not be loaded.";
}
