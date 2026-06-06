"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  ArrowIncomingIcon,
  ArrowOutgoingIcon,
  MicIcon,
  MicOffIcon,
  PhoneIcon,
  VideoIcon,
  VideoOffIcon,
} from "./icons";
import PhoneField from "./PhoneField";
import { KnockSurface, KnockIncoming, playKnock, vibrateKnock } from "./Knock";
import { Room, RoomEvent, Track, VideoPresets, type RemoteTrack } from "livekit-client";
import { enableWebPush } from "../lib/push";
import { firebaseAuth } from "../lib/firebase";
import {
  RecaptchaVerifier,
  signInWithPhoneNumber,
  type ConfirmationResult,
} from "firebase/auth";

// slide-api on Fly. AWS App Runner's Envoy ingress rejects WebSocket upgrades
// (403), so the /v1/ws signaling socket can't connect there; calls never ring.
// Fly serves WebSockets, so the API (REST + WS) lives there.
const API_BASE =
  process.env.NEXT_PUBLIC_SLIDE_API_BASE_URL ??
  "https://slide-api.fly.dev/v1";

type AuthTokens = {
  accessToken: string;
  refreshToken: string;
};

type User = {
  id: string;
  phone: string;
  displayName?: string | null;
};

type ContactSyncResult = {
  phone: string;
  displayName?: string | null;
  userId?: string | null;
  onSlide: boolean;
};

type IceServer = {
  urls: string[];
  username?: string | null;
  credential?: string | null;
};

type Call = {
  id: string;
  type?: string;
  createdBy?: string;
};

type CallSession = {
  call: Call;
  joinToken: string;
  sfuUrl: string;
  iceServers: IceServer[];
};

type SignalEvent = {
  type: string;
  callId?: string;
  callType?: string;
  fromUserId?: string;
  fromName?: string;
  call?: Call;
  from?: string | User;
};

type IncomingCall = {
  callId: string;
  fromUserId: string;
  fromName: string;
};

type ActiveCall = {
  callId: string;
  peerName: string;
  direction: "incoming" | "outgoing";
  video: boolean;
  phone?: string | null;
  userId?: string | null;
};

type Contact = {
  userId: string;
  phone: string;
  displayName?: string | null;
};

type RecentCall = {
  id: string;
  peerName: string;
  phone?: string | null;
  userId?: string | null;
  direction: "incoming" | "outgoing";
  video: boolean;
  startedAt: number;
  durationSec: number;
  connected: boolean;
  label?: string;
};

type LookupState =
  | { status: "idle" }
  | { status: "checking" }
  | { status: "found"; contact: ContactSyncResult }
  | { status: "not-found" }
  | { status: "self" }
  | { status: "error"; message: string };

function storedTokens(): AuthTokens | null {
  if (typeof window === "undefined") return null;
  const raw = window.localStorage.getItem("slide.web.tokens");
  if (!raw) return null;
  try {
    return JSON.parse(raw) as AuthTokens;
  } catch {
    return null;
  }
}

function saveTokens(tokens: AuthTokens | null) {
  if (typeof window === "undefined") return;
  if (tokens) {
    window.localStorage.setItem("slide.web.tokens", JSON.stringify(tokens));
  } else {
    window.localStorage.removeItem("slide.web.tokens");
  }
}

function loadList<T>(key: string): T[] {
  if (typeof window === "undefined") return [];
  const raw = window.localStorage.getItem(key);
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? (parsed as T[]) : [];
  } catch {
    return [];
  }
}

function saveList<T>(key: string, list: T[]) {
  if (typeof window === "undefined") return;
  window.localStorage.setItem(key, JSON.stringify(list));
}

function initials(name: string) {
  const cleaned = name.trim();
  if (!cleaned) return "?";
  if (/^\+?\d/.test(cleaned)) {
    const digits = cleaned.replace(/\D/g, "");
    return digits.slice(-2) || "#";
  }
  const parts = cleaned.split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}

function formatDuration(totalSec: number) {
  const sec = Math.max(0, Math.floor(totalSec));
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  const mm = h > 0 ? String(m).padStart(2, "0") : String(m);
  return `${h > 0 ? `${h}:` : ""}${mm}:${String(s).padStart(2, "0")}`;
}

function relativeTime(ts: number) {
  const diff = Date.now() - ts;
  const min = Math.floor(diff / 60000);
  if (min < 1) return "Just now";
  if (min < 60) return `${min}m ago`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h ago`;
  const day = Math.floor(hr / 24);
  if (day === 1) return "Yesterday";
  if (day < 7) return `${day}d ago`;
  return new Date(ts).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

function recentOutcome(call: RecentCall) {
  if (call.label) return call.label;
  if (call.connected) return formatDuration(call.durationSec);
  return call.direction === "incoming" ? "Missed call" : "No answer";
}

function apiUrl(path: string) {
  return `${API_BASE.replace(/\/$/, "")}${path}`;
}

class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.name = "ApiError";
    this.status = status;
  }
}

// Decode a JWT's `exp` (seconds since epoch) without verifying the signature;
// used only to decide whether to proactively refresh before opening the socket.
function tokenExpiry(jwt: string): number | null {
  try {
    const payload = jwt.split(".")[1];
    if (!payload) return null;
    const json = JSON.parse(
      atob(payload.replace(/-/g, "+").replace(/_/g, "/")),
    );
    return typeof json.exp === "number" ? json.exp : null;
  } catch {
    return null;
  }
}

function humanizeCallError(message: string): string {
  if (/participant required/i.test(message)) {
    return "You can't call your own number. Try a different one.";
  }
  if (/exactly one participant/i.test(message)) {
    return "Group calls aren't supported on the web yet.";
  }
  if (/unknown participant/i.test(message)) {
    return "That person isn't reachable on Slide right now.";
  }
  return message;
}

function wsUrl(token: string) {
  const url = new URL(apiUrl("/ws"));
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.searchParams.set("token", token);
  return url.toString();
}

async function jsonFetch<T>(
  path: string,
  token: string | null,
  init: RequestInit = {},
): Promise<T> {
  const headers = new Headers(init.headers);
  if (!(init.body instanceof FormData)) {
    headers.set("Content-Type", "application/json");
  }
  if (token) headers.set("Authorization", `Bearer ${token}`);
  const response = await fetch(apiUrl(path), { ...init, headers });
  if (!response.ok) {
    let message = `${response.status} ${response.statusText}`;
    try {
      const data = await response.json();
      message = data?.error?.message ?? data?.message ?? message;
    } catch {
      // non-JSON body; keep the status line.
    }
    throw new ApiError(response.status, message);
  }
  if (response.status === 204) return undefined as T;
  return (await response.json()) as T;
}

function incomingFrom(event: SignalEvent): IncomingCall | null {
  const callId = event.callId ?? event.call?.id;
  if (!callId) return null;
  const fromObject = typeof event.from === "object" ? event.from : null;
  const fromUserId =
    event.fromUserId ??
    (typeof event.from === "string" ? event.from : undefined) ??
    fromObject?.id ??
    event.call?.createdBy ??
    "unknown";
  const fromName =
    event.fromName ??
    fromObject?.displayName ??
    fromObject?.phone ??
    "Slide";
  return { callId, fromUserId, fromName };
}

function assertBrowserReachableSfu(session: CallSession) {
  if (typeof window === "undefined") return;
  const url = new URL(session.sfuUrl);
  const localSfu = url.hostname === "localhost" || url.hostname === "127.0.0.1";
  const localPage =
    window.location.hostname === "localhost" ||
    window.location.hostname === "127.0.0.1";
  if (localSfu && !localPage) {
    throw new Error("The API returned a local SFU URL. Set SFU_PUBLIC_URL.");
  }
  if (window.location.protocol === "https:" && url.protocol !== "wss:") {
    throw new Error("Browser calls on HTTPS need a wss SFU URL.");
  }
}

// Pretty-print a phone number as it's typed: "+1 415 555 0123" / "415 555 0123".
// Backend normalization strips the spaces, so this is display-only.
function formatDial(raw: string): string {
  const hadPlus = raw.trimStart().startsWith("+");
  let digits = raw.replace(/\D/g, "");
  let cc = "";
  // Peel off a country code when there's an explicit + or more than 10 digits.
  if (hadPlus || digits.length > 10) {
    if (digits.startsWith("1")) {
      cc = "1";
      digits = digits.slice(1);
    } else {
      const n = Math.max(0, digits.length - 10);
      cc = digits.slice(0, n);
      digits = digits.slice(n);
    }
  }
  const groups: string[] = [];
  if (digits.length) groups.push(digits.slice(0, 3));
  if (digits.length > 3) groups.push(digits.slice(3, 6));
  if (digits.length > 6) groups.push(digits.slice(6, 10));
  const local = groups.join(" ");
  if (cc) return local ? `+${cc} ${local}` : `+${cc}`;
  if (hadPlus) return `+${local}`;
  return local;
}

export default function SlideWebApp() {
  const [tokens, setTokens] = useState<AuthTokens | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [authStep, setAuthStep] = useState<"phone" | "code">("phone");
  const [authBusy, setAuthBusy] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);
  const [dialNumber, setDialNumber] = useState("");
  // Audio/Video slider for the lookup result; you pick, then knock to call.
  const [dialVideo, setDialVideo] = useState(true);
  const [lookup, setLookup] = useState<LookupState>({ status: "idle" });
  const [incoming, setIncoming] = useState<IncomingCall | null>(null);
  // Knock: real-time "tap a rhythm" presence ritual. `knockSession` is the
  // full-screen duet stage; `knockTheirPulse` ticks when the peer in that
  // session knocks back so their ripple blooms on our stage.
  const [knockSession, setKnockSession] = useState<{ userId: string; name: string } | null>(null);
  const [knockTheirPulse, setKnockTheirPulse] = useState(0);
  const [knocking, setKnocking] = useState<{
    fromUserId: string;
    fromName: string;
    pulse: number;
  } | null>(null);
  const [activeCall, setActiveCall] = useState<ActiveCall | null>(null);
  const [notificationState, setNotificationState] = useState("default");
  const [status, setStatus] = useState("Ready");
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);
  const [contacts, setContacts] = useState<Contact[]>([]);
  const [recents, setRecents] = useState<RecentCall[]>([]);
  const [peerConnected, setPeerConnected] = useState(false);
  const [muted, setMuted] = useState(false);
  const [cameraOff, setCameraOff] = useState(false);
  const [elapsed, setElapsed] = useState(0);
  const [callError, setCallError] = useState<string | null>(null);

  const tokensRef = useRef<AuthTokens | null>(null);
  const refreshInFlight = useRef<Promise<string> | null>(null);
  const localVideo = useRef<HTMLVideoElement | null>(null);
  const remoteVideo = useRef<HTMLVideoElement | null>(null);
  const signalingSocket = useRef<WebSocket | null>(null);
  // LiveKit room for the media plane (replaces the custom SFU socket + PC).
  const room = useRef<Room | null>(null);
  const audioContext = useRef<AudioContext | null>(null);
  const ringTimer = useRef<number | null>(null);
  const callStartRef = useRef<number | null>(null);
  const everConnectedRef = useRef(false);
  const incomingRef = useRef<IncomingCall | null>(null);
  const knockSeq = useRef(0);
  const knockLastTap = useRef<number | null>(null);
  const knockClearTimer = useRef<number | null>(null);
  const knockNotifyAt = useRef(0);
  const knockSessionRef = useRef<{ userId: string; name: string } | null>(null);

  const signedIn = Boolean(tokens && user);

  useEffect(() => {
    const initial = storedTokens();
    tokensRef.current = initial;
    setTokens(initial);
    setContacts(loadList<Contact>("slide.web.contacts"));
    setRecents(loadList<RecentCall>("slide.web.recents"));
    setNotificationState(
      typeof Notification === "undefined" ? "unsupported" : Notification.permission,
    );
  }, []);

  useEffect(() => {
    tokensRef.current = tokens;
  }, [tokens]);

  const applyTokens = useCallback((next: AuthTokens | null) => {
    tokensRef.current = next;
    saveTokens(next);
    setTokens(next);
    if (!next) setUser(null);
  }, []);

  // Coalesced silent refresh: rotate the refresh token, mint a fresh access
  // token, persist both. Mirrors the iOS/Android 401-refresh behavior so web
  // sessions don't die after the 15-minute access-token TTL.
  const refreshAccessToken = useCallback(async (): Promise<string> => {
    if (refreshInFlight.current) return refreshInFlight.current;
    const current = tokensRef.current;
    if (!current?.refreshToken) throw new ApiError(401, "Not signed in");
    const attempt = (async () => {
      try {
        const res = await jsonFetch<AuthTokens>("/auth/refresh", null, {
          method: "POST",
          body: JSON.stringify({ refreshToken: current.refreshToken }),
        });
        const next = {
          accessToken: res.accessToken,
          refreshToken: res.refreshToken,
        };
        applyTokens(next);
        return next.accessToken;
      } finally {
        refreshInFlight.current = null;
      }
    })();
    refreshInFlight.current = attempt;
    return attempt;
  }, [applyTokens]);

  // Authenticated fetch with one transparent refresh-and-retry on 401.
  const authedFetch = useCallback(
    async <T,>(path: string, init: RequestInit = {}): Promise<T> => {
      const access = tokensRef.current?.accessToken ?? null;
      try {
        return await jsonFetch<T>(path, access, init);
      } catch (error) {
        if (
          error instanceof ApiError &&
          error.status === 401 &&
          tokensRef.current?.refreshToken
        ) {
          try {
            const fresh = await refreshAccessToken();
            return await jsonFetch<T>(path, fresh, init);
          } catch {
            applyTokens(null);
          }
        }
        throw error;
      }
    },
    [refreshAccessToken, applyTokens],
  );

  // Return a token guaranteed fresh for ~the next minute, refreshing if the
  // current one is expired or about to expire. Used before opening the socket.
  const ensureFreshToken = useCallback(async (): Promise<string | null> => {
    const current = tokensRef.current;
    if (!current) return null;
    const exp = tokenExpiry(current.accessToken);
    const now = Math.floor(Date.now() / 1000);
    if (exp !== null && exp - now < 60) {
      try {
        return await refreshAccessToken();
      } catch {
        applyTokens(null);
        return null;
      }
    }
    return current.accessToken;
  }, [refreshAccessToken, applyTokens]);

  useEffect(() => {
    if (!tokens) return;
    authedFetch<User>("/me")
      .then(setUser)
      .catch(() => applyTokens(null));
  }, [tokens, authedFetch, applyTokens]);

  useEffect(() => {
    incomingRef.current = incoming;
  }, [incoming]);

  useEffect(() => {
    knockSessionRef.current = knockSession;
  }, [knockSession]);

  useEffect(() => {
    if (localVideo.current) localVideo.current.srcObject = localStream;
  }, [localStream, activeCall]);

  useEffect(() => {
    if (remoteVideo.current) remoteVideo.current.srcObject = remoteStream;
  }, [remoteStream, activeCall]);

  useEffect(() => {
    if (!activeCall) {
      setElapsed(0);
      return;
    }
    const tick = () =>
      setElapsed(
        callStartRef.current
          ? Math.floor((Date.now() - callStartRef.current) / 1000)
          : 0,
      );
    tick();
    const id = window.setInterval(tick, 1000);
    return () => window.clearInterval(id);
  }, [activeCall]);

  const ensureAudio = useCallback(() => {
    if (typeof window === "undefined") return null;
    const AudioCtor = window.AudioContext ?? window.webkitAudioContext;
    if (!AudioCtor) return null;
    if (!audioContext.current) audioContext.current = new AudioCtor();
    void audioContext.current.resume();
    return audioContext.current;
  }, []);

  const stopRingtone = useCallback(() => {
    if (ringTimer.current !== null) {
      window.clearInterval(ringTimer.current);
      ringTimer.current = null;
    }
  }, []);

  const playRingtone = useCallback(() => {
    stopRingtone();
    const ctx = ensureAudio();
    if (!ctx) return;

    const playTone = (frequency: number, offset: number) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.frequency.value = frequency;
      osc.type = "sine";
      osc.connect(gain);
      gain.connect(ctx.destination);
      const start = ctx.currentTime + offset;
      gain.gain.setValueAtTime(0, start);
      gain.gain.linearRampToValueAtTime(0.08, start + 0.04);
      gain.gain.linearRampToValueAtTime(0, start + 0.42);
      osc.start(start);
      osc.stop(start + 0.45);
    };

    const cycle = () => {
      playTone(880, 0);
      playTone(1175, 0.46);
    };
    cycle();
    ringTimer.current = window.setInterval(cycle, 2200);
  }, [ensureAudio, stopRingtone]);

  const showNotification = useCallback((call: IncomingCall) => {
    if (typeof Notification === "undefined" || Notification.permission !== "granted") {
      return;
    }
    new Notification("Incoming Slide call", {
      body: `${call.fromName} is calling your browser.`,
      icon: "/icon.svg",
      tag: `slide-${call.callId}`,
    });
  }, []);

  const rememberContact = useCallback((contact: Contact) => {
    setContacts((current) => {
      const next = [
        contact,
        ...current.filter((entry) => entry.userId !== contact.userId),
      ].slice(0, 12);
      saveList("slide.web.contacts", next);
      return next;
    });
  }, []);

  const recordRecent = useCallback((call: RecentCall) => {
    setRecents((current) => {
      if (current.some((entry) => entry.id === call.id)) return current;
      const next = [call, ...current].slice(0, 20);
      saveList("slide.web.recents", next);
      return next;
    });
  }, []);

  useEffect(() => {
    if (!tokens) {
      signalingSocket.current?.close();
      signalingSocket.current = null;
      return;
    }

    let cancelled = false;
    let socket: WebSocket | null = null;
    let reconnectTimer: number | null = null;
    let attempts = 0;

    const scheduleReconnect = () => {
      if (cancelled || !tokensRef.current) return;
      const delay = Math.min(1000 * 2 ** attempts, 15000);
      attempts += 1;
      reconnectTimer = window.setTimeout(connect, delay);
    };

    const connect = async () => {
      if (cancelled) return;
      const token = await ensureFreshToken();
      if (cancelled || !token) return;
      const ws = new WebSocket(wsUrl(token));
      socket = ws;
      signalingSocket.current = ws;
      ws.onopen = () => {
        attempts = 0;
        setStatus("Browser calls are online");
      };
      ws.onclose = () => {
        if (cancelled) return;
        setStatus("Browser calls are offline");
        scheduleReconnect();
      };
      ws.onerror = () => setStatus("Signaling error");
      ws.onmessage = (message) => {
      let event: SignalEvent | null = null;
      try {
        event = JSON.parse(String(message.data)) as SignalEvent;
      } catch {
        event = null;
      }
      if (!event) return;
      if (event.type === "incoming_call") {
        const next = incomingFrom(event);
        if (!next) return;
        setIncoming(next);
        setStatus("Incoming call");
        playRingtone();
        showNotification(next);
      }
      if (event.type === "knock") {
        const fromUserId = event.fromUserId ?? "";
        const fromName = event.fromName ?? "Someone";
        // Every tap feels + sounds, with gentle pitch variation so a rhythm
        // reads as musical rather than robotic.
        playKnock(ensureAudio(), 0.9 + Math.random() * 0.2);
        vibrateKnock();

        // If we're already in the duet stage with this person, land their tap
        // there (a blooming ripple) instead of popping the incoming card.
        if (knockSessionRef.current?.userId === fromUserId) {
          setKnockTheirPulse((n) => n + 1);
          return;
        }

        setKnocking((cur) => ({
          fromUserId,
          fromName,
          pulse: (cur?.fromUserId === fromUserId ? cur.pulse : 0) + 1,
        }));
        // Fire a system notification once per knock burst (a fresh burst starts
        // after a >2s gap) so a knock reaches you even when the tab is in the
        // background; the per-tap sound + vibration carry the rhythm.
        const nowMs = Date.now();
        if (nowMs - knockNotifyAt.current > 2000) {
          knockNotifyAt.current = nowMs;
          if (typeof Notification !== "undefined" && Notification.permission === "granted") {
            try {
              new Notification(`${fromName} is tapping`, {
                tag: "slide-knock",
                renotify: true,
                silent: false,
              } as NotificationOptions);
            } catch {
              // Some browsers only allow notifications from a service worker.
            }
          }
        }
        if (knockClearTimer.current) window.clearTimeout(knockClearTimer.current);
        knockClearTimer.current = window.setTimeout(() => setKnocking(null), 4000);
      }
      if (event.type === "call_ended" || event.type === "call_declined") {
        const ringing = incomingRef.current;
        const matchesRinging =
          ringing &&
          (ringing.callId === event.callId || ringing.callId === event.call?.id);
        if (matchesRinging && !activeCall) {
          recordRecent({
            id: `${ringing!.callId}-missed`,
            peerName: ringing!.fromName,
            userId: ringing!.fromUserId,
            direction: "incoming",
            video: false,
            startedAt: Date.now(),
            durationSec: 0,
            connected: false,
          });
        }
        setIncoming((current) =>
          current?.callId === event.callId || current?.callId === event.call?.id
            ? null
            : current,
        );
        if (activeCall?.callId === event.callId || activeCall?.callId === event.call?.id) {
          endCall(false);
        }
      }
      };
    };

    void connect();

    return () => {
      cancelled = true;
      if (reconnectTimer !== null) window.clearTimeout(reconnectTimer);
      socket?.close();
      signalingSocket.current = null;
    };
  }, [
    activeCall?.callId,
    ensureAudio,
    ensureFreshToken,
    playRingtone,
    recordRecent,
    showNotification,
    tokens,
  ]);

  const sendKnock = useCallback(
    (toUserId: string) => {
      const sock = signalingSocket.current;
      if (!sock || sock.readyState !== WebSocket.OPEN) {
        setStatus("Tap needs browser calls online");
        return;
      }
      const now = Date.now();
      const dt = knockLastTap.current ? now - knockLastTap.current : 0;
      knockLastTap.current = now;
      knockSeq.current += 1;
      sock.send(
        JSON.stringify({
          type: "knock",
          to: toUserId,
          fromName: user?.displayName || user?.phone || "Someone",
          seq: knockSeq.current,
          dt,
        }),
      );
      playKnock(ensureAudio(), 0.9 + Math.random() * 0.2);
      vibrateKnock();
    },
    [ensureAudio, user],
  );

  // Open the full-screen duet stage for a person (also used by "knock back").
  const openKnock = useCallback((userId: string, name: string) => {
    knockSeq.current = 0;
    knockLastTap.current = null;
    setKnockTheirPulse(0);
    setKnocking(null);
    setKnockSession({ userId, name });
  }, []);

  // Firebase phone auth: send the SMS via Google (no carrier registration), then
  // exchange the verified ID token for Slide tokens at /auth/firebase.
  const recaptchaRef = useRef<RecaptchaVerifier | null>(null);
  const confirmationRef = useRef<ConfirmationResult | null>(null);

  const requestOtp = async () => {
    setAuthBusy(true);
    setAuthError(null);
    try {
      const e164 = phone.startsWith("+") ? phone : `+1${phone.replace(/\D/g, "")}`;
      const auth = firebaseAuth();
      if (!recaptchaRef.current) {
        recaptchaRef.current = new RecaptchaVerifier(auth, "recaptcha-container", {
          size: "invisible",
        });
      }
      confirmationRef.current = await signInWithPhoneNumber(
        auth,
        e164,
        recaptchaRef.current,
      );
      setAuthStep("code");
    } catch (error) {
      // Reset the verifier so a retry gets a fresh challenge.
      recaptchaRef.current?.clear();
      recaptchaRef.current = null;
      setAuthError(
        error instanceof Error ? error.message : "Could not send a verification code.",
      );
    } finally {
      setAuthBusy(false);
    }
  };

  const verifyOtp = async () => {
    setAuthBusy(true);
    setAuthError(null);
    try {
      if (!confirmationRef.current) throw new Error("Request a code first.");
      const cred = await confirmationRef.current.confirm(code);
      const idToken = await cred.user.getIdToken();
      const response = await jsonFetch<
        AuthTokens & { user: User; isNewUser: boolean }
      >("/auth/firebase", null, {
        method: "POST",
        body: JSON.stringify({ idToken }),
      });
      applyTokens({
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      });
      setUser(response.user);
      setAuthStep("phone");
      setCode("");
      confirmationRef.current = null;
      ensureAudio();
    } catch (error) {
      setAuthError(
        error instanceof Error ? error.message : "That code did not verify.",
      );
    } finally {
      setAuthBusy(false);
    }
  };

  const logout = () => {
    const refreshToken = tokensRef.current?.refreshToken;
    if (refreshToken) {
      void jsonFetch("/auth/logout", null, {
        method: "POST",
        body: JSON.stringify({ refreshToken }),
      }).catch(() => undefined);
    }
    saveList("slide.web.contacts", []);
    saveList("slide.web.recents", []);
    setContacts([]);
    setRecents([]);
    applyTokens(null);
    setIncoming(null);
    endCall(false);
  };

  const enableNotifications = async () => {
    ensureAudio();
    if (typeof Notification === "undefined") {
      setNotificationState("unsupported");
      return;
    }
    const permission = await Notification.requestPermission();
    setNotificationState(permission);
    if (permission === "granted" && tokensRef.current) {
      void enableWebPush((subscription) =>
        authedFetch("/push/register", {
          method: "POST",
          body: JSON.stringify({
            pushToken: subscription.endpoint,
            kind: "webpush",
            p256dh: subscription.p256dh,
            auth: subscription.auth,
            platform: "web",
            appVersion: "web",
          }),
        }),
      );
    }
  };

  const checkNumber = async () => {
    if (!tokensRef.current) return;
    setCallError(null);
    setLookup({ status: "checking" });
    try {
      const results = await authedFetch<ContactSyncResult[]>("/contacts/sync", {
        method: "POST",
        body: JSON.stringify({ phones: [dialNumber], names: [dialNumber] }),
      });
      const contact = results[0];
      if (contact?.userId && contact.userId === user?.id) {
        setLookup({ status: "self" });
      } else if (contact?.onSlide && contact.userId) {
        setLookup({ status: "found", contact });
        rememberContact({
          userId: contact.userId,
          phone: contact.phone,
          displayName: contact.displayName,
        });
      } else {
        setLookup({ status: "not-found" });
      }
    } catch {
      setLookup({ status: "error", message: "Could not check that number." });
    }
  };

  const callContact = useCallback(
    (
      entry: {
        userId?: string | null;
        phone?: string | null;
        displayName?: string | null;
        peerName?: string;
      },
      video: boolean,
    ) => {
      if (!entry.userId) {
        if (entry.phone) {
          setDialNumber(formatDial(entry.phone));
          setLookup({ status: "idle" });
        }
        return;
      }
      void startCall(
        {
          phone: entry.phone ?? entry.peerName ?? "",
          displayName: entry.displayName ?? entry.peerName ?? null,
          userId: entry.userId,
          onSlide: true,
        },
        video,
      );
    },
    // startCall is stable across renders for our purposes
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [tokens],
  );

  const toggleMute = useCallback(() => {
    setMuted((current) => {
      const next = !current;
      void room.current?.localParticipant.setMicrophoneEnabled(!next);
      return next;
    });
  }, []);

  const toggleCamera = useCallback(() => {
    setCameraOff((current) => {
      const next = !current;
      void room.current?.localParticipant.setCameraEnabled(!next);
      return next;
    });
  }, []);

  const startMedia = async (
    session: CallSession,
    peerName: string,
    direction: "incoming" | "outgoing",
    video: boolean,
    meta: { phone?: string | null; userId?: string | null } = {},
  ) => {
    stopRingtone();
    setStatus("Connecting media");
    setPeerConnected(false);
    setMuted(false);
    setCameraOff(false);
    everConnectedRef.current = false;
    callStartRef.current = Date.now();
    assertBrowserReachableSfu(session);

    // Remote media accumulates here as the other participant publishes tracks.
    const remote = new MediaStream();
    setRemoteStream(remote);

    const refreshRemote = () => setRemoteStream(new MediaStream(remote.getTracks()));
    const markConnected = () => {
      setStatus("Connected");
      setPeerConnected(true);
      if (!everConnectedRef.current) {
        everConnectedRef.current = true;
        callStartRef.current = Date.now();
      }
    };

    const lkRoom = new Room({
      adaptiveStream: true,
      dynacast: true,
      // Capture + publish at 720p so the remote feed is crisp (the default
      // capture is softer). Simulcast layers let LiveKit drop to lower
      // resolutions only when bandwidth / the display size calls for it.
      videoCaptureDefaults: { resolution: VideoPresets.h720.resolution },
      publishDefaults: {
        videoSimulcastLayers: [VideoPresets.h180, VideoPresets.h360],
        videoEncoding: VideoPresets.h720.encoding,
      },
    });
    room.current = lkRoom;

    lkRoom.on(RoomEvent.TrackSubscribed, (track: RemoteTrack) => {
      if (track.kind === Track.Kind.Video || track.kind === Track.Kind.Audio) {
        remote.addTrack(track.mediaStreamTrack);
        refreshRemote();
        markConnected();
      }
    });
    lkRoom.on(RoomEvent.TrackUnsubscribed, (track: RemoteTrack) => {
      remote.removeTrack(track.mediaStreamTrack);
      refreshRemote();
    });
    // The far side hung up / the room emptied → tear our side down too.
    lkRoom.on(RoomEvent.ParticipantDisconnected, () => {
      if (lkRoom.numParticipants <= 1) endCall(false);
    });
    lkRoom.on(RoomEvent.Disconnected, () => {
      if (room.current === lkRoom) endCall(false);
    });

    // Connect, then publish camera/mic. TCP fallback (port 7881) is built in,
    // so this works even where UDP is blocked.
    await lkRoom.connect(session.sfuUrl, session.joinToken);
    await lkRoom.localParticipant.setMicrophoneEnabled(true);
    await lkRoom.localParticipant.setCameraEnabled(video);

    // Mirror the locally published tracks into a stream for the self-preview.
    const localTracks: MediaStreamTrack[] = [];
    lkRoom.localParticipant.trackPublications.forEach((pub) => {
      const t = pub.track?.mediaStreamTrack;
      if (t) localTracks.push(t);
    });
    setLocalStream(new MediaStream(localTracks));

    setActiveCall({
      callId: session.call.id,
      peerName,
      direction,
      video,
      phone: meta.phone ?? null,
      userId: meta.userId ?? null,
    });
  };

  const startCall = async (contact: ContactSyncResult, video: boolean) => {
    if (!tokensRef.current || !contact.userId) return;
    if (contact.userId === user?.id) {
      setCallError("You can't call your own number.");
      return;
    }
    setCallError(null);
    rememberContact({
      userId: contact.userId,
      phone: contact.phone,
      displayName: contact.displayName,
    });
    try {
      setStatus("Starting call");
      const session = await authedFetch<CallSession>("/calls", {
        method: "POST",
        body: JSON.stringify({
          type: "one_to_one",
          participantUserIds: [contact.userId],
        }),
      });
      await startMedia(
        session,
        contact.displayName || contact.phone,
        "outgoing",
        video,
        { phone: contact.phone, userId: contact.userId },
      );
    } catch (error) {
      const message =
        error instanceof ApiError
          ? humanizeCallError(error.message)
          : "Could not start the call.";
      setCallError(message);
      setStatus("Ready");
    }
  };

  const acceptIncoming = async (video: boolean) => {
    if (!tokensRef.current || !incoming) return;
    try {
      const call = incoming;
      setIncoming(null);
      const session = await authedFetch<CallSession>(
        `/calls/${call.callId}/accept`,
        { method: "POST" },
      );
      await startMedia(session, call.fromName, "incoming", video, {
        userId: call.fromUserId,
      });
    } catch (error) {
      setCallError(
        error instanceof ApiError
          ? humanizeCallError(error.message)
          : "Could not answer the call.",
      );
      setStatus("Ready");
      stopRingtone();
    }
  };

  const declineIncoming = async () => {
    if (!tokens || !incoming) return;
    const call = incoming;
    setIncoming(null);
    stopRingtone();
    recordRecent({
      id: `${call.callId}-${Date.now()}`,
      peerName: call.fromName,
      userId: call.fromUserId,
      direction: "incoming",
      video: false,
      startedAt: Date.now(),
      durationSec: 0,
      connected: false,
      label: "Declined",
    });
    await authedFetch(`/calls/${call.callId}/decline`, {
      method: "POST",
    }).catch(() => undefined);
  };

  const endCall = (notifyServer = true) => {
    stopRingtone();
    // Null the ref first so the room's Disconnected handler doesn't re-enter.
    const lkRoom = room.current;
    room.current = null;
    lkRoom?.disconnect();
    localStream?.getTracks().forEach((track) => track.stop());
    remoteStream?.getTracks().forEach((track) => track.stop());
    if (activeCall) {
      const connected = everConnectedRef.current;
      const startedAt = callStartRef.current ?? Date.now();
      recordRecent({
        id: `${activeCall.callId}-${startedAt}`,
        peerName: activeCall.peerName,
        phone: activeCall.phone,
        userId: activeCall.userId,
        direction: activeCall.direction,
        video: activeCall.video,
        startedAt,
        durationSec: connected ? Math.round((Date.now() - startedAt) / 1000) : 0,
        connected,
      });
    }
    if (notifyServer && tokensRef.current && activeCall) {
      void authedFetch(`/calls/${activeCall.callId}/leave`, {
        method: "POST",
      }).catch(() => undefined);
    }
    callStartRef.current = null;
    everConnectedRef.current = false;
    setPeerConnected(false);
    setLocalStream(null);
    setRemoteStream(null);
    setActiveCall(null);
    setStatus("Ready");
  };

  const notificationLabel = useMemo(() => {
    if (notificationState === "granted") return "Notifications on";
    if (notificationState === "denied") return "Notifications blocked";
    if (notificationState === "unsupported") return "Notifications unavailable";
    return "Enable notifications";
  }, [notificationState]);

  return (
    <section id="web" className="border-b border-hairline bg-bg">
      <div
        className={`mx-auto grid min-h-[calc(100vh-72px)] gap-8 px-6 py-10 lg:py-12 ${
          signedIn
            ? "max-w-xl place-items-center"
            : "max-w-6xl lg:grid-cols-[0.86fr_1.14fr] lg:items-center"
        }`}
      >
        {!signedIn ? (
          <div className="max-w-xl">
            <p className="text-[12px] font-light uppercase tracking-label text-text-secondary">
              iOS, Android, and web
            </p>
            <h1 className="mt-5 text-[56px] font-light leading-[0.95] tracking-wordmark text-text sm:text-[84px]">
              Slide
            </h1>
            <p className="mt-6 max-w-md text-[21px] font-light leading-snug text-text sm:text-[25px]">
              Phone-number video calls for the people you already know.
            </p>
            <p className="mt-4 max-w-md text-[15px] font-light leading-relaxed text-text-secondary">
              Sign in with your number, verify by code, and call someone by typing
              their phone number. Browser notifications ring when a call comes in.
            </p>
            <div className="mt-8 flex flex-wrap gap-3 text-[13px] text-text-secondary">
              <span className="rounded-full border border-hairline px-3 py-1">Web app</span>
              <span className="rounded-full border border-hairline px-3 py-1">iPhone</span>
              <span className="rounded-full border border-hairline px-3 py-1">Android</span>
            </div>
          </div>
        ) : null}

        <div className="w-full rounded-[8px] border border-hairline bg-white p-4 shadow-[0_1px_0_rgba(10,10,10,0.04)] sm:p-5">
          <div className="flex items-center justify-between border-b border-hairline pb-4">
            <div>
              <p className="text-[12px] font-light uppercase tracking-label text-text-secondary">
                Browser call surface
              </p>
              <p className="mt-1 text-[15px] text-text">{status}</p>
            </div>
            {signedIn ? (
              <button
                className="rounded-full border border-hairline px-3 py-1.5 text-[13px] text-text-secondary transition-colors hover:border-text/30 hover:text-text"
                onClick={logout}
              >
                Sign out
              </button>
            ) : null}
          </div>

          {!signedIn ? (
            <div className="grid gap-5 pt-5">
              <div>
                <h2 className="text-[28px] font-light leading-tight text-text">
                  Sign in by phone
                </h2>
                <p className="mt-2 text-[14px] leading-relaxed text-text-secondary">
                  Your phone number is your account. Enter the verification code
                  to create or open your Slide account.
                </p>
              </div>
              {authStep === "phone" ? (
                <div className="grid gap-2">
                  <span className="text-[12px] uppercase tracking-label text-text-secondary">
                    Phone number
                  </span>
                  <PhoneField onChange={setPhone} onEnter={requestOtp} />
                </div>
              ) : (
                <label className="grid gap-2">
                  <span className="text-[12px] uppercase tracking-label text-text-secondary">
                    Verification code
                  </span>
                  <input
                    value={code}
                    onChange={(event) => setCode(event.target.value)}
                    inputMode="numeric"
                    placeholder="123456"
                    className="h-12 rounded-[8px] border border-hairline bg-bg px-4 text-[24px] font-light tracking-[0.18em] outline-none transition-colors focus:border-text/40"
                  />
                </label>
              )}
              {authError ? <p className="text-[13px] text-danger">{authError}</p> : null}
              {/* Invisible reCAPTCHA target for Firebase phone auth. */}
              <div id="recaptcha-container" />
              <button
                className="h-12 rounded-[8px] bg-text px-4 text-[14px] font-medium text-white transition-opacity disabled:opacity-40"
                disabled={authBusy || (authStep === "phone" ? phone.length < 4 : code.length < 4)}
                onClick={authStep === "phone" ? requestOtp : verifyOtp}
              >
                {authBusy ? "Working" : authStep === "phone" ? "Send code" : "Verify"}
              </button>
            </div>
          ) : (
            <div className="grid gap-5 pt-5">
              <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                <div>
                  <h2 className="text-[26px] font-light text-text">
                    {user?.displayName || user?.phone}
                  </h2>
                  <p className="text-[13px] text-text-secondary">
                    Call anyone on Slide by phone number.
                  </p>
                </div>
                <button
                  onClick={enableNotifications}
                  className="rounded-[8px] border border-hairline px-4 py-2 text-[13px] text-text transition-colors hover:border-text/30"
                >
                  {notificationLabel}
                </button>
              </div>

              <div className="grid gap-3 rounded-[8px] bg-bg-grouped p-4">
                <label className="grid gap-2">
                  <span className="text-[12px] uppercase tracking-label text-text-secondary">
                    Call by phone number
                  </span>
                  <div className="flex flex-col gap-2 sm:flex-row">
                    <input
                      value={dialNumber}
                      onChange={(event) => {
                        setDialNumber(formatDial(event.target.value));
                        setLookup({ status: "idle" });
                        setCallError(null);
                      }}
                      inputMode="tel"
                      placeholder="+1 415 555 0123"
                      className="h-12 flex-1 rounded-[8px] border border-hairline bg-white px-4 text-[18px] font-light outline-none transition-colors focus:border-text/40"
                    />
                    <button
                      className="h-12 rounded-[8px] bg-text px-5 text-[14px] font-medium text-white transition-opacity disabled:opacity-40"
                      disabled={lookup.status === "checking" || dialNumber.replace(/\D/g, "").length < 4}
                      onClick={checkNumber}
                    >
                      {lookup.status === "checking" ? "Checking" : "Check"}
                    </button>
                  </div>
                </label>

                {lookup.status === "found" ? (
                  <div className="rounded-[12px] border border-hairline bg-white p-5">
                    <div className="flex items-center gap-3">
                      <div className="flex h-12 w-12 items-center justify-center rounded-full border border-hairline text-[14px] text-text-secondary">
                        {(lookup.contact.displayName || lookup.contact.phone).slice(0, 2).toUpperCase()}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[17px] text-text">
                          {lookup.contact.displayName || lookup.contact.phone}
                        </p>
                        <p className="text-[12px] text-text-secondary">On Slide</p>
                      </div>
                    </div>

                    {/* Audio ↔ Video slider: a dark pill glides under the choice. */}
                    <div className="relative mt-5 flex rounded-full bg-bg-grouped p-1 text-[14px]">
                      <span
                        className="pointer-events-none absolute bottom-1 top-1 w-[calc(50%-4px)] rounded-full bg-text transition-[left] duration-300 ease-out"
                        style={{ left: dialVideo ? "calc(50% + 0px)" : "4px" }}
                      />
                      <button
                        onClick={() => setDialVideo(false)}
                        className={`relative z-10 flex flex-1 items-center justify-center gap-2 py-2 transition-colors ${
                          !dialVideo ? "text-white" : "text-text-secondary"
                        }`}
                      >
                        <PhoneIcon className="h-4 w-4" />
                        Audio
                      </button>
                      <button
                        onClick={() => setDialVideo(true)}
                        className={`relative z-10 flex flex-1 items-center justify-center gap-2 py-2 transition-colors ${
                          dialVideo ? "text-white" : "text-text-secondary"
                        }`}
                      >
                        <VideoIcon className="h-4 w-4" />
                        Video
                      </button>
                    </div>

                    {/* Tap pad: opens the realtime Tap surface. */}
                    <div className="mt-6 flex flex-col items-center">
                      <button
                        aria-label={`Tap ${lookup.contact.displayName || lookup.contact.phone}`}
                        onClick={() => {
                          if (!lookup.contact.userId) return;
                          openKnock(
                            lookup.contact.userId,
                            lookup.contact.displayName || lookup.contact.phone,
                          );
                        }}
                        className="grid h-32 w-32 select-none place-items-center rounded-full border border-hairline bg-bg-grouped text-[48px] transition-transform active:scale-95 active:bg-text/[0.06]"
                      >
                        ✊
                      </button>
                      <p className="mt-3 text-[13px] text-text-secondary">
                        Tap a rhythm. They feel every tap.
                      </p>
                      <button
                        onClick={() => startCall(lookup.contact, dialVideo)}
                        className="mt-5 inline-flex h-12 w-full items-center justify-center gap-2 rounded-full bg-text px-5 text-[14px] font-medium text-white transition-transform active:scale-[0.98]"
                      >
                        {dialVideo ? (
                          <VideoIcon className="h-4 w-4" />
                        ) : (
                          <PhoneIcon className="h-4 w-4" />
                        )}
                        {dialVideo ? "Start video call" : "Start call"}
                      </button>
                    </div>
                  </div>
                ) : null}

                {lookup.status === "self" ? (
                  <p className="text-[13px] text-text-secondary">
                    That&apos;s your own number. Enter someone else&apos;s to call
                    them.
                  </p>
                ) : null}
                {lookup.status === "not-found" ? (
                  <p className="text-[13px] text-text-secondary">
                    That number is not on Slide yet. Send them the site link.
                  </p>
                ) : null}
                {lookup.status === "error" ? (
                  <p className="text-[13px] text-danger">{lookup.message}</p>
                ) : null}
                {callError ? (
                  <p className="text-[13px] text-danger">{callError}</p>
                ) : null}
              </div>

              {contacts.length > 0 ? (
                <div className="grid gap-2">
                  <span className="text-[12px] uppercase tracking-label text-text-secondary">
                    On Slide
                  </span>
                  <div className="grid gap-1.5">
                    {contacts.map((contact) => {
                      const name = contact.displayName || contact.phone;
                      return (
                        <div
                          key={contact.userId}
                          className="group flex items-center gap-3 rounded-[8px] border border-transparent px-2 py-2 transition-colors hover:border-hairline hover:bg-bg-grouped"
                        >
                          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-bg-grouped text-[12px] font-medium text-text-secondary">
                            {initials(name)}
                          </div>
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-[15px] text-text">{name}</p>
                            {contact.displayName ? (
                              <p className="truncate text-[12px] text-text-secondary">
                                {contact.phone}
                              </p>
                            ) : null}
                          </div>
	                          <div className="flex gap-1.5 opacity-70 transition-opacity group-hover:opacity-100">
	                            <button
	                              className="flex h-9 w-9 items-center justify-center rounded-full border border-hairline text-[17px] text-text transition-colors hover:border-text/30"
	                              onClick={() => openKnock(contact.userId, name)}
	                              aria-label={`Tap ${name}`}
	                            >
	                              ✊
	                            </button>
	                            <button
	                              className="flex h-9 w-9 items-center justify-center rounded-full border border-hairline text-text transition-colors hover:border-text/30"
	                              onClick={() => callContact(contact, false)}
                              aria-label={`Audio call ${name}`}
                            >
                              <PhoneIcon className="h-4 w-4" />
                            </button>
                            <button
                              className="flex h-9 w-9 items-center justify-center rounded-full bg-text text-white transition-opacity hover:opacity-90"
                              onClick={() => callContact(contact, true)}
                              aria-label={`Video call ${name}`}
                            >
                              <VideoIcon className="h-4 w-4" />
                            </button>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              ) : null}

              {recents.length > 0 ? (
                <div className="grid gap-2">
                  <div className="flex items-center justify-between">
                    <span className="text-[12px] uppercase tracking-label text-text-secondary">
                      Recent
                    </span>
                    <button
                      className="text-[12px] text-text-secondary transition-colors hover:text-text"
                      onClick={() => {
                        setRecents([]);
                        saveList("slide.web.recents", []);
                      }}
                    >
                      Clear
                    </button>
                  </div>
                  <div className="grid gap-0.5">
                    {recents.slice(0, 6).map((call) => {
                      const missed = !call.connected;
                      return (
                        <button
                          key={call.id}
                          className="group flex items-center gap-3 rounded-[8px] px-2 py-2 text-left transition-colors hover:bg-bg-grouped"
                          onClick={() => callContact(call, call.video)}
                        >
                          <span
                            className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full ${
                              missed
                                ? "bg-danger/10 text-danger"
                                : "bg-bg-grouped text-text-secondary"
                            }`}
                          >
                            {call.direction === "incoming" ? (
                              <ArrowIncomingIcon className="h-4 w-4" />
                            ) : (
                              <ArrowOutgoingIcon className="h-4 w-4" />
                            )}
                          </span>
                          <div className="min-w-0 flex-1">
                            <p
                              className={`truncate text-[15px] ${
                                missed ? "text-danger" : "text-text"
                              }`}
                            >
                              {call.peerName}
                            </p>
                            <p className="truncate text-[12px] text-text-secondary">
                              {call.video ? "Video" : "Audio"} · {recentOutcome(call)}
                            </p>
                          </div>
                          <span className="shrink-0 text-[12px] text-text-secondary">
                            {relativeTime(call.startedAt)}
                          </span>
                          <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-text-secondary opacity-0 transition-opacity group-hover:opacity-100">
                            {call.video ? (
                              <VideoIcon className="h-4 w-4" />
                            ) : (
                              <PhoneIcon className="h-4 w-4" />
                            )}
                          </span>
                        </button>
                      );
                    })}
                  </div>
                </div>
              ) : null}

              {contacts.length === 0 && recents.length === 0 ? (
                <div className="rounded-[8px] border border-dashed border-hairline px-4 py-8 text-center">
                  <p className="text-[14px] text-text">No calls yet</p>
                  <p className="mt-1 text-[13px] text-text-secondary">
                    Look up a phone number above to start your first call.
                    People you reach show up here.
                  </p>
                </div>
              ) : null}
            </div>
          )}
        </div>
      </div>

      {activeCall ? (
        <div className="fixed inset-0 z-50 flex flex-col bg-[#0b0b0c] text-white">
          <video
            ref={remoteVideo}
            autoPlay
            playsInline
            className={`absolute inset-0 h-full w-full object-cover transition-opacity duration-500 ${
              activeCall.video && peerConnected && status !== "Call failed"
                ? "opacity-100"
                : "opacity-0"
            }`}
          />

          {!(activeCall.video && peerConnected && status !== "Call failed") ? (
            <div className="absolute inset-0 grid place-items-center px-6">
              <div className="flex flex-col items-center text-center">
                <div className="flex h-28 w-28 items-center justify-center rounded-full border border-white/15 bg-white/[0.06] text-[34px] font-light backdrop-blur-sm">
                  {initials(activeCall.peerName)}
                </div>
                <h2 className="mt-6 text-[30px] font-light">{activeCall.peerName}</h2>
                <p className="mt-2 text-[15px] text-white/60">
                  {status === "Call failed"
                    ? "Call failed"
                    : peerConnected
                      ? formatDuration(elapsed)
                      : activeCall.direction === "outgoing"
                        ? "Calling…"
                        : "Connecting…"}
                </p>
              </div>
            </div>
          ) : (
            <div className="pointer-events-none absolute inset-x-0 top-0 bg-gradient-to-b from-black/55 to-transparent p-6">
              <p className="text-[17px] font-light">{activeCall.peerName}</p>
              <p className="text-[13px] text-white/60">{formatDuration(elapsed)}</p>
            </div>
          )}

          {activeCall.video ? (
            <div className="absolute right-5 top-5 h-40 w-28 overflow-hidden rounded-[14px] border border-white/15 bg-black/50 shadow-[0_8px_30px_rgba(0,0,0,0.4)] sm:h-44 sm:w-32">
              <video
                ref={localVideo}
                autoPlay
                muted
                playsInline
                className={`h-full w-full object-cover transition-opacity ${
                  cameraOff ? "opacity-0" : "opacity-100"
                }`}
              />
              {cameraOff ? (
                <div className="absolute inset-0 grid place-items-center text-white/50">
                  <VideoOffIcon className="h-6 w-6" />
                </div>
              ) : null}
            </div>
          ) : (
            <video ref={localVideo} autoPlay muted playsInline className="hidden" />
          )}

          <div className="absolute inset-x-0 bottom-0 flex items-center justify-center gap-5 bg-gradient-to-t from-black/70 to-transparent px-6 pb-10 pt-16">
            <button
              onClick={toggleMute}
              aria-pressed={muted}
              aria-label={muted ? "Unmute" : "Mute"}
              className={`flex h-14 w-14 items-center justify-center rounded-full backdrop-blur-sm transition-colors ${
                muted ? "bg-white text-text" : "bg-white/15 text-white hover:bg-white/25"
              }`}
            >
              {muted ? <MicOffIcon className="h-6 w-6" /> : <MicIcon className="h-6 w-6" />}
            </button>
            {activeCall.video ? (
              <button
                onClick={toggleCamera}
                aria-pressed={cameraOff}
                aria-label={cameraOff ? "Turn camera on" : "Turn camera off"}
                className={`flex h-14 w-14 items-center justify-center rounded-full backdrop-blur-sm transition-colors ${
                  cameraOff
                    ? "bg-white text-text"
                    : "bg-white/15 text-white hover:bg-white/25"
                }`}
              >
                {cameraOff ? (
                  <VideoOffIcon className="h-6 w-6" />
                ) : (
                  <VideoIcon className="h-6 w-6" />
                )}
              </button>
            ) : null}
            <button
              onClick={() => endCall()}
              aria-label="End call"
              className="flex h-16 w-16 items-center justify-center rounded-full bg-danger text-white shadow-[0_8px_30px_rgba(229,72,77,0.45)] transition-transform hover:scale-105"
            >
              <PhoneIcon className="h-7 w-7 rotate-[135deg]" />
            </button>
          </div>
        </div>
      ) : null}

      {knockSession ? (
        <KnockSurface
          name={knockSession.name}
          theirPulse={knockTheirPulse}
          onTap={() => sendKnock(knockSession.userId)}
          onCall={() => {
            const s = knockSession;
            setKnockSession(null);
            startCall(
              { phone: s.name, displayName: s.name, userId: s.userId, onSlide: true },
              true,
            );
          }}
          onClose={() => setKnockSession(null)}
        />
      ) : null}

      {knocking && !knockSession ? (
        <KnockIncoming
          name={knocking.fromName}
          pulseKey={knocking.pulse}
          onKnockBack={() => {
            const k = knocking;
            openKnock(k.fromUserId, k.fromName);
            sendKnock(k.fromUserId);
          }}
          onCall={() => {
            const k = knocking;
            setKnocking(null);
            startCall(
              { phone: k.fromName, displayName: k.fromName, userId: k.fromUserId, onSlide: true },
              true,
            );
          }}
          onDismiss={() => setKnocking(null)}
        />
      ) : null}

      {incoming ? (
        <div className="fixed inset-0 z-50 grid place-items-center bg-white/92 px-6 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-[8px] border border-hairline bg-white p-6 text-center shadow-[0_20px_80px_rgba(10,10,10,0.10)]">
            <div className="mx-auto flex h-24 w-24 animate-gentle-pulse items-center justify-center rounded-full border border-hairline text-[28px] font-light text-text">
              {initials(incoming.fromName)}
            </div>
            <h2 className="mt-5 text-[30px] font-light text-text">{incoming.fromName}</h2>
            <p className="mt-1 text-[14px] text-text-secondary">Incoming browser call</p>
            <div className="mt-8 flex items-end justify-center gap-6">
              <div className="flex flex-col items-center gap-2">
                <button
                  className="flex h-16 w-16 items-center justify-center rounded-full bg-danger text-white transition-transform hover:scale-105"
                  onClick={declineIncoming}
                  aria-label="Decline"
                >
                  <PhoneIcon className="h-7 w-7 rotate-[135deg]" />
                </button>
                <span className="text-[12px] text-text-secondary">Decline</span>
              </div>
              <div className="flex flex-col items-center gap-2">
                <button
                  className="flex h-16 w-16 items-center justify-center rounded-full border border-hairline text-text transition-colors hover:border-text/30"
                  onClick={() => acceptIncoming(false)}
                  aria-label="Accept audio"
                >
                  <PhoneIcon className="h-7 w-7" />
                </button>
                <span className="text-[12px] text-text-secondary">Audio</span>
              </div>
              <div className="flex flex-col items-center gap-2">
                <button
                  className="flex h-16 w-16 items-center justify-center rounded-full bg-text text-white transition-transform hover:scale-105"
                  onClick={() => acceptIncoming(true)}
                  aria-label="Accept video"
                >
                  <VideoIcon className="h-7 w-7" />
                </button>
                <span className="text-[12px] text-text-secondary">Video</span>
              </div>
            </div>
          </div>
        </div>
      ) : null}
    </section>
  );
}

declare global {
  interface Window {
    webkitAudioContext?: typeof AudioContext;
  }
}
