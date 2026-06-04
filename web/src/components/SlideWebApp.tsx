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
import { KnockBanner, KnockPad, playKnock, vibrateKnock } from "./Knock";
import { enableWebPush } from "../lib/push";

const API_BASE =
  process.env.NEXT_PUBLIC_SLIDE_API_BASE_URL ??
  "https://nck3w7ufbz.us-east-1.awsapprunner.com/v1";

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
    throw new Error(`${response.status} ${response.statusText}`);
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

function sfuSocketUrl(session: CallSession) {
  const url = new URL(session.sfuUrl);
  url.searchParams.set("token", session.joinToken);
  return url.toString();
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

export default function SlideWebApp() {
  const [tokens, setTokens] = useState<AuthTokens | null>(null);
  const [user, setUser] = useState<User | null>(null);
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [devCode, setDevCode] = useState<string | null>(null);
  const [authStep, setAuthStep] = useState<"phone" | "code">("phone");
  const [authBusy, setAuthBusy] = useState(false);
  const [authError, setAuthError] = useState<string | null>(null);
  const [dialNumber, setDialNumber] = useState("");
  const [lookup, setLookup] = useState<LookupState>({ status: "idle" });
  const [incoming, setIncoming] = useState<IncomingCall | null>(null);
  // Knock: lightweight, real-time "tap a rhythm" presence ping.
  const [knockPad, setKnockPad] = useState<{ userId: string; name: string } | null>(null);
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

  const localVideo = useRef<HTMLVideoElement | null>(null);
  const remoteVideo = useRef<HTMLVideoElement | null>(null);
  const signalingSocket = useRef<WebSocket | null>(null);
  const mediaSocket = useRef<WebSocket | null>(null);
  const peerConnection = useRef<RTCPeerConnection | null>(null);
  const audioContext = useRef<AudioContext | null>(null);
  const ringTimer = useRef<number | null>(null);
  const callStartRef = useRef<number | null>(null);
  const everConnectedRef = useRef(false);
  const incomingRef = useRef<IncomingCall | null>(null);
  const knockSeq = useRef(0);
  const knockLastTap = useRef<number | null>(null);
  const knockClearTimer = useRef<number | null>(null);

  const signedIn = Boolean(tokens && user);

  useEffect(() => {
    const initial = storedTokens();
    setTokens(initial);
    setContacts(loadList<Contact>("slide.web.contacts"));
    setRecents(loadList<RecentCall>("slide.web.recents"));
    setNotificationState(
      typeof Notification === "undefined" ? "unsupported" : Notification.permission,
    );
  }, []);

  useEffect(() => {
    if (!tokens) return;
    jsonFetch<User>("/me", tokens.accessToken)
      .then(setUser)
      .catch(() => {
        saveTokens(null);
        setTokens(null);
        setUser(null);
      });
  }, [tokens]);

  useEffect(() => {
    incomingRef.current = incoming;
  }, [incoming]);

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

    const socket = new WebSocket(wsUrl(tokens.accessToken));
    signalingSocket.current = socket;
    socket.onopen = () => setStatus("Browser calls are online");
    socket.onclose = () => setStatus("Browser calls are offline");
    socket.onerror = () => setStatus("Signaling error");
    socket.onmessage = (message) => {
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
        setKnocking((cur) => ({
          fromUserId,
          fromName,
          pulse: (cur?.fromUserId === fromUserId ? cur.pulse : 0) + 1,
        }));
        playKnock(ensureAudio());
        vibrateKnock();
        if (knockClearTimer.current) window.clearTimeout(knockClearTimer.current);
        knockClearTimer.current = window.setTimeout(() => setKnocking(null), 2500);
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

    return () => {
      socket.close();
    };
  }, [activeCall?.callId, ensureAudio, playRingtone, recordRecent, showNotification, tokens]);

  const sendKnock = useCallback(
    (toUserId: string) => {
      const now = Date.now();
      const dt = knockLastTap.current ? now - knockLastTap.current : 0;
      knockLastTap.current = now;
      knockSeq.current += 1;
      const sock = signalingSocket.current;
      if (sock && sock.readyState === WebSocket.OPEN) {
        sock.send(
          JSON.stringify({
            type: "knock",
            to: toUserId,
            fromName: user?.displayName || user?.phone || "Someone",
            seq: knockSeq.current,
            dt,
          }),
        );
      }
      playKnock(ensureAudio());
      vibrateKnock();
    },
    [ensureAudio, user],
  );

  const openKnockPad = useCallback((userId: string, name: string) => {
    knockSeq.current = 0;
    knockLastTap.current = null;
    setKnockPad({ userId, name });
  }, []);

  const requestOtp = async () => {
    setAuthBusy(true);
    setAuthError(null);
    try {
      const response = await jsonFetch<{ devCode?: string | null }>(
        "/auth/request-otp",
        null,
        {
          method: "POST",
          body: JSON.stringify({ phone }),
        },
      );
      setDevCode(response.devCode ?? null);
      setAuthStep("code");
    } catch {
      setAuthError("Could not send a verification code.");
    } finally {
      setAuthBusy(false);
    }
  };

  const verifyOtp = async () => {
    setAuthBusy(true);
    setAuthError(null);
    try {
      const response = await jsonFetch<
        AuthTokens & { user: User; isNewUser: boolean }
      >("/auth/verify-otp", null, {
        method: "POST",
        body: JSON.stringify({ phone, code }),
      });
      const nextTokens = {
        accessToken: response.accessToken,
        refreshToken: response.refreshToken,
      };
      saveTokens(nextTokens);
      setTokens(nextTokens);
      setUser(response.user);
      setAuthStep("phone");
      setCode("");
      ensureAudio();
    } catch {
      setAuthError("That code did not verify.");
    } finally {
      setAuthBusy(false);
    }
  };

  const logout = () => {
    saveTokens(null);
    saveList("slide.web.contacts", []);
    saveList("slide.web.recents", []);
    setContacts([]);
    setRecents([]);
    setTokens(null);
    setUser(null);
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
    if (permission === "granted" && tokens) {
      void enableWebPush((pushToken) =>
        jsonFetch("/devices", tokens.accessToken, {
          method: "POST",
          body: JSON.stringify({
            pushToken,
            platform: "web",
            kind: "webpush",
            appVersion: "web",
          }),
        }),
      );
    }
  };

  const checkNumber = async () => {
    if (!tokens) return;
    setLookup({ status: "checking" });
    try {
      const results = await jsonFetch<ContactSyncResult[]>(
        "/contacts/sync",
        tokens.accessToken,
        {
          method: "POST",
          body: JSON.stringify({ phones: [dialNumber], names: [dialNumber] }),
        },
      );
      const contact = results[0];
      if (contact?.onSlide && contact.userId) {
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
          setDialNumber(entry.phone);
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
      localStream?.getAudioTracks().forEach((track) => {
        track.enabled = !next;
      });
      return next;
    });
  }, [localStream]);

  const toggleCamera = useCallback(() => {
    setCameraOff((current) => {
      const next = !current;
      localStream?.getVideoTracks().forEach((track) => {
        track.enabled = !next;
      });
      return next;
    });
  }, [localStream]);

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
    const media = await navigator.mediaDevices.getUserMedia({
      audio: true,
      video,
    });
    setLocalStream(media);
    const remote = new MediaStream();
    setRemoteStream(remote);

    const pc = new RTCPeerConnection({
      iceServers: session.iceServers.map((server) => ({
        urls: server.urls,
        username: server.username ?? undefined,
        credential: server.credential ?? undefined,
      })),
    });
    peerConnection.current = pc;
    media.getTracks().forEach((track) => pc.addTrack(track, media));
    pc.ontrack = (event) => {
      event.streams[0]?.getTracks().forEach((track) => remote.addTrack(track));
      setRemoteStream(new MediaStream(remote.getTracks()));
    };
    pc.onconnectionstatechange = () => {
      if (pc.connectionState === "connected") {
        setStatus("Connected");
        setPeerConnected(true);
        everConnectedRef.current = true;
        callStartRef.current = Date.now();
      }
      if (pc.connectionState === "failed") {
        setStatus("Call failed");
        setPeerConnected(false);
      }
    };

    const socket = new WebSocket(sfuSocketUrl(session));
    mediaSocket.current = socket;
    pc.onicecandidate = (event) => {
      if (!event.candidate || socket.readyState !== WebSocket.OPEN) return;
      socket.send(
        JSON.stringify({
          type: "ice",
          candidate: event.candidate.candidate,
          sdp_mid: event.candidate.sdpMid,
          sdp_mline_index: event.candidate.sdpMLineIndex,
        }),
      );
    };
    socket.onopen = async () => {
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      socket.send(JSON.stringify({ type: "offer", sdp: offer.sdp }));
    };
    socket.onmessage = async (message) => {
      const event = JSON.parse(String(message.data)) as {
        type: string;
        sdp?: string;
        candidate?: string;
        sdp_mid?: string;
        sdp_mline_index?: number;
      };
      if (event.type === "answer" && event.sdp) {
        await pc.setRemoteDescription({ type: "answer", sdp: event.sdp });
      }
      if (event.type === "offer" && event.sdp) {
        await pc.setRemoteDescription({ type: "offer", sdp: event.sdp });
        const answer = await pc.createAnswer();
        await pc.setLocalDescription(answer);
        socket.send(JSON.stringify({ type: "answer", sdp: answer.sdp }));
      }
      if (event.type === "ice" && event.candidate) {
        await pc.addIceCandidate({
          candidate: event.candidate,
          sdpMid: event.sdp_mid,
          sdpMLineIndex: event.sdp_mline_index,
        });
      }
    };
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
    if (!tokens || !contact.userId) return;
    rememberContact({
      userId: contact.userId,
      phone: contact.phone,
      displayName: contact.displayName,
    });
    try {
      setStatus("Starting call");
      const session = await jsonFetch<CallSession>("/calls", tokens.accessToken, {
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
      setStatus(error instanceof Error ? error.message : "Could not start the call");
    }
  };

  const acceptIncoming = async (video: boolean) => {
    if (!tokens || !incoming) return;
    try {
      const call = incoming;
      setIncoming(null);
      const session = await jsonFetch<CallSession>(
        `/calls/${call.callId}/accept`,
        tokens.accessToken,
        { method: "POST" },
      );
      await startMedia(session, call.fromName, "incoming", video, {
        userId: call.fromUserId,
      });
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Could not answer the call");
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
    await jsonFetch(`/calls/${call.callId}/decline`, tokens.accessToken, {
      method: "POST",
    }).catch(() => undefined);
  };

  const endCall = (notifyServer = true) => {
    stopRingtone();
    mediaSocket.current?.close();
    mediaSocket.current = null;
    peerConnection.current?.close();
    peerConnection.current = null;
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
    if (notifyServer && tokens && activeCall) {
      void jsonFetch(`/calls/${activeCall.callId}/leave`, tokens.accessToken, {
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
                  {devCode ? (
                    <span className="text-[12px] text-text-secondary">
                      Dev code: {devCode}
                    </span>
                  ) : null}
                </label>
              )}
              {authError ? <p className="text-[13px] text-danger">{authError}</p> : null}
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
                        setDialNumber(event.target.value);
                        setLookup({ status: "idle" });
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
                  <div className="flex flex-col gap-3 rounded-[8px] border border-hairline bg-white p-3 sm:flex-row sm:items-center">
                    <div className="flex h-11 w-11 items-center justify-center rounded-full border border-hairline text-[13px] text-text-secondary">
                      {(lookup.contact.displayName || lookup.contact.phone).slice(0, 2).toUpperCase()}
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-[15px] text-text">
                        {lookup.contact.displayName || lookup.contact.phone}
                      </p>
                      <p className="text-[12px] text-text-secondary">On Slide</p>
                    </div>
                    <div className="flex gap-2">
                      <button
                        className="inline-flex h-10 items-center gap-2 rounded-[8px] border border-hairline px-3 text-[13px] text-text"
                        onClick={() => startCall(lookup.contact, false)}
                      >
                        <PhoneIcon className="h-4 w-4" />
                        Audio
                      </button>
                      <button
                        className="inline-flex h-10 items-center gap-2 rounded-[8px] bg-text px-3 text-[13px] text-white"
                        onClick={() => startCall(lookup.contact, true)}
                      >
                        <VideoIcon className="h-4 w-4" />
                        Video
                      </button>
                      <button
                        className="inline-flex h-10 items-center gap-2 rounded-[8px] border border-hairline px-3 text-[13px] text-text"
                        disabled={!lookup.contact.userId}
                        onClick={() =>
                          lookup.contact.userId &&
                          openKnockPad(
                            lookup.contact.userId,
                            lookup.contact.displayName || lookup.contact.phone,
                          )
                        }
                      >
                        <span className="text-[15px] leading-none">✊</span>
                        Knock
                      </button>
                    </div>
                  </div>
                ) : null}

                {lookup.status === "not-found" ? (
                  <p className="text-[13px] text-text-secondary">
                    That number is not on Slide yet. Send them the site link.
                  </p>
                ) : null}
                {lookup.status === "error" ? (
                  <p className="text-[13px] text-danger">{lookup.message}</p>
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

      {knockPad ? (
        <KnockPad
          name={knockPad.name}
          onTap={() => sendKnock(knockPad.userId)}
          onClose={() => setKnockPad(null)}
        />
      ) : null}

      {knocking ? (
        <KnockBanner
          name={knocking.fromName}
          pulseKey={knocking.pulse}
          onKnockBack={() => sendKnock(knocking.fromUserId)}
          onCall={() => {
            setKnocking(null);
            startCall(
              {
                phone: knocking.fromName,
                displayName: knocking.fromName,
                userId: knocking.fromUserId,
                onSlide: true,
              },
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
