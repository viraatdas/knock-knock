/* Slide web push service worker. Keep tiny, no deps. */

self.addEventListener("push", (event) => {
  let payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (_err) {
    payload = { body: event.data ? event.data.text() : "" };
  }

  const data = payload.data || {};
  const type = data.type || payload.type;
  const fromName = payload.title || data.fromName || "Slide";
  const body =
    payload.body ||
    (type === "knock" ? "is knocking" : "Incoming Slide call");

  const title = type === "knock" ? `${fromName} is knocking` : fromName;

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: "/icon-512.png",
      badge: "/icon-512.png",
      tag: data.callId ? `slide-${data.callId}` : "slide-call",
      renotify: true,
      requireInteraction: type !== "knock",
      data: { callId: data.callId, type },
    }),
  );
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const target = "/web";
  event.waitUntil(
    self.clients
      .matchAll({ type: "window", includeUncontrolled: true })
      .then((clients) => {
        for (const client of clients) {
          if (client.url.includes("/web") && "focus" in client) {
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
