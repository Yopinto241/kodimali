export const serviceKinds: Record<string, [string, string]> = {
  mc_host: ["MC / host", "MC / mshereheshaji"],
  dj: ["DJ", "DJ"],
  performer: ["Performer", "Msanii"],
  choir_group: ["Choir / group", "Kwaya / kikundi"],
  photographer: ["Photographer", "Mpiga picha"],
  videographer: ["Videographer", "Mpiga video"],
  planner: ["Event planner", "Mpangaji wa tukio"],
  decorator: ["Decorator", "Mpambaji"],
  caterer: ["Catering", "Huduma ya chakula"],
  cook: ["Cook", "Mpishi"],
  usher: ["Usher", "Mkaribishaji"],
  hospitality: ["Hospitality", "Ukarimu"],
  cleaning_team: ["Cleaning team", "Usafi"],
  transport_delivery: ["Transport / delivery", "Usafiri / usafirishaji"],
  other: ["Other services", "Huduma nyingine"],
};
export function serviceLabel(kind: unknown, sw: boolean) {
  return (
    serviceKinds[String(kind)]?.[sw ? 1 : 0] ?? (sw ? "Huduma" : "Service")
  );
}
export function priceUnit(unit: unknown, sw: boolean) {
  const labels: Record<string, [string, string]> = {
    item_hour: ["per item / hour", "kwa kifaa / saa"],
    item_day: ["per item / day", "kwa kifaa / siku"],
    item_event: ["per item / event", "kwa kifaa / tukio"],
    per_day: ["per day", "kwa siku"],
    day: ["per day", "kwa siku"],
    per_hour: ["per hour", "kwa saa"],
    hour: ["per hour", "kwa saa"],
    per_item: ["per item", "kwa kifaa"],
    per_event: ["per event", "kwa tukio"],
    fixed: ["fixed price", "bei maalumu"],
    per_person: ["per person", "kwa mtu"],
    per_session: ["per session", "kwa kipindi"],
    per_trip: ["per trip", "kwa safari"],
  };
  return (
    labels[String(unit)]?.[sw ? 1 : 0] ??
    (sw ? "kipimo kitathibitishwa" : "unit confirmed in quote")
  );
}
export function eventPrice(item: Record<string, unknown>, sw: boolean) {
  if (item.price_amount_tzs == null) return sw ? "Omba bei" : "Request a quote";
  const amount = `TZS ${Number(item.price_amount_tzs).toLocaleString("en-TZ")}`;
  return item.price_unit
    ? `${amount} / ${priceUnit(item.price_unit, sw)}`
    : `${sw ? "Kuanzia" : "From"} ${amount}`;
}
export function validEventPeriod(start: string, end: string) {
  return Boolean(
    start &&
    end &&
    Number.isFinite(Date.parse(start)) &&
    Number.isFinite(Date.parse(end)) &&
    Date.parse(end) > Date.parse(start),
  );
}
