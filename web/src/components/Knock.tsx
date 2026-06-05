"use client";

import { useEffect, useRef } from "react";

// A "knock" is a lightweight, real-time presence ping: the caller taps a rhythm,
// each tap is relayed over the signaling socket, and the callee hears + feels the
// same taps as they land. No call row, no ringtone loop — it only "rings" while
// someone is actively knocking.

// Synthesize a knuckle-on-door knock with WebAudio (no asset needed):
// a fast low "thud" body + a high-passed noise "click" attack.
export function playKnock(ctx: AudioContext | null) {
  if (!ctx) return;
  const t = ctx.currentTime;

  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = "sine";
  osc.frequency.setValueAtTime(180, t);
  osc.frequency.exponentialRampToValueAtTime(90, t + 0.08);
  gain.gain.setValueAtTime(0.0001, t);
  gain.gain.exponentialRampToValueAtTime(0.6, t + 0.005);
  gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.18);
  osc.connect(gain);
  gain.connect(ctx.destination);
  osc.start(t);
  osc.stop(t + 0.2);

  const frames = Math.floor(ctx.sampleRate * 0.03);
  const buf = ctx.createBuffer(1, frames, ctx.sampleRate);
  const data = buf.getChannelData(0);
  for (let i = 0; i < frames; i++) {
    data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / frames, 3);
  }
  const noise = ctx.createBufferSource();
  noise.buffer = buf;
  const ng = ctx.createGain();
  ng.gain.value = 0.25;
  const hp = ctx.createBiquadFilter();
  hp.type = "highpass";
  hp.frequency.value = 1200;
  noise.connect(hp);
  hp.connect(ng);
  ng.connect(ctx.destination);
  noise.start(t);
}

export function vibrateKnock() {
  if (typeof navigator !== "undefined" && typeof navigator.vibrate === "function") {
    // A quick double buzz per tap so each knock *feels* like a knock-knock.
    navigator.vibrate([25, 20, 35]);
  }
}

// Full-screen pad: every pointer-down sends one knock (parent handles sound +
// relay so the caller hears their own rhythm too).
export function KnockPad({
  name,
  onTap,
  onClose,
}: {
  name: string;
  onTap: () => void;
  onClose: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 grid place-items-center bg-white/92 px-6 backdrop-blur-sm">
      <div className="w-full max-w-sm rounded-[8px] border border-hairline bg-white p-6 text-center shadow-[0_20px_80px_rgba(10,10,10,0.10)]">
        <p className="text-[12px] uppercase tracking-label text-text-secondary">Knocking</p>
        <h2 className="mt-1 text-[26px] font-light text-text">{name}</h2>
        <p className="mt-1 text-[13px] text-text-secondary">
          Tap a rhythm. They feel each knock as you tap it.
        </p>
        <button
          aria-label={`Knock for ${name}`}
          onPointerDown={(e) => {
            e.preventDefault();
            onTap();
          }}
          className="mx-auto mt-6 flex h-44 w-44 select-none items-center justify-center rounded-full border border-hairline bg-bg-grouped text-[44px] text-text transition-transform active:scale-95 active:bg-text/[0.06]"
        >
          ✊
        </button>
        <button
          onClick={onClose}
          className="mt-6 rounded-[8px] border border-hairline px-4 py-2 text-[13px] text-text transition-colors hover:border-text/30"
        >
          Done
        </button>
      </div>
    </div>
  );
}

// Transient banner shown to the person being knocked. Each incoming tap re-pulses
// it; it self-dismisses after a couple seconds of silence.
export function KnockBanner({
  name,
  pulseKey,
  onKnockBack,
  onCall,
  onDismiss,
}: {
  name: string;
  pulseKey: number;
  onKnockBack: () => void;
  onCall: () => void;
  onDismiss: () => void;
}) {
  const ref = useRef<HTMLDivElement>(null);
  // Re-trigger the pulse animation on every new tap.
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    el.classList.remove("animate-gentle-pulse");
    void el.offsetWidth;
    el.classList.add("animate-gentle-pulse");
  }, [pulseKey]);

  return (
    <div className="fixed inset-x-0 top-4 z-50 flex justify-center px-4">
      <div
        ref={ref}
        className="flex w-full max-w-sm items-center gap-3 rounded-[12px] border border-hairline bg-white px-4 py-3 shadow-[0_12px_40px_rgba(10,10,10,0.12)]"
      >
        <span className="text-[22px]">✊</span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-[14px] text-text">{name} is knocking</p>
          <p className="text-[12px] text-text-secondary">Knock back or pick up</p>
        </div>
        <button
          onClick={onKnockBack}
          className="rounded-[8px] border border-hairline px-3 py-1.5 text-[12px] text-text hover:border-text/30"
        >
          Knock back
        </button>
        <button
          onClick={onCall}
          className="rounded-[8px] bg-text px-3 py-1.5 text-[12px] text-white"
        >
          Call
        </button>
        <button
          onClick={onDismiss}
          aria-label="Dismiss"
          className="text-text-secondary hover:text-text"
        >
          ✕
        </button>
      </div>
    </div>
  );
}
