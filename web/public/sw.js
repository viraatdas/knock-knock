/* Slide web push service worker. Keep tiny, no deps. */

self.addEventListener("push", (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_err) {
    payload = { body: event.data ? event.data.text() : "" };
  }

  const data = payload.data || payload;
  const type = data.type || payload.type;
  const callId = data.callId || payload.callId || "";
  if ((type === "call_ended" || type === "call_declined") && callId) {
    event.waitUntil(
      self.registration
        .getNotifications({ tag: `slide-${callId}` })
        .then((notifications) => notifications.forEach((notification) => notification.close())),
    );
    return;
  }
  const ringStyle = data.ringStyle || payload.ringStyle || "call";
  const fromUserId = data.fromUserId || payload.fromUserId || "";
  const videoEnabled = data.videoEnabled ?? payload.videoEnabled ?? "true";
  const isCallInvite = type === "incoming_call";
  const isKnock =
    ringStyle === "knock" ||
    type === "knock" ||
    data.knock === true ||
    data.knock === "true";
  const fromName = payload.title || data.fromName || payload.fromName || "Slide";
  const body =
    payload.body ||
    (isKnock ? "is knocking" : "Incoming Slide call");

  const title = isKnock ? `${fromName} is knocking` : fromName;

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: "/icon-512.png",
      badge: "/icon-512.png",
      tag: callId ? `slide-${callId}` : isKnock ? "slide-knock" : "slide-call",
      renotify: true,
      requireInteraction: isCallInvite,
      data: {
        callId,
        type,
        ringStyle,
        knock: isKnock,
        fromUserId,
        fromName,
        videoEnabled,
      },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const call = event.notification.data || {};
  const params = new URLSearchParams();
  if (call.callId) params.set("incomingCallId", call.callId);
  const target = `/web${params.toString() ? `?${params.toString()}` : ""}`;
  event.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((clients) => {
        for (const client of clients) {
          if (client.url.includes("/web") && "focus" in client) {
            if ("postMessage" in client) {
              client.postMessage({ type: "slide-notification-click", call });
            }
            return client.focus();
          }
        }
        if (self.clients.openWindow) {
          return self.clients.openWindow(target);
        }
        return undefined;
      }),
  );
});
