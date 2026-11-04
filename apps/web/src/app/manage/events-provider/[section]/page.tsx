import { notFound } from "next/navigation";
import { EventOperations } from "@/components/event-operations";
import { providerEventViews } from "@/lib/event-operation-routes";
export default async function Page({params}:{params:Promise<{section:string}>}) { const {section}=await params; if (!(providerEventViews as readonly string[]).includes(section)) notFound(); return <EventOperations mode="provider" view={section}/>; }
