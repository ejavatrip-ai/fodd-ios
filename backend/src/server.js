import express from "express";
import cors from "cors";
import { z } from "zod";
import { migrateAndSeed, pool } from "./database.js";
import { createSession, hashPassword, requireAuth, verifyPassword } from "./auth.js";

if (!process.env.DATABASE_URL) { console.error("DATABASE_URL wajib tersedia"); process.exit(1); }
const app = express();
const port = Number(process.env.PORT || 3000);
app.disable("x-powered-by");
app.use(cors({ origin: process.env.ALLOWED_ORIGIN || "*" }));
app.use(express.json({ limit: "512kb" }));

const publicUserSQL = `u.id,u.name,u.username,u.bio,
  (SELECT COUNT(*)::int FROM follows WHERE following_id=u.id) AS "followersCount",
  (SELECT COUNT(*)::int FROM follows WHERE follower_id=u.id) AS "followingCount"`;

app.get("/health", async (_req,res,next) => { try { await pool.query("SELECT 1"); res.json({ status:"ok",service:"fodd-api",version:"2.0" }); } catch(e){ next(e); } });

const credentialsSchema = z.object({
  email: z.string().trim().toLowerCase().email(),
  password: z.string().min(8).max(100)
});
const registerSchema = credentialsSchema.extend({
  name: z.string().trim().min(2).max(80),
  username: z.string().trim().toLowerCase().regex(/^[a-z0-9_]{3,30}$/)
});

app.post("/api/auth/register", async (req,res,next) => {
  try {
    const input = registerSchema.parse(req.body);
    const password = hashPassword(input.password);
    const result = await pool.query(
      `INSERT INTO users(name,username,email,password_hash,password_salt) VALUES($1,$2,$3,$4,$5)
       RETURNING id,name,username,email,bio`,
      [input.name,input.username,input.email,password.hash,password.salt]
    );
    const token = await createSession(result.rows[0].id);
    res.status(201).json({ data:{ token,user:result.rows[0] } });
  } catch(e) { if (e.code === "23505") return res.status(409).json({ error:"Email atau username sudah digunakan" }); next(e); }
});

app.post("/api/auth/login", async (req,res,next) => {
  try {
    const input = credentialsSchema.parse(req.body);
    const result = await pool.query(`SELECT id,name,username,email,bio,password_hash,password_salt FROM users WHERE email=$1`,[input.email]);
    const user = result.rows[0];
    if (!user || !verifyPassword(input.password,user.password_salt,user.password_hash)) return res.status(401).json({ error:"Email atau password salah" });
    const token = await createSession(user.id);
    delete user.password_hash; delete user.password_salt;
    res.json({ data:{ token,user } });
  } catch(e) { next(e); }
});

app.post("/api/auth/logout", requireAuth, async (req,res,next) => { try { await pool.query(`DELETE FROM sessions WHERE token_hash=$1`,[req.tokenHash]); res.status(204).end(); } catch(e){ next(e); } });
app.get("/api/me", requireAuth, async (req,res) => res.json({ data:req.user }));

app.patch("/api/me", requireAuth, async (req,res,next) => {
  try {
    const input = z.object({ name:z.string().trim().min(2).max(80), bio:z.string().trim().max(240) }).parse(req.body);
    const result = await pool.query(`UPDATE users SET name=$1,bio=$2 WHERE id=$3 RETURNING id,name,username,email,bio`,[input.name,input.bio,req.user.id]);
    res.json({ data:result.rows[0] });
  } catch(e){ next(e); }
});

app.get("/api/users", requireAuth, async (req,res,next) => {
  try {
    const q = String(req.query.search || "").trim();
    const result = await pool.query(
      `SELECT ${publicUserSQL}, EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id) AS "isFollowing"
       FROM users u WHERE u.id<>$1 AND ($2='' OR u.name ILIKE '%'||$2||'%' OR u.username ILIKE '%'||$2||'%') ORDER BY u.name LIMIT 100`,
      [req.user.id,q]
    );
    res.json({ data:result.rows });
  } catch(e){ next(e); }
});

app.get("/api/users/:id", requireAuth, async (req,res,next) => {
  try {
    const result = await pool.query(`SELECT ${publicUserSQL}, EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id) AS "isFollowing" FROM users u WHERE u.id=$2`,[req.user.id,req.params.id]);
    if (!result.rowCount) return res.status(404).json({ error:"Member tidak ditemukan" });
    res.json({ data:result.rows[0] });
  } catch(e){ next(e); }
});

app.put("/api/users/:id/follow", requireAuth, async (req,res,next) => { try { await pool.query(`INSERT INTO follows(follower_id,following_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[req.user.id,req.params.id]); res.status(204).end(); } catch(e){ next(e); } });
app.delete("/api/users/:id/follow", requireAuth, async (req,res,next) => { try { await pool.query(`DELETE FROM follows WHERE follower_id=$1 AND following_id=$2`,[req.user.id,req.params.id]); res.status(204).end(); } catch(e){ next(e); } });

app.get("/api/restaurants", async (req,res,next) => {
  try { const q=String(req.query.search||"").trim(); const result=await pool.query(`SELECT id,name,category,image,rating::float8 AS rating,distance,price FROM restaurants WHERE ($1='' OR name ILIKE '%'||$1||'%' OR category ILIKE '%'||$1||'%') ORDER BY rating DESC`,[q]); res.json({data:result.rows}); } catch(e){next(e);}
});

app.get("/api/moments", requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`SELECT m.id,m.caption,m.image,m.likes,m.created_at AS "createdAt",u.id AS "userId",u.name,u.username FROM moments m JOIN users u ON u.id=m.user_id ORDER BY m.created_at DESC LIMIT 100`);
    res.json({data:result.rows});
  } catch(e){next(e);}
});

app.post("/api/moments", requireAuth, async (req,res,next) => {
  try {
    const input=z.object({caption:z.string().trim().min(1).max(500),image:z.enum(["FoodHero","Cafe","Noodles","Burgers"]).default("Noodles")}).parse(req.body);
    const result=await pool.query(`INSERT INTO moments(author,caption,image,user_id) VALUES($1,$2,$3,$4) RETURNING id,caption,image,likes,created_at AS "createdAt"`,[req.user.name,input.caption,input.image,req.user.id]);
    res.status(201).json({data:{...result.rows[0],userId:req.user.id,name:req.user.name,username:req.user.username}});
  } catch(e){next(e);}
});

app.get("/api/messages/:userId", requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`SELECT id,sender_id AS "senderId",receiver_id AS "receiverId",body,created_at AS "createdAt" FROM messages WHERE (sender_id=$1 AND receiver_id=$2) OR (sender_id=$2 AND receiver_id=$1) ORDER BY created_at`,[req.user.id,req.params.userId]);
    res.json({data:result.rows});
  } catch(e){next(e);}
});

app.post("/api/messages/:userId", requireAuth, async (req,res,next) => {
  try {
    const {body}=z.object({body:z.string().trim().min(1).max(1000)}).parse(req.body);
    const result=await pool.query(`INSERT INTO messages(sender_id,receiver_id,body) VALUES($1,$2,$3) RETURNING id,sender_id AS "senderId",receiver_id AS "receiverId",body,created_at AS "createdAt"`,[req.user.id,req.params.userId,body]);
    res.status(201).json({data:result.rows[0]});
  } catch(e){next(e);}
});

app.use((error,_req,res,_next) => {
  if (error instanceof z.ZodError) return res.status(400).json({error:"Data tidak valid",details:error.issues});
  if (error.code === "23503" || error.code === "23514") return res.status(400).json({error:"Data tidak dapat diproses"});
  console.error(error); res.status(500).json({error:"Terjadi kesalahan pada server"});
});

await migrateAndSeed();
app.listen(port,"0.0.0.0",()=>console.log(`Fodd API v2 aktif pada port ${port}`));
