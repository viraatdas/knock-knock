"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { PhoneIcon, VideoIcon, WaveformIcon } from "./icons";

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
  const [activeCall, setActiveCall] = useState<ActiveCall | null>(null);
  const [notificationState, setNotificationState] = useState("default");
  const [status, setStatus] = useState("Ready");
  const [localStream, setLocalStream] = useState<MediaStream | null>(null);
  const [remoteStream, setRemoteStream] = useState<MediaStream | null>(null);

  const localVideo = useRef<HTMLVideoElement | null>(null);
  const remoteVideo = useRef<HTMLVideoElement | null>(null);
  const signalingSocket = useRef<WebSocket | null>(null);
  const mediaSocket = useRef<WebSocket | null>(null);
  const peerConnection = useRef<RTCPeerConnection | null>(null);
  const audioContext = useRef<AudioContext | null>(null);
  const ringTimer = useRef<number | null>(null);

  const signedIn = Boolean(tokens && user);

  useEffect(() => {
    const initial = storedTokens();
    setTokens(initial);
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
    if (localVideo.current) localVideo.current.srcObject = localStream;
  }, [localStream]);

  useEffect(() => {
    if (remoteVideo.current) remoteVideo.current.srcObject = remoteStream;
  }, [remoteStream]);

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
      if (event.type === "call_ended" || event.type === "call_declined") {
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
  }, [activeCall?.callId, playRingtone, showNotification, tokens]);

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
      } else {
        setLookup({ status: "not-found" });
      }
    } catch {
      setLookup({ status: "error", message: "Could not check that number." });
    }
  };

  const startMedia = async (
    session: CallSession,
    peerName: string,
    direction: "incoming" | "outgoing",
    video: boolean,
  ) => {
    stopRingtone();
    setStatus("Connecting media");
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
      if (pc.connectionState === "connected") setStatus("Connected");
      if (pc.connectionState === "failed") setStatus("Call failed");
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
    setActiveCall({ callId: session.call.id, peerName, direction });
  };

  const startCall = async (contact: ContactSyncResult, video: boolean) => {
    if (!tokens || !contact.userId) return;
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
      await startMedia(session, call.fromName, "incoming", video);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : "Could not answer the call");
      stopRingtone();
    }
  };

  const declineIncoming = async () => {
    if (!tokens || !incoming) return;
    const callId = incoming.callId;
    setIncoming(null);
    stopRingtone();
    await jsonFetch(`/calls/${callId}/decline`, tokens.accessToken, {
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
    if (notifyServer && tokens && activeCall) {
      void jsonFetch(`/calls/${activeCall.callId}/leave`, tokens.accessToken, {
        method: "POST",
      }).catch(() => undefined);
    }
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
      <div className="mx-auto grid min-h-[calc(100vh-72px)] max-w-6xl gap-8 px-6 py-10 lg:grid-cols-[0.86fr_1.14fr] lg:items-center lg:py-12">
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

        <div className="rounded-[8px] border border-hairline bg-white p-4 shadow-[0_1px_0_rgba(10,10,10,0.04)] sm:p-5">
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
                <label className="grid gap-2">
                  <span className="text-[12px] uppercase tracking-label text-text-secondary">
                    Phone number
                  </span>
                  <input
                    value={phone}
                    onChange={(event) => setPhone(event.target.value)}
                    inputMode="tel"
                    placeholder="+1 415 555 0123"
                    className="h-12 rounded-[8px] border border-hairline bg-bg px-4 text-[18px] font-light outline-none transition-colors focus:border-text/40"
                  />
                </label>
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

              <div className="grid gap-3 rounded-[8px] border border-hairline p-4">
                <div className="flex items-center justify-between">
                  <div>
                    <p className="text-[15px] text-text">Live call</p>
                    <p className="text-[13px] text-text-secondary">
                      {activeCall
                        ? `${activeCall.peerName} is connected from ${activeCall.direction}`
                        : "No active browser call"}
                    </p>
                  </div>
                  {activeCall ? (
                    <button
                      className="rounded-full bg-danger px-4 py-2 text-[13px] text-white"
                      onClick={() => endCall()}
                    >
                      End
                    </button>
                  ) : (
                    <WaveformIcon className="h-7 w-7 text-text-secondary" />
                  )}
                </div>
                <div className="grid gap-3 sm:grid-cols-2">
                  <video
                    ref={localVideo}
                    autoPlay
                    muted
                    playsInline
                    className="aspect-video w-full rounded-[8px] bg-bg-grouped object-cover"
                  />
                  <video
                    ref={remoteVideo}
                    autoPlay
                    playsInline
                    className="aspect-video w-full rounded-[8px] bg-bg-grouped object-cover"
                  />
                </div>
              </div>
            </div>
          )}
        </div>
      </div>

      {incoming ? (
        <div className="fixed inset-0 z-50 grid place-items-center bg-white/92 px-6 backdrop-blur-sm">
          <div className="w-full max-w-sm rounded-[8px] border border-hairline bg-white p-6 text-center shadow-[0_20px_80px_rgba(10,10,10,0.10)]">
            <div className="mx-auto flex h-24 w-24 animate-gentle-pulse items-center justify-center rounded-full border border-hairline text-[28px] font-light text-text">
              {incoming.fromName.slice(0, 2).toUpperCase()}
            </div>
            <h2 className="mt-5 text-[30px] font-light text-text">{incoming.fromName}</h2>
            <p className="mt-1 text-[14px] text-text-secondary">Incoming browser call</p>
            <div className="mt-8 flex justify-center gap-8">
              <button
                className="flex h-16 w-16 items-center justify-center rounded-full bg-danger text-white"
                onClick={declineIncoming}
                aria-label="Decline"
              >
                <PhoneIcon className="h-7 w-7 rotate-[135deg]" />
              </button>
              <button
                className="flex h-16 w-16 items-center justify-center rounded-full bg-text text-white"
                onClick={() => acceptIncoming(true)}
                aria-label="Accept"
              >
                <VideoIcon className="h-7 w-7" />
              </button>
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
