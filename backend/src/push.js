import http2 from "node:http2";
import { createPrivateKey, sign } from "node:crypto";
import { pool } from "./database.js";

let cachedJwt = null;
let cachedAt = 0;

const b64 = input => Buffer.from(input).toString("base64url");

function makeJwt() {
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  const rawKey = process.env.APNS_PRIVATE_KEY;
  if (!keyId || !teamId || !rawKey) return null;
  const now = Math.floor(Date.now()/1000);
  if (cachedJwt && now - cachedAt < 45*60) return cachedJwt;
  const header = b64(JSON.stringify({ alg:"ES256", kid:keyId }));
  const payload = b64(JSON.stringify({ iss:teamId, iat:now }));
  const unsigned = `${header}.${payload}`;
  const key = createPrivateKey(rawKey.replace(/\\n/g,"\n"));
  const signature = sign("sha256", Buffer.from(unsigned), { key, dsaEncoding:"ieee-p1363" }).toString("base64url");
  cachedJwt = `${unsigned}.${signature}`;
  cachedAt = now;
  return cachedJwt;
}

async function sendToDevice(deviceToken, payload) {
  const jwt = makeJwt();
  const topic = process.env.APNS_BUNDLE_ID || "com.fodd.app";
  if (!jwt || !topic) return false;
  const host = process.env.APNS_ENVIRONMENT === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
  return await new Promise(resolve => {
    const client = http2.connect(host);
    client.on("error", error => { console.error("APNs connection", error.message); resolve(false); });
    const request = client.request({
      ":method":"POST",
      ":path":`/3/device/${deviceToken}`,
      "authorization":`bearer ${jwt}`,
      "apns-topic":topic,
      "apns-push-type":"alert",
      "apns-priority":"10"
    });
    let status = 0;
    request.on("response", headers => { status = Number(headers[":status"] || 0); });
    request.on("data", ()=>{});
    request.on("end", () => { client.close(); resolve(status >= 200 && status < 300); });
    request.on("error", error => { console.error("APNs request", error.message); client.close(); resolve(false); });
    request.end(JSON.stringify(payload));
  });
}

async function sendLiveActivityDevice(activityToken, payload) {
  const jwt = makeJwt();
  const topic = process.env.APNS_BUNDLE_ID || "com.fodd.app";
  if (!jwt || !topic) return false;
  const host = process.env.APNS_ENVIRONMENT === "production" ? "https://api.push.apple.com" : "https://api.sandbox.push.apple.com";
  return await new Promise(resolve => {
    const client = http2.connect(host);
    client.on("error", error => { console.error("APNs Live Activity connection", error.message); resolve(false); });
    const request = client.request({
      ":method":"POST",
      ":path":`/3/device/${activityToken}`,
      "authorization":`bearer ${jwt}`,
      "apns-topic":`${topic}.push-type.liveactivity`,
      "apns-push-type":"liveactivity",
      "apns-priority":"10"
    });
    let status = 0;
    request.on("response", headers => { status = Number(headers[":status"] || 0); });
    request.on("data", ()=>{});
    request.on("end", () => { client.close(); resolve(status >= 200 && status < 300); });
    request.on("error", error => { console.error("APNs Live Activity request", error.message); client.close(); resolve(false); });
    request.end(JSON.stringify(payload));
  });
}

export async function sendLiveActivityUpdate(planId, state, event="update") {
  if (!process.env.APNS_KEY_ID || !process.env.APNS_TEAM_ID || !process.env.APNS_PRIVATE_KEY) return;
  const result = await pool.query(`SELECT activity_token FROM live_activity_tokens WHERE plan_id=$1`, [planId]);
  if (!result.rowCount) return;
  const now = Math.floor(Date.now()/1000);
  const aps = {
    timestamp: now,
    event,
    "content-state": state
  };
  if (state?.scheduledAt && event === "update") aps["stale-date"] = Math.max(now + 60, Number(state.scheduledAt) + 15*60);
  if (event === "end") aps["dismissal-date"] = now + 5*60;
  await Promise.allSettled(result.rows.map(row => sendLiveActivityDevice(row.activity_token, { aps })));
  if (event === "end") await pool.query(`DELETE FROM live_activity_tokens WHERE plan_id=$1`, [planId]);
}

export async function sendPushToUser(userId, input={}) {
  const { title="Fodd", body="", type="general", ...context } = input;
  if (!process.env.APNS_KEY_ID || !process.env.APNS_TEAM_ID || !process.env.APNS_PRIVATE_KEY) return;
  const result = await pool.query(`SELECT device_token FROM device_tokens WHERE user_id=$1`, [userId]);
  const payload = { aps:{ alert:{ title, body }, sound:"default", badge:1 }, type, ...context };
  await Promise.allSettled(result.rows.map(row => sendToDevice(row.device_token, payload)));
}
