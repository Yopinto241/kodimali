"use client";

import Link from "next/link";
import { FormEvent, useCallback, useEffect, useRef, useState } from "react";
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
  const [conversation, setConversation] = useState<Row | null>(null);
  const [userId, setUserId] = useState("");
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("Loading chat...");
  const bottomRef = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    const { data: auth } = await supabase.auth.getUser();
    if (!auth.user) throw new Error("Sign in to open this chat.");
    setUserId(auth.user.id);
    const { data: conversation, error: conversationError } = await supabase.rpc(
      "get_listing_chat_conversation",
      { p_conversation_id: conversationId } as never,
    );
    if (conversationError) throw conversationError;
    const conversationResult = conversation as unknown;
    if (!conversationResult || (Array.isArray(conversationResult) && conversationResult.length === 0))
      throw new Error("This chat is unavailable or access has expired.");
    setConversation((Array.isArray(conversationResult) ? conversationResult[0] : conversationResult) as Row);
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
    bottomRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [messages]);

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
    <section className="chat-shell mx-auto flex h-[calc(100dvh-10rem)] min-h-[620px] max-w-4xl flex-col overflow-hidden">
      <div className="chat-header flex items-center gap-3 px-4 py-3 sm:px-5">
        <Link href="/account" className="chat-icon-button" aria-label={sw ? "Rudi" : "Back"}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m15 18-6-6 6-6" /></svg>
        </Link>
        <div className="chat-avatar" aria-hidden="true">
          {String(conversation?.agent_name ?? "A").slice(0, 1).toUpperCase()}
        </div>
        <div className="min-w-0 flex-1">
          <h1 className="truncate text-base font-bold text-white sm:text-lg">
            {String(conversation?.agent_name ?? (sw ? "Wakala" : "Agent"))}
          </h1>
          <p className="truncate text-xs text-white/75">
            {String(conversation?.listing_title ?? (sw ? "Mazungumzo ya mali" : "Listing conversation"))}
          </p>
        </div>
        <span className="hidden rounded-full bg-white/10 px-3 py-1 text-xs font-semibold text-white/80 sm:inline">
          {sw ? "Faragha" : "Private"}
        </span>
      </div>
      <div
        className="chat-message-area flex-1 space-y-2 overflow-y-auto px-3 py-5 sm:px-6"
        aria-live="polite"
      >
        {messages.length === 0 ? (
          <div className="mx-auto mt-10 max-w-sm rounded-xl bg-[#fff7c7] px-4 py-3 text-center text-sm text-[#4b4b3a] shadow-sm">
            {notice || (sw ? "Anza mazungumzo na wakala." : "Start the conversation with the agent.")}
          </div>
        ) : (
          messages.map((message) => {
            const mine = String(message.sender_id ?? "") === userId;
            return (
              <article className={`chat-bubble ${mine ? "chat-bubble-mine" : "chat-bubble-theirs"}`} key={String(message.id)}>
                <p className="whitespace-pre-wrap break-words text-[15px] leading-5">{String(message.body ?? "")}</p>
                <div className="mt-1 flex items-center justify-end gap-1 text-[10px] text-[#667781]">
                  <time>{formatChatTime(message.created_at, language)}</time>
                  {mine ? <span className={message.read_at ? "text-[#53bdeb]" : ""} aria-label={message.read_at ? "Read" : "Sent"}>✓✓</span> : null}
                </div>
              </article>
            );
          })
        )}
        <div ref={bottomRef} />
      </div>
      <form className="chat-composer flex items-end gap-2 p-2.5 sm:p-3" onSubmit={send}>
        <label className="sr-only" htmlFor="listing-chat-message">
          {sw ? "Ujumbe" : "Message"}
        </label>
        <textarea
          id="listing-chat-message"
          className="chat-input min-h-11 min-w-0 flex-1 resize-none"
          maxLength={2000}
          rows={1}
          placeholder={sw ? "Andika ujumbe…" : "Write a message…"}
          value={body}
          onChange={(event) => setBody(event.target.value)}
          onKeyDown={(event) => {
            if (event.key === "Enter" && !event.shiftKey) {
              event.preventDefault();
              event.currentTarget.form?.requestSubmit();
            }
          }}
        />
        <button className="chat-send-button" disabled={busy || !body.trim()} aria-label={sw ? "Tuma" : "Send"}>
          <svg viewBox="0 0 24 24" aria-hidden="true"><path d="m4 4 16 8-16 8 3-8-3-8Zm3 8h13" /></svg>
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

function formatChatTime(value: unknown, language: string) {
  const date = new Date(String(value ?? ""));
  if (Number.isNaN(date.getTime())) return "";
  return new Intl.DateTimeFormat(language === "sw" ? "sw-TZ" : "en-GB", {
    hour: "2-digit",
    minute: "2-digit",
  }).format(date);
}

function readError(error: unknown) {
  return error instanceof Error
    ? error.message
    : "The chat could not be loaded.";
}
