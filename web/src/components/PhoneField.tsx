"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { COUNTRIES, Country, DEFAULT_COUNTRY, detectCountry, flagEmoji } from "./countries";

type Props = {
  // Called with the full E.164 number ("+14155550123") or "" when empty.
  onChange: (e164: string) => void;
  onEnter?: () => void;
};

export default function PhoneField({ onChange, onEnter }: Props) {
  const [country, setCountry] = useState<Country>(DEFAULT_COUNTRY);
  const [national, setNational] = useState("");
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const wrapRef = useRef<HTMLDivElement>(null);
  const searchRef = useRef<HTMLInputElement>(null);

  // Detect the country from the browser locale after mount (keeps SSR markup stable).
  useEffect(() => {
    setCountry(detectCountry());
  }, []);

  const emit = (c: Country, raw: string) => {
    const digits = raw.replace(/\D/g, "");
    onChange(digits ? `+${c.dial}${digits}` : "");
  };

  const onNationalChange = (raw: string) => {
    setNational(raw);
    emit(country, raw);
  };

  const selectCountry = (c: Country) => {
    setCountry(c);
    setOpen(false);
    setQuery("");
    emit(c, national);
  };

  // Close on outside click / Escape.
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    document.addEventListener("mousedown", onDown);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  useEffect(() => {
    if (open) searchRef.current?.focus();
  }, [open]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return COUNTRIES;
    const qDigits = q.replace(/\D/g, "");
    return COUNTRIES.filter(
      (c) =>
        c.name.toLowerCase().includes(q) ||
        c.iso2.toLowerCase().includes(q) ||
        (qDigits.length > 0 && c.dial.startsWith(qDigits)),
    );
  }, [query]);

  return (
    <div ref={wrapRef} className="relative">
      <div className="flex h-12 items-stretch rounded-[8px] border border-hairline bg-bg transition-colors focus-within:border-text/40">
        <button
          type="button"
          aria-label="Select country"
          aria-haspopup="listbox"
          aria-expanded={open}
          onClick={() => setOpen((o) => !o)}
          className="flex shrink-0 items-center gap-1.5 rounded-l-[8px] pl-3.5 pr-2.5 text-text outline-none hover:bg-text/[0.03]"
        >
          <span className="text-[18px] leading-none">{flagEmoji(country.iso2)}</span>
          <span className="text-[15px] font-light text-text-secondary">+{country.dial}</span>
          <svg
            width="10"
            height="6"
            viewBox="0 0 10 6"
            fill="none"
            className={`text-text-secondary transition-transform ${open ? "rotate-180" : ""}`}
            aria-hidden
          >
            <path d="M1 1l4 4 4-4" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </button>
        <span className="my-2.5 w-px bg-hairline" aria-hidden />
        <input
          value={national}
          onChange={(e) => onNationalChange(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && onEnter) onEnter();
          }}
          inputMode="tel"
          autoComplete="tel-national"
          placeholder="415 555 0123"
          className="min-w-0 flex-1 rounded-r-[8px] bg-transparent px-3 text-[18px] font-light outline-none"
        />
      </div>

      {open ? (
        <div
          role="listbox"
          className="absolute left-0 z-30 mt-1 w-full max-w-[340px] overflow-hidden rounded-[10px] border border-hairline bg-bg shadow-[0_12px_40px_rgba(10,10,10,0.12)]"
        >
          <input
            ref={searchRef}
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search country or code"
            className="w-full border-b border-hairline bg-bg px-3.5 py-2.5 text-[14px] font-light outline-none placeholder:text-text-secondary"
          />
          <ul className="max-h-64 overflow-y-auto py-1">
            {filtered.length === 0 ? (
              <li className="px-3.5 py-3 text-[13px] text-text-secondary">No matches</li>
            ) : (
              filtered.map((c) => {
                const active = c.iso2 === country.iso2;
                return (
                  <li key={c.iso2}>
                    <button
                      type="button"
                      onClick={() => selectCountry(c)}
                      className={`flex w-full items-center gap-2.5 px-3.5 py-2 text-left text-[14px] transition-colors hover:bg-text/[0.04] ${
                        active ? "bg-text/[0.04]" : ""
                      }`}
                    >
                      <span className="text-[17px] leading-none">{flagEmoji(c.iso2)}</span>
                      <span className="flex-1 truncate font-light text-text">{c.name}</span>
                      <span className="text-text-secondary">+{c.dial}</span>
                    </button>
                  </li>
                );
              })
            )}
          </ul>
        </div>
      ) : null}
    </div>
  );
}
