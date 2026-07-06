export const categories = [
  "Houses",
  "Cars",
  "Motorcycles",
  "Offices",
  "Meeting halls",
  "Ceremony halls",
];

export const flowSteps = [
  "Customer browses active listings without creating an account.",
  "Customer sends a guest request using only name and phone number.",
  "The backend copies listings.agent_id into booking_requests.agent_id.",
  "Only that agent receives the operational notification and responds.",
  "Agent follows up by call or WhatsApp to confirm the next step.",
];

export const launchRules = [
  "Start in Arusha first.",
  "Protect against fake agents, fake media, and fake listings.",
  "Do overlap validation in the backend, not only in the client.",
  "Delay payments, SMS, maps, and chat until the core workflow is stable.",
];

export const roleCards = [
  {
    title: "Customer App",
    description:
      "Browse public listings, use location filters, and send guest requests safely.",
    href: "/account",
  },
  {
    title: "Manage App",
    description:
      "One shared management app that opens Agent or Admin dashboard after login.",
    href: "/manage",
  },
  {
    title: "Website",
    description:
      "Public marketplace powered by the same backend with no customer login required.",
    href: "/listings",
  },
];

export const statusFlow = [
  "New",
  "Checking Availability",
  "Contacted",
  "Viewing Scheduled",
  "Reserved",
  "Confirmed",
  "Completed",
  "Cancelled",
  "Rejected",
  "No Response",
  "Agent Delayed",
];

export const mediaRules = [
  "Maximum 8 images",
  "Maximum 1 video",
  "Video max 30 seconds",
  "Video max 30 MB",
];
