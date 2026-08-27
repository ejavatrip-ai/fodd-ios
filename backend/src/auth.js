import { randomBytes, scryptSync, timingSafeEqual, createHash } from "node:crypto";
import { pool } from "./database.js";

const tokenHash = token => createHash("sha256").update(token).digest("hex");

export function hashPassword(password, salt = randomBytes(16).toString("hex")) {
  return { salt, hash: scryptSync(password, salt, 64).toString("hex") };
}

export function verifyPassword(password, salt, expectedHash) {
  const actual = Buffer.from(scryptSync(password, salt, 64).toString("hex"), "hex");
  const expected = Buffer.from(expectedHash, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

export async function createSession(userId) {
  const token = randomBytes(32).toString("base64url");
  await pool.query(
    `INSERT INTO sessions (token_hash,user_id,expires_at) VALUES ($1,$2,NOW() + INTERVAL '30 days')`,
    [tokenHash(token), userId]
  );
  return token;
}

export async function requireAuth(req, res, next) {
  try {
    const header = req.get("authorization") || "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token) return res.status(401).json({ error: "Silakan login" });
    const result = await pool.query(
      `SELECT u.id,u.name,u.username,u.email,u.bio
       FROM sessions s JOIN users u ON u.id=s.user_id
       WHERE s.token_hash=$1 AND s.expires_at>NOW()`, [tokenHash(token)]
    );
    if (!result.rowCount) return res.status(401).json({ error: "Sesi tidak valid atau kedaluwarsa" });
    req.user = result.rows[0];
    req.tokenHash = tokenHash(token);
    next();
  } catch (error) { next(error); }
}
