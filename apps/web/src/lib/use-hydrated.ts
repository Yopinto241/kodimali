"use client";
import { useSyncExternalStore } from "react";
const subscribe = () => () => {};
const client = () => true;
const server = () => false;
/** Do not accept filter interactions before their client handlers are attached. */
export function useHydrated() { return useSyncExternalStore(subscribe, client, server); }
