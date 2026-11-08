import type { ReactNode } from "react";
import type { Tone } from "./verdict";

export function Pill({ tone, children }: { tone: Tone; children: ReactNode }) {
  return <span className={`pill ${tone}`}>{children}</span>;
}

export function Card({ title, aside, children }: { title?: ReactNode; aside?: ReactNode; children: ReactNode }) {
  return (
    <section className="card">
      {(title || aside) && <div className="cardhead">{title && <h2>{title}</h2>}{aside && <div className="aside">{aside}</div>}</div>}
      {children}
    </section>
  );
}

export function Stat({ label, value, tone }: { label: string; value: ReactNode; tone?: Tone }) {
  return <div className={`stat ${tone ?? ""}`}><div className="statv">{value}</div><div className="statl">{label}</div></div>;
}

export function Empty({ children }: { children: ReactNode }) { return <p className="empty">{children}</p>; }

export const fmtAge = (s: number) => (s < 90 ? `${s}s` : s < 5400 ? `${Math.round(s / 60)}m` : s < 172800 ? `${(s / 3600).toFixed(1)}h` : `${Math.round(s / 86400)}d`);
export const fmtUsd = (v: bigint, dec = 6) => `$${Number(v) / 10 ** dec >= 1e9 ? "∞" : (Number(v) / 10 ** dec).toLocaleString(undefined, { maximumFractionDigits: 2 })}`;
export const fmtDate = (sec: number | bigint) => new Date(Number(sec) * 1000).toISOString().replace("T", " ").slice(0, 16) + " UTC";
export const DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
/** Seconds after Monday 00:00 UTC, as a weekday and time. */
export const fmtWeekOffset = (s: number) => `${DAYS[Math.floor(s / 86400) % 7]} ${String(Math.floor((s % 86400) / 3600)).padStart(2, "0")}:${String(Math.floor((s % 3600) / 60)).padStart(2, "0")} UTC`;
export const basescan = (a: string) => `https://basescan.org/address/${a}`;
