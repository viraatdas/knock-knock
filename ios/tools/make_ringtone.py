#!/usr/bin/env python3
"""Generate Slide's original ringtone + pickup chime (warm marimba).

Royalty-free, fully synthesized — no copyrighted audio. Outputs WAVs which the
build step converts to CAF/M4A. Run: python3 ios/tools/make_ringtone.py
"""
import numpy as np, wave, struct, os

SR = 44100
OUT = "ios/Resources"

def marimba(freq, dur, t0, amp=1.0):
    """A soft wooden-mallet note: fast attack, quick decay, gentle harmonics."""
    n = int(dur*SR)
    t = np.linspace(0, dur, n, False)
    # mallet: fundamental + a touch of 2nd/4th harmonic, fast exp decay
    env = np.exp(-t*7.5)
    body = (np.sin(2*np.pi*freq*t)
            + 0.28*np.sin(2*np.pi*2*freq*t)*np.exp(-t*11)
            + 0.12*np.sin(2*np.pi*4*freq*t)*np.exp(-t*16))
    # short pitched "knock" transient at onset
    knock = np.sin(2*np.pi*freq*3.1*t)*np.exp(-t*60)*0.2
    return (body*env + knock)*amp, int(t0*SR)

def mix(events, total):
    buf = np.zeros(int(total*SR))
    for sig, start in events:
        end = start+len(sig)
        if end > len(buf):
            sig = sig[:len(buf)-start]; end = len(buf)
        buf[start:end] += sig
    # gentle soft-clip + normalize
    buf = np.tanh(buf*0.9)
    buf /= max(1e-6, np.max(np.abs(buf)))
    return buf*0.92

def write_wav(path, sig):
    sig16 = (sig*32767).astype(np.int16)
    with wave.open(path, "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(sig16.tobytes())
    print("wrote", path, f"{len(sig)/SR:.2f}s")

# Notes (Hz) — a warm, rising pentatonic phrase (C5, E5, G5, A5, C6)
C5,E5,G5,A5,C6,D6 = 523.25,659.25,783.99,880.0,1046.5,1174.66

# --- RINGTONE: a 3s phrase that loops cleanly ---
phrase = [
    (C5,0.00),(E5,0.18),(G5,0.36),(A5,0.60),
    (G5,0.84),(C6,1.02),(A5,1.32),(G5,1.56),
    (E5,1.80),(G5,1.98),(C6,2.22),  # lift
]
events=[]
for i,(f,t0) in enumerate(phrase):
    amp = 0.7 + 0.3*(i/len(phrase))
    events.append(marimba(f, 0.7, t0, amp))
# soft low root for warmth
events.append(marimba(C5/2, 1.2, 0.0, 0.25))
events.append(marimba(G5/2, 1.0, 1.5, 0.22))
ring = mix(events, 3.0)
# tiny fade in/out so the 3s loop is seamless
fade=int(0.04*SR)
ring[:fade]*=np.linspace(0,1,fade); ring[-fade:]*=np.linspace(1,0,fade)
write_wav("/tmp/ringtone.wav", ring)

# --- PICKUP / CONNECTED chime: two quick rising notes (~0.5s) ---
pick = mix([marimba(G5,0.45,0.0,0.9), marimba(C6,0.45,0.12,1.0)], 0.6)
write_wav("/tmp/pickup.wav", pick)

# --- END / disconnect: two soft descending notes ---
end = mix([marimba(G5,0.4,0.0,0.8), marimba(E5,0.45,0.10,0.7)], 0.55)
write_wav("/tmp/hangup.wav", end)
print("done")
