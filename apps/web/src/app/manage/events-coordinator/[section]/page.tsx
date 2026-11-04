import { notFound } from "next/navigation";
import { EventOperations } from "@/components/event-operations";
import { coordinatorEventViews } from "@/lib/event-operation-routes";
export default async function Page({params}:{params:Promise<{section:string}>}) { const {section}=await params; if (!(coordinatorEventViews as readonly string[]).includes(section)) notFound(); return <EventOperations mode="coordinator" view={section}/>; }
