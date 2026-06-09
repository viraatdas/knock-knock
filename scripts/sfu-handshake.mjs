// Proves the API -> SFU join-token handshake against both live local services.
//   node scripts/sfu-handshake.mjs
// 1) phone-OTP login two users via the API (requires EXPOSE_DEV_OTP=true),
// 2) create a call -> receive { sfuUrl, joinToken, iceServers },
// 3) open the SFU media WebSocket with the join token -> expect UPGRADE,
//    send a `ping` -> expect a `pong`,
// 4) open with a bad token -> expect the upgrade to be REJECTED.
// Node 22+ has a global WebSocket and fetch.

const API = process.env.BASE || "http://localhost:8080/v1";
const SFU_HTTP = process.env.SFU || "http://localhost:9000";

const jget = async (r) => {
  if (!r.ok) throw new Error(`HTTP ${r.status} ${await r.text()}`);
  return r.json();
};

async function login(phone) {
  const otp = await jget(
    await fetch(`${API}/auth/request-otp`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone }),
    }),
  );
  if (!otp.devCode) {
    fail("request-otp did not return devCode; start the API with SMS_PROVIDER=console EXPOSE_DEV_OTP=true");
  }
  const v = await jget(
    await fetch(`${API}/auth/verify-otp`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ phone, code: otp.devCode }),
    }),
  );
  return v;
}

function connect(url, { expectOpen, sendPing }) {
  return new Promise((resolve) => {
    let settled = false;
    const done = (ok, detail) => {
      if (!settled) {
        settled = true;
        resolve({ ok, detail });
      }
    };
    let ws;
    try {
      ws = new WebSocket(url);
    } catch (e) {
      return done(!expectOpen, `ctor threw: ${e.message}`);
    }
    const t = setTimeout(() => {
      try { ws.close(); } catch {}
      done(!expectOpen, "timeout (no open)");
    }, 5000);

    ws.addEventListener("open", () => {
      if (!expectOpen) {
        clearTimeout(t);
        try { ws.close(); } catch {}
        return done(false, "opened but expected rejection");
      }
      if (sendPing) ws.send(JSON.stringify({ type: "ping" }));
      else { clearTimeout(t); ws.close(); done(true, "opened"); }
    });
    ws.addEventListener("message", (ev) => {
      const msg = typeof ev.data === "string" ? ev.data : "";
      if (msg.includes("pong")) {
        clearTimeout(t);
        ws.close();
        done(true, "opened + pong");
      }
    });
    ws.addEventListener("error", () => {
      clearTimeout(t);
      done(!expectOpen, "ws error (rejected)");
    });
    ws.addEventListener("close", (ev) => {
      if (!settled) {
        clearTimeout(t);
        done(!expectOpen, `closed code=${ev.code}`);
      }
    });
  });
}

const fail = (m) => { console.error("FAIL:", m); process.exit(1); };

(async () => {
  console.log("== health ==");
  const h = await (await fetch(`${SFU_HTTP}/health`)).text();
  if (h.trim() !== "ok") fail(`SFU health = ${h}`);
  console.log("SFU health ok");

  console.log("== login A + B ==");
  const a = await login(process.env.PHONE_A || "+14155550201");
  const b = await login(process.env.PHONE_B || "+14155550202");

  console.log("== A creates 1:1 call to B ==");
  const call = await jget(
    await fetch(`${API}/calls`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${a.accessToken}`,
      },
      body: JSON.stringify({ type: "one_to_one", participantUserIds: [b.user.id] }),
    }),
  );
  const { sfuUrl, joinToken, iceServers } = call;
  console.log("sfuUrl:", sfuUrl);
  console.log("iceServers:", JSON.stringify(iceServers));
  if (!joinToken) fail("no joinToken from API");

  console.log("== valid join token -> expect UPGRADE + pong ==");
  const good = await connect(`${sfuUrl}&token=${encodeURIComponent(joinToken)}`, {
    expectOpen: true,
    sendPing: true,
  });
  console.log(good.ok ? `OK accepted (${good.detail})` : `FAIL ${good.detail}`);
  if (!good.ok) fail("SFU rejected a valid join token");

  console.log("== bad join token -> expect REJECTION ==");
  const bad = await connect(`${sfuUrl}&token=not-a-real-token`, { expectOpen: false });
  console.log(bad.ok ? `OK rejected (${bad.detail})` : `FAIL ${bad.detail}`);
  if (!bad.ok) fail("SFU accepted a bad token (auth bypass!)");

  console.log("\nOK: API -> SFU handshake verified (auth gate + signaling round-trip)");
})().catch((e) => fail(e.stack || e.message));
