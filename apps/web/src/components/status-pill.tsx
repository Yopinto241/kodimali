type StatusPillProps = {
  label: string;
  tone?: "active" | "pending" | "danger" | "muted" | "info";
};

const toneClasses = {
  active: "status-active",
  pending: "status-pending",
  danger: "status-danger",
  muted: "status-muted",
  info: "status-info",
} as const;

export function StatusPill({
  label,
  tone = "info",
}: StatusPillProps) {
  return (
    <span className={`status-badge ${toneClasses[tone]}`}>
      {label}
    </span>
  );
}
