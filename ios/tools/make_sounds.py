#!/usr/bin/env python3
"""Generate Knock Knock - 5 Minute Dates's UI sounds (all synthesized, no licensed audio).

Outputs WAVs to a temp dir, then converts each to CAF/IMA4 with afconvert
(mono, 44.1 kHz). Run: python3 ios/tools/make_sounds.py

Sounds (see SPEC 2.6):
  knockknock.caf         two warm wooden knocks, 180 ms apart (~0.75 s) - 5-minute mark
  knock.caf               single knock - 7 PM push sound, welcome gesture
  match.caf                three rising warm marimba notes G5-B5-D6 + soft low root (~0.9 s)
  found.caf                two quick rising notes (~0.5 s) - partner found
  ended.caf                two soft descending notes (~0.55 s) - date over
  tick.caf                  soft wooden tick (~80 ms) - last 10 seconds
  message.caf               soft pop on send (~120 ms), sweep 900 -> 600 Hz
  message_received.caf      same pop a fourth lower, sweep 675 -> 450 Hz

Levels: everything is peak-normalized to -1 dBFS, then scaled down per sound so
UI sounds sit around -12 dBFS peak and the two knock sounds stay the loudest,
at -1 dBFS peak.
"""
import numpy as np
import wave
import os
import subprocess
import tempfile

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Resources")

KNOCK_DBFS = -1.0
UI_DBFS = -12.0


def db_to_linear(dbfs):
    return 10 ** (dbfs / 20.0)


def lowpass(x, alpha):
    """Simple one-pole lowpass (exponential smoothing) - gives noise a soft,
    wood-like character instead of a harsh hiss."""
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc)
        y[i] = acc
    return y


def marimba(freq, dur, t0, amp=1.0):
    """A soft wooden-mallet note: fast attack, quick decay, gentle harmonics.
    (Same idea as the old make_ringtone.py marimba().)"""
    n = int(dur * SR)
    t = np.linspace(0, dur, n, False)
    env = np.exp(-t * 7.5)
    body = (np.sin(2 * np.pi * freq * t)
            + 0.28 * np.sin(2 * np.pi * 2 * freq * t) * np.exp(-t * 11)
            + 0.12 * np.sin(2 * np.pi * 4 * freq * t) * np.exp(-t * 16))
    knock = np.sin(2 * np.pi * freq * 3.1 * t) * np.exp(-t * 60) * 0.2
    return (body * env + knock) * amp, int(t0 * SR)


def wood_knock(t0, freq=150, amp=1.0, dur=0.22):
    """A single knock: a filtered noise burst (the rap of knuckle on wood) plus
    a low resonant thump around 120-180 Hz with a fast exponential decay."""
    n = int(dur * SR)
    t = np.linspace(0, dur, n, False)
    thump_env = np.exp(-t * 30)
    thump = np.sin(2 * np.pi * freq * t + 0.3 * np.sin(2 * np.pi * freq * 2 * t)) * thump_env

    noise_dur = min(dur, 0.035)
    nn = int(noise_dur * SR)
    noise = np.random.default_rng(0).uniform(-1, 1, nn)
    noise = lowpass(noise, 0.15)
    noise_env = np.exp(-np.linspace(0, noise_dur, nn, False) * 140)
    noise *= noise_env

    sig = thump * 0.8
    sig[:nn] += noise * 0.9
    return sig * amp, int(t0 * SR)


def wooden_tick(t0, amp=1.0, dur=0.08):
    """A very short, soft wooden tick: a brief filtered-noise click with a
    touch of high pitch, decaying almost immediately."""
    n = int(dur * SR)
    t = np.linspace(0, dur, n, False)
    noise = np.random.default_rng(1).uniform(-1, 1, n)
    noise = lowpass(noise, 0.35)
    click_env = np.exp(-t * 90)
    click = np.sin(2 * np.pi * 900 * t) * np.exp(-t * 220) * 0.4
    sig = (noise * click_env + click) * amp
    return sig, int(t0 * SR)


def sweep_pop(f0, f1, dur, t0=0.0, amp=1.0):
    """A soft pop: a short sine sweep with a fast exponential decay."""
    n = int(dur * SR)
    t = np.linspace(0, dur, n, False)
    freq = np.linspace(f0, f1, n)
    phase = 2 * np.pi * np.cumsum(freq) / SR
    env = np.exp(-t * 28)
    sig = np.sin(phase) * env * amp
    return sig, int(t0 * SR)


def mix(events, total_dur):
    buf = np.zeros(int(total_dur * SR))
    for sig, start in events:
        end = start + len(sig)
        if end > len(buf):
            sig = sig[:len(buf) - start]
            end = len(buf)
        buf[start:end] += sig
    return buf


def finish(sig, dbfs):
    """Peak-normalize to 0 dBFS, then scale to the target peak level."""
    peak = np.max(np.abs(sig))
    if peak > 1e-9:
        sig = sig / peak
    return sig * db_to_linear(dbfs)


def write_wav(path, sig):
    sig16 = np.clip(sig * 32767, -32768, 32767).astype(np.int16)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(sig16.tobytes())


# Notes (Hz)
G5, B5, D6 = 783.99, 987.77, 1174.66
G3 = 195.998
E5, C6 = 659.25, 1046.50


def build_sounds():
    sounds = {}

    # knockknock: two knocks, 180 ms apart, ~0.75s buffer for decay tail
    events = [wood_knock(0.0), wood_knock(0.18)]
    sig = mix(events, 0.75)
    sounds["knockknock"] = (finish(sig, KNOCK_DBFS), "two warm wooden knocks, 180 ms apart")

    # knock: single knock
    sig = mix([wood_knock(0.0)], 0.45)
    sounds["knock"] = (finish(sig, KNOCK_DBFS), "a single warm wooden knock")

    # match: three rising marimba notes G5 -> B5 -> D6 with a soft low root
    events = [
        marimba(G5, 0.55, 0.00, 0.85),
        marimba(B5, 0.55, 0.22, 0.95),
        marimba(D6, 0.60, 0.44, 1.0),
        marimba(G3, 0.85, 0.00, 0.22),
    ]
    sig = mix(events, 0.9)
    sounds["match"] = (finish(sig, UI_DBFS), "three rising warm marimba notes (G5, B5, D6) over a soft low root")

    # found: two quick rising notes
    events = [marimba(G5, 0.42, 0.00, 0.9), marimba(C6, 0.42, 0.12, 1.0)]
    sig = mix(events, 0.5)
    sounds["found"] = (finish(sig, UI_DBFS), "two quick rising marimba notes (G5, C6)")

    # ended: two soft descending notes
    events = [marimba(G5, 0.4, 0.00, 0.75), marimba(E5, 0.42, 0.10, 0.65)]
    sig = mix(events, 0.55)
    sounds["ended"] = (finish(sig, UI_DBFS), "two soft descending marimba notes (G5, E5)")

    # tick: soft wooden tick
    sig = mix([wooden_tick(0.0)], 0.08)
    sounds["tick"] = (finish(sig, UI_DBFS), "a very short soft wooden tick")

    # message: soft pop on send, sweep 900 -> 600 Hz
    sig = mix([sweep_pop(900, 600, 0.12)], 0.12)
    sounds["message"] = (finish(sig, UI_DBFS), "a soft pop, sine sweep 900 -> 600 Hz")

    # message_received: same pop a fourth lower (900*3/4=675, 600*3/4=450)
    sig = mix([sweep_pop(675, 450, 0.12)], 0.12)
    sounds["message_received"] = (finish(sig, UI_DBFS), "the send pop a fourth lower, sweep 675 -> 450 Hz")

    return sounds


def main():
    sounds = build_sounds()
    with tempfile.TemporaryDirectory() as tmp:
        for name, (sig, desc) in sounds.items():
            wav_path = os.path.join(tmp, f"{name}.wav")
            caf_path = os.path.join(OUT, f"{name}.caf")
            write_wav(wav_path, sig)
            subprocess.run(
                ["afconvert", "-f", "caff", "-d", "ima4", wav_path, caf_path],
                check=True,
            )
            print(f"wrote {caf_path}  -  {desc}")
    print("done")


if __name__ == "__main__":
    main()
