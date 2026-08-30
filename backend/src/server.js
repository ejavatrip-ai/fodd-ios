import express from "express";
import { createHash, randomInt } from "node:crypto";
import cors from "cors";
import { z } from "zod";
import { migrateAndSeed, pool } from "./database.js";
import { createSession, hashPassword, requireAuth, verifyPassword } from "./auth.js";
import { sendEmail } from "./email.js";
import { sendPushToUser, sendLiveActivityUpdate } from "./push.js";

if (!process.env.DATABASE_URL) { console.error("DATABASE_URL wajib tersedia"); process.exit(1); }
const app = express();
const port = Number(process.env.PORT || 3000);
app.disable("x-powered-by");
if(process.env.NODE_ENV === "production") app.set("trust proxy",1);
app.use(cors({ origin: process.env.ALLOWED_ORIGIN || "*" }));
app.use(express.json({ limit:"12mb" }));
app.use((_req,res,next)=>{res.setHeader("X-Content-Type-Options","nosniff");res.setHeader("Referrer-Policy","no-referrer");res.setHeader("Permissions-Policy","camera=(), microphone=(), geolocation=()");if(process.env.NODE_ENV === "production")res.setHeader("Strict-Transport-Security","max-age=31536000; includeSubDomains");next();});
app.use("/api",(_req,res,next)=>{res.setHeader("Cache-Control","no-store");next();});

const rateBuckets=new Map();
function rateLimit(windowMs,max,prefix) {
  return (req,res,next) => {
    const now=Date.now();const key=`${prefix}:${req.ip}`;const current=rateBuckets.get(key);
    if(!current || current.resetAt<=now){rateBuckets.set(key,{count:1,resetAt:now+windowMs});return next();}
    if(current.count>=max){res.setHeader("Retry-After",String(Math.max(1,Math.ceil((current.resetAt-now)/1000))));return res.status(429).json({error:"Terlalu banyak permintaan. Coba lagi sebentar."});}
    current.count+=1;next();
  };
}
const authRateLimit=rateLimit(15*60*1000,60,"auth");
const codeRateLimit=rateLimit(15*60*1000,15,"auth-code");
const reportRateLimit=rateLimit(15*60*1000,30,"report");
setInterval(()=>{const now=Date.now();for(const [key,value] of rateBuckets)if(value.resetAt<=now)rateBuckets.delete(key);},10*60*1000).unref();

const publicUserSQL = `u.id,u.name,u.username,u.bio,u.avatar,u.is_private AS "isPrivate",u.is_creator AS "isCreator",u.creator_verified AS "creatorVerified",u.creator_category AS "creatorCategory",u.creator_website AS "creatorWebsite",
  (SELECT COUNT(*)::int FROM follows WHERE following_id=u.id) AS "followersCount",
  (SELECT COUNT(*)::int FROM follows WHERE follower_id=u.id) AS "followingCount"`;
const accountSQL = `u.id,u.name,u.username,u.email,u.bio,u.avatar,u.email_verified AS "isEmailVerified",u.is_private AS "isPrivate",u.is_creator AS "isCreator",u.creator_verified AS "creatorVerified",u.creator_category AS "creatorCategory",u.creator_website AS "creatorWebsite"`;
const restaurantSQL = `r.id,r.name,r.category,r.image,r.rating::float8 AS rating,r.distance,r.price,r.address,r.phone,r.hours,r.menu,r.website,r.latitude,r.longitude,r.is_verified AS "isVerified",(SELECT COUNT(*)::int FROM restaurant_owners ro WHERE ro.restaurant_id=r.id) AS "ownerCount"`;
const restaurantObjectSQL = `json_build_object(\'id\',r.id,\'name\',r.name,\'category\',r.category,\'image\',r.image,\'rating\',r.rating::float8,\'distance\',r.distance,\'price\',r.price,\'isSaved\',EXISTS(SELECT 1 FROM saved_restaurants sr WHERE sr.user_id=$1 AND sr.restaurant_id=r.id),\'address\',r.address,\'phone\',r.phone,\'hours\',r.hours,\'menu\',r.menu,\'website\',r.website,\'latitude\',r.latitude,\'longitude\',r.longitude,\'isVerified\',r.is_verified,\'ownerCount\',(SELECT COUNT(*)::int FROM restaurant_owners ro WHERE ro.restaurant_id=r.id))`;
const hashToken = token => createHash("sha256").update(token).digest("hex");
const exposeCodes = () => process.env.EXPOSE_AUTH_CODES === "true" || process.env.NODE_ENV !== "production";

app.get("/health", async (_req,res,next) => {
  try { await pool.query("SELECT 1"); res.json({ status:"ok",service:"fodd-api",version:"8.0" }); }
  catch(e){ next(e); }
});

const credentialsSchema=z.object({email:z.string().trim().toLowerCase().email(),password:z.string().min(8).max(100)});
const registerSchema=credentialsSchema.extend({name:z.string().trim().min(2).max(80),username:z.string().trim().toLowerCase().regex(/^[a-z0-9_]{3,30}$/)});

async function createAuthCode(userId,purpose) {
  const code=String(randomInt(100000,1000000));
  await pool.query(`DELETE FROM auth_codes WHERE user_id=$1 AND purpose=$2 AND consumed_at IS NULL`,[userId,purpose]);
  await pool.query(`INSERT INTO auth_codes(user_id,purpose,code_hash,expires_at) VALUES($1,$2,$3,NOW()+INTERVAL '15 minutes')`,[userId,purpose,hashToken(code)]);
  return code;
}
async function consumeAuthCode(userId,purpose,code) {
  const result=await pool.query(`UPDATE auth_codes SET consumed_at=NOW() WHERE id=(SELECT id FROM auth_codes WHERE user_id=$1 AND purpose=$2 AND code_hash=$3 AND consumed_at IS NULL AND expires_at>NOW() ORDER BY created_at DESC LIMIT 1) RETURNING id`,[userId,purpose,hashToken(code)]);
  return result.rowCount > 0;
}
async function deliverCode(user,purpose,code) {
  const verification=purpose === "email_verify";
  const subject=verification ? "Kode verifikasi Fodd":"Kode reset password Fodd";
  const action=verification ? "verifikasi email":"reset password";
  return sendEmail({to:user.email,subject,html:`<div style="font-family:Arial,sans-serif"><h2>Fodd</h2><p>Kode ${action} Anda:</p><p style="font-size:32px;font-weight:700;letter-spacing:6px">${code}</p><p>Kode berlaku 15 menit.</p></div>`});
}

async function pairBlocked(a,b) {
  const result=await pool.query(`SELECT 1 FROM blocks WHERE (blocker_id=$1 AND blocked_id=$2) OR (blocker_id=$2 AND blocked_id=$1) LIMIT 1`,[a,b]);
  return result.rowCount > 0;
}
async function pushIfEnabled(userId,type,payload) {
  const column={follow:"push_follows",like:"push_likes",comment:"push_comments",message:"push_messages",recommendation:"push_recommendations",together:"push_together"}[type];
  if(!column) return sendPushToUser(userId,payload);
  const result=await pool.query(`SELECT COALESCE((SELECT ${column} FROM user_preferences WHERE user_id=$1),TRUE) AS enabled`,[userId]);
  if(result.rows[0]?.enabled) return sendPushToUser(userId,payload);
}

async function broadcastDiningLiveActivity(planId,event="update") {
  try {
    const result=await pool.query(`SELECT p.status,p.scheduled_at AS "scheduledAt",
      COALESCE(sr.name,(SELECT r2.name FROM dining_plan_candidates dc JOIN restaurants r2 ON r2.id=dc.restaurant_id WHERE dc.plan_id=p.id ORDER BY (SELECT COUNT(*) FROM dining_plan_votes dv WHERE dv.plan_id=p.id AND dv.restaurant_id=dc.restaurant_id) DESC,dc.created_at LIMIT 1),'Voting restoran') AS "restaurantName",
      (1+(SELECT COUNT(*) FROM dining_plan_members dm WHERE dm.plan_id=p.id AND dm.rsvp='going'))::int AS "goingCount",
      (SELECT COUNT(*)::int FROM dining_plan_messages dmsg WHERE dmsg.plan_id=p.id) AS "messageCount"
      FROM dining_plans p LEFT JOIN restaurants sr ON sr.id=p.selected_restaurant_id WHERE p.id=$1`,[planId]);
    if(!result.rowCount)return;
    const row=result.rows[0];
    await sendLiveActivityUpdate(planId,{
      status:row.status,
      restaurantName:row.restaurantName,
      goingCount:Number(row.goingCount||1),
      messageCount:Number(row.messageCount||0),
      scheduledAt:Math.floor(new Date(row.scheduledAt).getTime()/1000)
    },event);
  } catch(error) { console.error("Live Activity update",error.message); }
}

const moderationTerms=String(process.env.MODERATION_TERMS||"").split(",").map(x=>x.trim().toLowerCase()).filter(Boolean);
function ensureSafeContent(text) {
  const value=String(text||"").trim();
  const lower=value.toLowerCase();
  const links=(value.match(/https?:\/\//gi)||[]).length;
  if(links>4 || /(.)\1{18,}/u.test(value) || moderationTerms.some(term=>lower.includes(term))) {
    const error=new Error("Konten terdeteksi sebagai spam atau melanggar filter komunitas");error.status=422;throw error;
  }
}

function requireAdmin(req,res,next) {
  const configured=String(process.env.ADMIN_TOKEN||"");
  if(!configured) return res.status(404).json({error:"Not found"});
  if(req.get("x-admin-token")!==configured) return res.status(403).json({error:"Akses admin ditolak"});
  next();
}

async function planAccess(userId,planId) {
  const result=await pool.query(`SELECT p.id,p.host_id AS "hostId",p.status,m.rsvp FROM dining_plans p LEFT JOIN dining_plan_members m ON m.plan_id=p.id AND m.user_id=$1 WHERE p.id=$2 AND (p.host_id=$1 OR m.user_id=$1) AND (p.host_id=$1 OR NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=p.host_id) OR (b.blocker_id=p.host_id AND b.blocked_id=$1)))`,[userId,planId]);
  return result.rows[0]||null;
}
async function collectionAccess(userId,collectionId) {
  const result=await pool.query(`SELECT c.id,c.user_id AS "ownerId",CASE WHEN c.user_id=$1 THEN 'owner' ELSE cm.role END AS role FROM collections c LEFT JOIN collection_members cm ON cm.collection_id=c.id AND cm.user_id=$1 WHERE c.id=$2 AND (c.user_id=$1 OR cm.user_id=$1 OR c.is_private=FALSE)`,[userId,collectionId]);
  return result.rows[0]||null;
}
async function restaurantManagementAccess(userId,restaurantId) {
  const result=await pool.query(`SELECT role FROM restaurant_owners WHERE restaurant_id=$1 AND user_id=$2`,[restaurantId,userId]);
  return result.rows[0]?.role||null;
}
async function hangoutInviteAllowed(hostId,targetId) {
  if(hostId===targetId || await pairBlocked(hostId,targetId)) return false;
  const pref=await pool.query(`SELECT COALESCE((SELECT invite_policy FROM hangout_preferences WHERE user_id=$1),'friends') AS policy`,[targetId]);
  const policy=pref.rows[0]?.policy || 'friends';
  if(policy==='everyone') return true;
  if(policy==='close_foodies') {
    const close=await pool.query(`SELECT 1 FROM close_foodies WHERE user_id=$1 AND member_id=$2 LIMIT 1`,[targetId,hostId]);
    return close.rowCount>0;
  }
  const mutual=await pool.query(`SELECT (EXISTS(SELECT 1 FROM follows WHERE follower_id=$1 AND following_id=$2) AND EXISTS(SELECT 1 FROM follows WHERE follower_id=$2 AND following_id=$1)) AS ok`,[hostId,targetId]);
  return Boolean(mutual.rows[0]?.ok);
}
async function loadDiningPlans(userId,planId=null) {
  const params=planId?[userId,planId]:[userId];
  const filter=planId?`AND p.id=$2`:``;
  const result=await pool.query(`SELECT p.id,p.title,p.note,p.scheduled_at AS "scheduledAt",p.status,p.host_id AS "hostId",p.created_at AS "createdAt",
    (p.host_id=$1) AS "isHost",COALESCE(me.rsvp,'going') AS "myRsvp",
    json_build_object('id',h.id,'name',h.name,'username',h.username,'avatar',h.avatar) AS host,
    CASE WHEN sr.id IS NULL THEN NULL ELSE json_build_object('id',sr.id,'name',sr.name,'category',sr.category,'image',sr.image,'rating',sr.rating::float8,'distance',sr.distance,'price',sr.price,'isSaved',EXISTS(SELECT 1 FROM saved_restaurants ssr WHERE ssr.user_id=$1 AND ssr.restaurant_id=sr.id),'address',sr.address,'phone',sr.phone,'hours',sr.hours,'menu',sr.menu,'website',sr.website,'latitude',sr.latitude,'longitude',sr.longitude) END AS "selectedRestaurant",
    (SELECT COUNT(*)::int+1 FROM dining_plan_members dpm WHERE dpm.plan_id=p.id) AS "memberCount",
    (SELECT COUNT(*)::int+1 FROM dining_plan_members dpm WHERE dpm.plan_id=p.id AND dpm.rsvp='going') AS "goingCount",
    (SELECT COUNT(*)::int FROM dining_plan_members dpm WHERE dpm.plan_id=p.id AND dpm.rsvp='maybe') AS "maybeCount",
    COALESCE((SELECT json_agg(json_build_object('id',u.id,'name',u.name,'username',u.username,'avatar',u.avatar,'rsvp',dpm.rsvp,'isHost',false) ORDER BY u.name) FROM dining_plan_members dpm JOIN users u ON u.id=dpm.user_id WHERE dpm.plan_id=p.id),'[]'::json) AS members,
    COALESCE((SELECT json_agg(json_build_object('restaurant',json_build_object('id',r.id,'name',r.name,'category',r.category,'image',r.image,'rating',r.rating::float8,'distance',r.distance,'price',r.price,'isSaved',EXISTS(SELECT 1 FROM saved_restaurants sx WHERE sx.user_id=$1 AND sx.restaurant_id=r.id),'address',r.address,'phone',r.phone,'hours',r.hours,'menu',r.menu,'website',r.website,'latitude',r.latitude,'longitude',r.longitude,'isVerified',r.is_verified,'ownerCount',(SELECT COUNT(*)::int FROM restaurant_owners ro WHERE ro.restaurant_id=r.id)),'voteCount',(SELECT COUNT(*)::int FROM dining_plan_votes v WHERE v.plan_id=p.id AND v.restaurant_id=r.id),'myVote',EXISTS(SELECT 1 FROM dining_plan_votes v WHERE v.plan_id=p.id AND v.restaurant_id=r.id AND v.user_id=$1),'proposedBy',proposer.name) ORDER BY (SELECT COUNT(*) FROM dining_plan_votes v WHERE v.plan_id=p.id AND v.restaurant_id=r.id) DESC,dpc.created_at) FROM dining_plan_candidates dpc JOIN restaurants r ON r.id=dpc.restaurant_id JOIN users proposer ON proposer.id=dpc.proposed_by WHERE dpc.plan_id=p.id),'[]'::json) AS candidates,
    (SELECT COUNT(*)::int FROM dining_plan_photos dp WHERE dp.plan_id=p.id) AS "photoCount",
    (SELECT COUNT(*)::int FROM dining_plan_messages dm WHERE dm.plan_id=p.id) AS "messageCount",
    COALESCE((SELECT json_agg(json_build_object('id',dto.id,'scheduledAt',dto.scheduled_at,'voteCount',(SELECT COUNT(*)::int FROM dining_plan_time_votes dtv WHERE dtv.option_id=dto.id),'myVote',EXISTS(SELECT 1 FROM dining_plan_time_votes dtv WHERE dtv.option_id=dto.id AND dtv.user_id=$1),'proposedBy',pu.name) ORDER BY dto.scheduled_at) FROM dining_plan_time_options dto JOIN users pu ON pu.id=dto.proposed_by WHERE dto.plan_id=p.id),'[]'::json) AS "timeOptions",
    COALESCE((SELECT json_agg(json_build_object('userId',pr.user_id,'name',pu.name,'avatar',pu.avatar,'status',pr.status,'etaMinutes',pr.eta_minutes,'updatedAt',pr.updated_at) ORDER BY CASE pr.status WHEN 'arrived' THEN 0 WHEN 'otw' THEN 1 ELSE 2 END,pu.name) FROM dining_plan_presence pr JOIN users pu ON pu.id=pr.user_id WHERE pr.plan_id=p.id),'[]'::json) AS presence
    FROM dining_plans p JOIN users h ON h.id=p.host_id LEFT JOIN dining_plan_members me ON me.plan_id=p.id AND me.user_id=$1 LEFT JOIN restaurants sr ON sr.id=p.selected_restaurant_id
    WHERE (p.host_id=$1 OR me.user_id=$1) ${filter} ORDER BY p.scheduled_at ASC`,params);
  return result.rows;
}

app.post("/api/auth/register", authRateLimit, async (req,res,next) => {
  try {
    const input=registerSchema.parse(req.body); const password=hashPassword(input.password);
    const result=await pool.query(`INSERT INTO users(name,username,email,password_hash,password_salt) VALUES($1,$2,$3,$4,$5) RETURNING id,name,username,email,bio,avatar,email_verified AS "isEmailVerified",is_private AS "isPrivate",is_creator AS "isCreator",creator_verified AS "creatorVerified",creator_category AS "creatorCategory",creator_website AS "creatorWebsite"`,[input.name,input.username,input.email,password.hash,password.salt]);
    const user=result.rows[0]; const token=await createSession(user.id);
    const code=await createAuthCode(user.id,"email_verify"); void deliverCode(user,"email_verify",code);
    res.status(201).json({data:{token,user}});
  } catch(e) { if(e.code==="23505") return res.status(409).json({error:"Email atau username sudah digunakan"}); next(e); }
});

app.post("/api/auth/login", authRateLimit, async (req,res,next) => {
  try {
    const input=credentialsSchema.parse(req.body);
    const result=await pool.query(`SELECT id,name,username,email,bio,avatar,email_verified AS "isEmailVerified",is_private AS "isPrivate",is_creator AS "isCreator",creator_verified AS "creatorVerified",creator_category AS "creatorCategory",creator_website AS "creatorWebsite",password_hash,password_salt FROM users WHERE email=$1`,[input.email]);
    const user=result.rows[0];
    if(!user || !verifyPassword(input.password,user.password_salt,user.password_hash)) return res.status(401).json({error:"Email atau password salah"});
    const token=await createSession(user.id); delete user.password_hash; delete user.password_salt;
    res.json({data:{token,user}});
  } catch(e){ next(e); }
});

app.post("/api/auth/forgot-password", codeRateLimit, async (req,res,next) => {
  try {
    const {email}=z.object({email:z.string().trim().toLowerCase().email()}).parse(req.body);
    const result=await pool.query(`SELECT id,email,name FROM users WHERE email=$1`,[email]);
    let devCode;
    if(result.rowCount) {
      const code=await createAuthCode(result.rows[0].id,"password_reset");
      const sent=await deliverCode(result.rows[0],"password_reset",code);
      if(exposeCodes() && !sent) devCode=code;
    }
    res.json({data:{message:"Jika email terdaftar, kode reset telah dikirim.",...(devCode?{devCode}:{})}});
  } catch(e){ next(e); }
});

app.post("/api/auth/reset-password", codeRateLimit, async (req,res,next) => {
  try {
    const input=z.object({email:z.string().trim().toLowerCase().email(),code:z.string().regex(/^\d{6}$/),newPassword:z.string().min(8).max(100)}).parse(req.body);
    const result=await pool.query(`SELECT id FROM users WHERE email=$1`,[input.email]);
    if(!result.rowCount || !(await consumeAuthCode(result.rows[0].id,"password_reset",input.code))) return res.status(400).json({error:"Kode reset tidak valid atau kedaluwarsa"});
    const password=hashPassword(input.newPassword);
    await pool.query(`UPDATE users SET password_hash=$1,password_salt=$2 WHERE id=$3`,[password.hash,password.salt,result.rows[0].id]);
    await pool.query(`DELETE FROM sessions WHERE user_id=$1`,[result.rows[0].id]);
    res.json({data:{message:"Password berhasil diubah"}});
  } catch(e){ next(e); }
});

app.post("/api/auth/change-password", requireAuth, async (req,res,next) => {
  try {
    const input=z.object({currentPassword:z.string().min(8).max(100),newPassword:z.string().min(8).max(100)}).parse(req.body);
    const result=await pool.query(`SELECT password_hash,password_salt FROM users WHERE id=$1`,[req.user.id]);
    if(!verifyPassword(input.currentPassword,result.rows[0].password_salt,result.rows[0].password_hash)) return res.status(401).json({error:"Password sekarang salah"});
    const password=hashPassword(input.newPassword);
    await pool.query(`UPDATE users SET password_hash=$1,password_salt=$2 WHERE id=$3`,[password.hash,password.salt,req.user.id]);
    await pool.query(`DELETE FROM sessions WHERE user_id=$1 AND token_hash<>$2`,[req.user.id,req.tokenHash]);
    res.json({data:{message:"Password berhasil diubah"}});
  } catch(e){ next(e); }
});

app.post("/api/auth/request-verification", codeRateLimit, requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`SELECT id,email,name,email_verified FROM users WHERE id=$1`,[req.user.id]); const user=result.rows[0];
    if(user.email_verified) return res.json({data:{message:"Email sudah terverifikasi"}});
    const code=await createAuthCode(user.id,"email_verify"); const sent=await deliverCode(user,"email_verify",code);
    res.json({data:{message:"Kode verifikasi telah dikirim.",...(exposeCodes()&&!sent?{devCode:code}:{})}});
  } catch(e){ next(e); }
});

app.post("/api/auth/verify-email", codeRateLimit, requireAuth, async (req,res,next) => {
  try {
    const {code}=z.object({code:z.string().regex(/^\d{6}$/)}).parse(req.body);
    if(!(await consumeAuthCode(req.user.id,"email_verify",code))) return res.status(400).json({error:"Kode verifikasi tidak valid atau kedaluwarsa"});
    const result=await pool.query(`UPDATE users u SET email_verified=TRUE WHERE id=$1 RETURNING id,name,username,email,bio,avatar,email_verified AS "isEmailVerified",is_private AS "isPrivate",is_creator AS "isCreator",creator_verified AS "creatorVerified",creator_category AS "creatorCategory",creator_website AS "creatorWebsite"`,[req.user.id]);
    res.json({data:result.rows[0]});
  } catch(e){ next(e); }
});

app.post("/api/auth/logout", requireAuth, async (req,res,next) => { try{await pool.query(`DELETE FROM sessions WHERE token_hash=$1`,[req.tokenHash]);res.status(204).end();}catch(e){next(e);} });
app.get("/api/me", requireAuth, async (req,res,next) => { try{const result=await pool.query(`SELECT ${accountSQL} FROM users u WHERE u.id=$1`,[req.user.id]);res.json({data:result.rows[0]});}catch(e){next(e);} });
app.patch("/api/me", requireAuth, async (req,res,next) => {
  try { const input=z.object({name:z.string().trim().min(2).max(80),bio:z.string().trim().max(280),avatar:z.string().max(7_000_000)}).parse(req.body);ensureSafeContent(input.bio); const result=await pool.query(`UPDATE users SET name=$1,bio=$2,avatar=$3 WHERE id=$4 RETURNING id,name,username,email,bio,avatar,email_verified AS "isEmailVerified",is_private AS "isPrivate",is_creator AS "isCreator",creator_verified AS "creatorVerified",creator_category AS "creatorCategory",creator_website AS "creatorWebsite"`,[input.name,input.bio,input.avatar,req.user.id]);res.json({data:result.rows[0]}); }
  catch(e){next(e);}
});
app.delete("/api/account", requireAuth, async (req,res,next) => {
  try { const {password}=z.object({password:z.string().min(8).max(100)}).parse(req.body);const result=await pool.query(`SELECT password_hash,password_salt FROM users WHERE id=$1`,[req.user.id]);if(!verifyPassword(password,result.rows[0].password_salt,result.rows[0].password_hash)) return res.status(401).json({error:"Password salah"});await pool.query(`DELETE FROM users WHERE id=$1`,[req.user.id]);res.json({data:{message:"Akun berhasil dihapus"}}); }
  catch(e){next(e);}
});

// Fodd 6.5 — Creator Studio
app.get("/api/creator/me", requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`SELECT u.id,u.is_creator AS "isCreator",u.creator_verified AS "isVerified",u.creator_category AS category,u.creator_website AS website,u.creator_since AS "creatorSince",
      (SELECT COUNT(*)::int FROM moments m WHERE m.user_id=u.id) AS "momentCount",
      (SELECT COUNT(*)::int FROM follows f WHERE f.following_id=u.id) AS "followersCount",
      (SELECT COUNT(*)::int FROM moment_likes ml JOIN moments m ON m.id=ml.moment_id WHERE m.user_id=u.id) AS "totalLikes",
      (SELECT COUNT(*)::int FROM comments c JOIN moments m ON m.id=c.moment_id WHERE m.user_id=u.id) AS "totalComments",
      (SELECT COUNT(*)::int FROM restaurant_reviews rr WHERE rr.user_id=u.id) + (SELECT COUNT(*)::int FROM place_reviews pr WHERE pr.user_id=u.id) AS "reviewCount"
      FROM users u WHERE u.id=$1`,[req.user.id]);
    res.json({data:result.rows[0]});
  } catch(e){next(e);}
});
app.patch("/api/creator/me", requireAuth, async (req,res,next) => {
  try {
    const input=z.object({isCreator:z.boolean(),category:z.string().trim().max(80).default(""),website:z.string().trim().max(500).default("")}).parse(req.body);
    const website=input.website && !/^https?:\/\//i.test(input.website) ? `https://${input.website}` : input.website;
    const result=await pool.query(`UPDATE users u SET is_creator=$1,creator_category=$2,creator_website=$3,creator_since=CASE WHEN $1 AND creator_since IS NULL THEN NOW() WHEN NOT $1 THEN NULL ELSE creator_since END,creator_verified=CASE WHEN $1 THEN creator_verified ELSE FALSE END WHERE u.id=$4 RETURNING ${accountSQL}`,[input.isCreator,input.category,website,req.user.id]);
    res.json({data:result.rows[0]});
  } catch(e){next(e);}
});

app.get("/api/users", requireAuth, async (req,res,next) => {
  try {
    const q=String(req.query.search||"").trim();
    const result=await pool.query(`SELECT ${publicUserSQL},
      EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id) AS "isFollowing",
      EXISTS(SELECT 1 FROM close_foodies cf WHERE cf.user_id=$1 AND cf.member_id=u.id) AS "isCloseFoodie",
      EXISTS(SELECT 1 FROM follow_requests fr WHERE fr.requester_id=$1 AND fr.target_id=u.id) AS "followRequestPending",
      EXISTS(SELECT 1 FROM blocks b WHERE b.blocker_id=$1 AND b.blocked_id=u.id) AS "isBlocked"
      FROM users u WHERE u.id<>$1
      AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=u.id AND b.blocked_id=$1) OR (b.blocker_id=$1 AND b.blocked_id=u.id))
      AND ($2='' OR u.name ILIKE '%'||$2||'%' OR u.username ILIKE '%'||$2||'%') ORDER BY u.name LIMIT 100`,[req.user.id,q]);
    res.json({data:result.rows});
  } catch(e){next(e);}
});
app.get("/api/users/:id", requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`SELECT ${publicUserSQL},
      EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id) AS "isFollowing",
      EXISTS(SELECT 1 FROM close_foodies cf WHERE cf.user_id=$1 AND cf.member_id=u.id) AS "isCloseFoodie",
      EXISTS(SELECT 1 FROM follow_requests fr WHERE fr.requester_id=$1 AND fr.target_id=u.id) AS "followRequestPending",
      EXISTS(SELECT 1 FROM blocks b WHERE b.blocker_id=$1 AND b.blocked_id=u.id) AS "isBlocked"
      FROM users u WHERE u.id=$2 AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=u.id AND b.blocked_id=$1) OR (b.blocker_id=$1 AND b.blocked_id=u.id))`,[req.user.id,req.params.id]);
    if(!result.rowCount)return res.status(404).json({error:"Member tidak ditemukan"});res.json({data:result.rows[0]});
  } catch(e){next(e);}
});
app.put("/api/users/:id/follow", requireAuth, async (req,res,next) => {
  try {
    if(req.params.id===req.user.id) return res.status(400).json({error:"Tidak dapat mengikuti akun sendiri"});
    if(await pairBlocked(req.user.id,req.params.id)) return res.status(403).json({error:"Interaksi tidak tersedia untuk akun ini"});
    const target=await pool.query(`SELECT id,is_private FROM users WHERE id=$1`,[req.params.id]);
    if(!target.rowCount) return res.status(404).json({error:"Member tidak ditemukan"});
    const existing=await pool.query(`SELECT 1 FROM follows WHERE follower_id=$1 AND following_id=$2`,[req.user.id,req.params.id]);
    if(existing.rowCount) return res.json({data:{isFollowing:true,pending:false,message:"Sudah mengikuti"}});
    if(target.rows[0].is_private) {
      const requested=await pool.query(`INSERT INTO follow_requests(requester_id,target_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING requester_id`,[req.user.id,req.params.id]);
      const body=`${req.user.name} meminta mengikuti akun Anda`;
      if(requested.rowCount){await pool.query(`INSERT INTO notifications(user_id,actor_id,type,body) VALUES($1,$2,'follow',$3)`,[req.params.id,req.user.id,body]);void pushIfEnabled(req.params.id,"follow",{title:"Permintaan mengikuti",body,type:"follow"});}
      return res.json({data:{isFollowing:false,pending:true,message:"Permintaan mengikuti dikirim"}});
    }
    const inserted=await pool.query(`INSERT INTO follows(follower_id,following_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING following_id`,[req.user.id,req.params.id]);
    if(inserted.rowCount){const body=`${req.user.name} mulai mengikuti Anda`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,body) VALUES($1,$2,'follow',$3)`,[req.params.id,req.user.id,body]);void pushIfEnabled(req.params.id,"follow",{title:"Pengikut baru",body,type:"follow"});}
    res.json({data:{isFollowing:true,pending:false,message:"Mengikuti"}});
  } catch(e){next(e);}
});
app.delete("/api/users/:id/follow", requireAuth, async (req,res,next) => {
  try{await pool.query(`DELETE FROM follows WHERE follower_id=$1 AND following_id=$2`,[req.user.id,req.params.id]);await pool.query(`DELETE FROM follow_requests WHERE requester_id=$1 AND target_id=$2`,[req.user.id,req.params.id]);res.status(204).end();}catch(e){next(e);}
});

app.get("/api/follow-requests", requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`SELECT json_build_object('id',u.id,'name',u.name,'username',u.username,'bio',u.bio,'avatar',u.avatar,'isPrivate',u.is_private,'followersCount',(SELECT COUNT(*)::int FROM follows WHERE following_id=u.id),'followingCount',(SELECT COUNT(*)::int FROM follows WHERE follower_id=u.id),'isFollowing',EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id),'isCloseFoodie',EXISTS(SELECT 1 FROM close_foodies cf WHERE cf.user_id=$1 AND cf.member_id=u.id),'followRequestPending',false,'isBlocked',false) AS member,fr.created_at AS "createdAt"
      FROM follow_requests fr JOIN users u ON u.id=fr.requester_id WHERE fr.target_id=$1
      AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=u.id) OR (b.blocker_id=u.id AND b.blocked_id=$1)) ORDER BY fr.created_at DESC`,[req.user.id]);
    res.json({data:result.rows});
  } catch(e){next(e);}
});
app.post("/api/follow-requests/:id", requireAuth, async (req,res,next) => {
  try {
    const {accept}=z.object({accept:z.boolean()}).parse(req.body);
    const pending=await pool.query(`DELETE FROM follow_requests WHERE requester_id=$1 AND target_id=$2 RETURNING requester_id`,[req.params.id,req.user.id]);
    if(!pending.rowCount) return res.status(404).json({error:"Permintaan tidak ditemukan"});
    if(accept && !(await pairBlocked(req.user.id,req.params.id))) {
      await pool.query(`INSERT INTO follows(follower_id,following_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[req.params.id,req.user.id]);
      const body=`${req.user.name} menyetujui permintaan mengikuti Anda`;
      await pool.query(`INSERT INTO notifications(user_id,actor_id,type,body) VALUES($1,$2,'follow',$3)`,[req.params.id,req.user.id,body]);
      void pushIfEnabled(req.params.id,"follow",{title:"Permintaan disetujui",body,type:"follow"});
    }
    res.status(204).end();
  } catch(e){next(e);}
});

app.get("/api/blocked-users", requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`SELECT ${publicUserSQL},false AS "isFollowing",false AS "isCloseFoodie",false AS "followRequestPending",true AS "isBlocked" FROM blocks b JOIN users u ON u.id=b.blocked_id WHERE b.blocker_id=$1 ORDER BY b.created_at DESC`,[req.user.id]);
    res.json({data:result.rows});
  } catch(e){next(e);}
});
app.put("/api/users/:id/block", requireAuth, async (req,res,next) => {
  const client=await pool.connect();
  try {
    if(req.params.id===req.user.id) return res.status(400).json({error:"Tidak dapat memblokir akun sendiri"});
    await client.query('BEGIN');
    await client.query(`INSERT INTO blocks(blocker_id,blocked_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[req.user.id,req.params.id]);
    await client.query(`DELETE FROM follows WHERE (follower_id=$1 AND following_id=$2) OR (follower_id=$2 AND following_id=$1)`,[req.user.id,req.params.id]);
    await client.query(`DELETE FROM follow_requests WHERE (requester_id=$1 AND target_id=$2) OR (requester_id=$2 AND target_id=$1)`,[req.user.id,req.params.id]);
    await client.query(`DELETE FROM close_foodies WHERE (user_id=$1 AND member_id=$2) OR (user_id=$2 AND member_id=$1)`,[req.user.id,req.params.id]);
    await client.query(`DELETE FROM collection_members cm USING collections c WHERE cm.collection_id=c.id AND ((c.user_id=$1 AND cm.user_id=$2) OR (c.user_id=$2 AND cm.user_id=$1))`,[req.user.id,req.params.id]);
    await client.query(`DELETE FROM dining_plan_members dpm USING dining_plans dp WHERE dpm.plan_id=dp.id AND ((dp.host_id=$1 AND dpm.user_id=$2) OR (dp.host_id=$2 AND dpm.user_id=$1))`,[req.user.id,req.params.id]);
    await client.query('COMMIT'); res.status(204).end();
  } catch(e){await client.query('ROLLBACK');next(e);} finally {client.release();}
});
app.delete("/api/users/:id/block", requireAuth, async (req,res,next) => { try{await pool.query(`DELETE FROM blocks WHERE blocker_id=$1 AND blocked_id=$2`,[req.user.id,req.params.id]);res.status(204).end();}catch(e){next(e);} });

// Fodd 6.1 — lingkaran teman kuliner dekat ala Inner Circle
app.get("/api/close-foodies", requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`SELECT ${publicUserSQL},EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id) AS "isFollowing",true AS "isCloseFoodie" FROM close_foodies cf JOIN users u ON u.id=cf.member_id WHERE cf.user_id=$1 ORDER BY cf.created_at DESC`,[req.user.id]);
    res.json({data:result.rows});
  } catch(e){next(e);}
});
app.put("/api/close-foodies/:id", requireAuth, async (req,res,next) => {
  try { if(req.params.id===req.user.id) return res.status(400).json({error:"Tidak dapat menambahkan akun sendiri"});if(await pairBlocked(req.user.id,req.params.id)) return res.status(403).json({error:"Interaksi tidak tersedia untuk akun ini"});await pool.query(`INSERT INTO close_foodies(user_id,member_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[req.user.id,req.params.id]);res.status(204).end(); }
  catch(e){next(e);}
});
app.delete("/api/close-foodies/:id", requireAuth, async (req,res,next) => {
  try { await pool.query(`DELETE FROM close_foodies WHERE user_id=$1 AND member_id=$2`,[req.user.id,req.params.id]);res.status(204).end(); }
  catch(e){next(e);}
});

app.get("/api/restaurants", async (req,res,next) => {
  try {
    const q=String(req.query.search||"").trim();const auth=(req.get("authorization")||"");const raw=auth.startsWith("Bearer ")?auth.slice(7):"";let userId=null;
    if(raw){const u=await pool.query(`SELECT user_id FROM sessions WHERE token_hash=$1 AND expires_at>NOW()`,[hashToken(raw)]);userId=u.rows[0]?.user_id||null;}
    const result=await pool.query(`SELECT ${restaurantSQL},COALESCE(sr.user_id IS NOT NULL,false) AS "isSaved" FROM restaurants r LEFT JOIN saved_restaurants sr ON sr.restaurant_id=r.id AND sr.user_id=$2 WHERE ($1='' OR r.name ILIKE '%'||$1||'%' OR r.category ILIKE '%'||$1||'%' OR r.address ILIKE '%'||$1||'%' OR r.menu ILIKE '%'||$1||'%') ORDER BY r.rating DESC`,[q,userId]);res.json({data:result.rows});
  } catch(e){next(e);}
});
app.put("/api/restaurants/:id", requireAuth, async (req,res,next) => {
  try {
    const input=z.object({name:z.string().trim().min(1).max(200),category:z.string().trim().max(100).default("Kuliner"),address:z.string().trim().max(500).default(""),phone:z.string().trim().max(80).default(""),website:z.string().trim().max(500).default(""),latitude:z.number().min(-90).max(90),longitude:z.number().min(-180).max(180),distance:z.string().trim().max(40).default("")}).parse(req.body);
    const existing=await pool.query(`SELECT is_verified FROM restaurants WHERE id=$1`,[req.params.id]);
    if(existing.rows[0]?.is_verified && !(await restaurantManagementAccess(req.user.id,req.params.id))) return res.status(403).json({error:"Restoran terverifikasi hanya dapat diubah oleh pengelolanya"});
    const result=await pool.query(`INSERT INTO restaurants AS r(id,name,category,image,rating,distance,price,address,phone,hours,menu,website,latitude,longitude) VALUES($1,$2,$3,'FoodHero',0,$4,'',$5,$6,'','',$7,$8,$9) ON CONFLICT(id) DO UPDATE SET name=CASE WHEN r.is_verified THEN r.name ELSE EXCLUDED.name END,category=CASE WHEN r.is_verified THEN r.category ELSE EXCLUDED.category END,distance=EXCLUDED.distance,address=CASE WHEN r.is_verified THEN r.address ELSE EXCLUDED.address END,phone=CASE WHEN r.is_verified THEN r.phone ELSE EXCLUDED.phone END,website=CASE WHEN r.is_verified THEN r.website ELSE EXCLUDED.website END,latitude=EXCLUDED.latitude,longitude=EXCLUDED.longitude RETURNING ${restaurantSQL}`,[req.params.id,input.name,input.category,input.distance,input.address,input.phone,input.website,input.latitude,input.longitude]);
    const saved=await pool.query(`SELECT EXISTS(SELECT 1 FROM saved_restaurants WHERE user_id=$1 AND restaurant_id=$2) AS value`,[req.user.id,req.params.id]);
    res.json({data:{...result.rows[0],isSaved:Boolean(saved.rows[0]?.value)}});
  } catch(e){next(e);}
});
app.put("/api/restaurants/:id/save", requireAuth, async (req,res,next)=>{try{await pool.query(`INSERT INTO saved_restaurants(user_id,restaurant_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[req.user.id,req.params.id]);await pool.query(`INSERT INTO smart_events(user_id,event_type,restaurant_id,weight) VALUES($1,'save',$2,4)`,[req.user.id,req.params.id]);res.status(204).end();}catch(e){next(e);}});
app.delete("/api/restaurants/:id/save", requireAuth, async (req,res,next)=>{try{await pool.query(`DELETE FROM saved_restaurants WHERE user_id=$1 AND restaurant_id=$2`,[req.user.id,req.params.id]);await pool.query(`INSERT INTO smart_events(user_id,event_type,restaurant_id,weight) VALUES($1,'unsave',$2,0.5)`,[req.user.id,req.params.id]);res.status(204).end();}catch(e){next(e);}});
app.get("/api/me/saved-restaurants",requireAuth,async(req,res,next)=>{try{const result=await pool.query(`SELECT ${restaurantSQL},true AS "isSaved" FROM restaurants r JOIN saved_restaurants s ON s.restaurant_id=r.id WHERE s.user_id=$1 ORDER BY s.created_at DESC`,[req.user.id]);res.json({data:result.rows});}catch(e){next(e);}});


// Fodd 6.5 — Restaurant Claim, Verified Restaurant & Restaurant Studio
app.post("/api/restaurants/:id/claim", requireAuth, async (req,res,next) => {
  try {
    const input=z.object({businessName:z.string().trim().min(1).max(160),role:z.enum(['owner','manager','staff']),note:z.string().trim().max(1000).default('')}).parse(req.body);ensureSafeContent(input.note);
    const restaurant=await pool.query(`SELECT id FROM restaurants WHERE id=$1`,[req.params.id]);if(!restaurant.rowCount)return res.status(404).json({error:"Restoran belum tersedia di Fodd"});
    if(await restaurantManagementAccess(req.user.id,req.params.id)) return res.status(409).json({error:"Anda sudah menjadi pengelola restoran ini"});
    const result=await pool.query(`INSERT INTO restaurant_claims(restaurant_id,user_id,business_name,role,note,status) VALUES($1,$2,$3,$4,$5,'pending') ON CONFLICT(restaurant_id,user_id) DO UPDATE SET business_name=EXCLUDED.business_name,role=EXCLUDED.role,note=EXCLUDED.note,status=CASE WHEN restaurant_claims.status='approved' THEN 'approved' ELSE 'pending' END,reviewed_at=NULL RETURNING id,restaurant_id AS "restaurantId",business_name AS "businessName",role,note,status,created_at AS "createdAt"`,[req.params.id,req.user.id,input.businessName,input.role,input.note]);
    res.status(201).json({data:result.rows[0]});
  } catch(e){next(e);}
});
app.get("/api/me/restaurant-claims", requireAuth, async (req,res,next) => {
  try {const result=await pool.query(`SELECT rc.id,rc.restaurant_id AS "restaurantId",r.name AS "restaurantName",rc.business_name AS "businessName",rc.role,rc.note,rc.status,rc.created_at AS "createdAt" FROM restaurant_claims rc JOIN restaurants r ON r.id=rc.restaurant_id WHERE rc.user_id=$1 ORDER BY rc.created_at DESC`,[req.user.id]);res.json({data:result.rows});}catch(e){next(e);}
});
app.get("/api/my-restaurants", requireAuth, async (req,res,next) => {
  try {const result=await pool.query(`SELECT ${restaurantSQL},true AS "isManagedByMe",ro.role AS "managementRole",EXISTS(SELECT 1 FROM saved_restaurants sr WHERE sr.user_id=$1 AND sr.restaurant_id=r.id) AS "isSaved" FROM restaurant_owners ro JOIN restaurants r ON r.id=ro.restaurant_id WHERE ro.user_id=$1 ORDER BY r.name`,[req.user.id]);res.json({data:result.rows});}catch(e){next(e);}
});
app.patch("/api/restaurant-studio/restaurants/:id", requireAuth, async (req,res,next) => {
  try {
    const role=await restaurantManagementAccess(req.user.id,req.params.id);if(!role)return res.status(403).json({error:"Anda bukan pengelola restoran ini"});
    if(role==='staff')return res.status(403).json({error:"Staff tidak dapat mengubah profil restoran"});
    const input=z.object({name:z.string().trim().min(1).max(200),category:z.string().trim().max(100),address:z.string().trim().max(500),phone:z.string().trim().max(80),hours:z.string().trim().max(500),website:z.string().trim().max(500),price:z.string().trim().max(60),image:z.string().max(7_000_000)}).parse(req.body);
    const result=await pool.query(`UPDATE restaurants r SET name=$1,category=$2,address=$3,phone=$4,hours=$5,website=$6,price=$7,image=$8 WHERE id=$9 RETURNING ${restaurantSQL}`,[input.name,input.category,input.address,input.phone,input.hours,input.website,input.price,input.image,req.params.id]);
    res.json({data:{...result.rows[0],isManagedByMe:true,managementRole:role,isSaved:false}});
  } catch(e){next(e);}
});
app.get("/api/restaurants/:id/menu", async (req,res,next) => {
  try {const result=await pool.query(`SELECT id,restaurant_id AS "restaurantId",name,description,category,price,image,is_available AS "isAvailable",sort_order AS "sortOrder",created_at AS "createdAt" FROM restaurant_menu_items WHERE restaurant_id=$1 ORDER BY category,sort_order,name`,[req.params.id]);res.json({data:result.rows});}catch(e){next(e);}
});
app.post("/api/restaurants/:id/menu", requireAuth, async (req,res,next) => {
  try {const role=await restaurantManagementAccess(req.user.id,req.params.id);if(!role)return res.status(403).json({error:"Anda bukan pengelola restoran ini"});const input=z.object({name:z.string().trim().min(1).max(120),description:z.string().trim().max(500).default(''),category:z.string().trim().max(80).default('Menu'),price:z.number().int().min(0).max(1_000_000_000),image:z.string().max(7_000_000).default(''),isAvailable:z.boolean().default(true),sortOrder:z.number().int().min(0).max(10000).default(0)}).parse(req.body);ensureSafeContent(`${input.name} ${input.description}`);const result=await pool.query(`INSERT INTO restaurant_menu_items(restaurant_id,name,description,category,price,image,is_available,sort_order) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id,restaurant_id AS "restaurantId",name,description,category,price,image,is_available AS "isAvailable",sort_order AS "sortOrder",created_at AS "createdAt"`,[req.params.id,input.name,input.description,input.category,input.price,input.image,input.isAvailable,input.sortOrder]);res.status(201).json({data:result.rows[0]});}catch(e){next(e);}
});
app.patch("/api/restaurants/:id/menu/:itemId", requireAuth, async (req,res,next) => {
  try {if(!(await restaurantManagementAccess(req.user.id,req.params.id)))return res.status(403).json({error:"Anda bukan pengelola restoran ini"});const input=z.object({name:z.string().trim().min(1).max(120),description:z.string().trim().max(500).default(''),category:z.string().trim().max(80).default('Menu'),price:z.number().int().min(0).max(1_000_000_000),image:z.string().max(7_000_000).default(''),isAvailable:z.boolean(),sortOrder:z.number().int().min(0).max(10000).default(0)}).parse(req.body);ensureSafeContent(`${input.name} ${input.description}`);const result=await pool.query(`UPDATE restaurant_menu_items SET name=$1,description=$2,category=$3,price=$4,image=$5,is_available=$6,sort_order=$7,updated_at=NOW() WHERE id=$8 AND restaurant_id=$9 RETURNING id,restaurant_id AS "restaurantId",name,description,category,price,image,is_available AS "isAvailable",sort_order AS "sortOrder",created_at AS "createdAt"`,[input.name,input.description,input.category,input.price,input.image,input.isAvailable,input.sortOrder,req.params.itemId,req.params.id]);if(!result.rowCount)return res.status(404).json({error:"Menu tidak ditemukan"});res.json({data:result.rows[0]});}catch(e){next(e);}
});
app.delete("/api/restaurants/:id/menu/:itemId", requireAuth, async (req,res,next) => {try{if(!(await restaurantManagementAccess(req.user.id,req.params.id)))return res.status(403).json({error:"Anda bukan pengelola restoran ini"});await pool.query(`DELETE FROM restaurant_menu_items WHERE id=$1 AND restaurant_id=$2`,[req.params.itemId,req.params.id]);res.status(204).end();}catch(e){next(e);}});
app.get("/api/restaurants/:id/posts", async (req,res,next) => {
  try {const result=await pool.query(`SELECT rp.id,rp.restaurant_id AS "restaurantId",rp.caption,rp.image,rp.created_at AS "createdAt",u.id AS "authorId",u.name AS "authorName",u.creator_verified AS "authorVerified" FROM restaurant_posts rp JOIN users u ON u.id=rp.author_id WHERE rp.restaurant_id=$1 ORDER BY rp.created_at DESC LIMIT 50`,[req.params.id]);res.json({data:result.rows});}catch(e){next(e);}
});
app.post("/api/restaurants/:id/posts", requireAuth, async (req,res,next) => {
  try {if(!(await restaurantManagementAccess(req.user.id,req.params.id)))return res.status(403).json({error:"Anda bukan pengelola restoran ini"});const input=z.object({caption:z.string().trim().min(1).max(1000),image:z.string().max(7_000_000).default('')}).parse(req.body);ensureSafeContent(input.caption);const result=await pool.query(`INSERT INTO restaurant_posts(restaurant_id,author_id,caption,image) VALUES($1,$2,$3,$4) RETURNING id,restaurant_id AS "restaurantId",caption,image,created_at AS "createdAt"`,[req.params.id,req.user.id,input.caption,input.image]);res.status(201).json({data:{...result.rows[0],authorId:req.user.id,authorName:req.user.name,authorVerified:Boolean(req.user.creator_verified)}});}catch(e){next(e);}
});
app.delete("/api/restaurants/:id/posts/:postId", requireAuth, async (req,res,next) => {try{if(!(await restaurantManagementAccess(req.user.id,req.params.id)))return res.status(403).json({error:"Anda bukan pengelola restoran ini"});await pool.query(`DELETE FROM restaurant_posts WHERE id=$1 AND restaurant_id=$2`,[req.params.postId,req.params.id]);res.status(204).end();}catch(e){next(e);}});

// Fodd 6.3 — Smart Food personalization (local scoring, no paid AI required)
const cuisineCatalog=["Indonesia","Jepang","Korea","China","Asia","Barat","Italian","Indian","Seafood","Burger","Mi","Kafe","Kopi","Dessert","Bakery","Halal","Vegetarian"];
const cuisineAliases={
  Indonesia:["indonesia","soto","rawon","rendang","bakso","nasi","ayam","warung","gado"],
  Jepang:["jepang","japanese","sushi","ramen","udon","sashimi","tempura"],
  Korea:["korea","korean","kimchi","bibimbap","tteok","bulgogi"],
  China:["china","chinese","dim sum","dimsum","kwetiau","wonton"],
  Italian:["italian","pizza","pasta","risotto"],
  Indian:["indian","curry","biryani","tandoori"],
  Seafood:["seafood","ikan","udang","kepiting","crab","fish"],
  Burger:["burger","hamburger"],
  Mi:["mie","mi ","noodle","ramen","udon"],
  Kafe:["kafe","cafe","coffee shop","kopitiam"],
  Kopi:["kopi","coffee","espresso","latte"],
  Dessert:["dessert","cake","gelato","ice cream","es krim","patisserie"],
  Bakery:["bakery","roti","bread","pastry"],
  Halal:["halal"],
  Vegetarian:["vegetarian","vegan","plant based"]
};
const moodCatalog=["Pedas","Coffee Time","Date Night","Hemat","Comfort Food","Dessert","Sarapan","Hidden Gems"];
const clamp=(value,min,max)=>Math.max(min,Math.min(max,value));
const cleanToken=value=>String(value||"").trim().replace(/\s+/g," ");
const restaurantTerms=restaurant=>`${restaurant.name||""} ${restaurant.category||""} ${restaurant.menu||""}`.toLowerCase();
const moodTerms={
  "Pedas":["pedas","sambal","spicy","chili","mie","mi"],
  "Coffee Time":["kopi","coffee","cafe","kafe","bakery"],
  "Date Night":["italian","barat","sushi","jepang","dessert","cafe","kafe"],
  "Hemat":["mie","mi","bakso","warung","nasi","ayam"],
  "Comfort Food":["nasi","mie","mi","soto","bakso","ayam","indonesia"],
  "Dessert":["dessert","cake","bakery","ice cream","es krim","sweet"],
  "Sarapan":["sarapan","breakfast","kopi","coffee","roti","bakery"],
  "Hidden Gems":[]
};
async function loadTastePreferences(userId){
  await pool.query(`INSERT INTO taste_preferences(user_id) VALUES($1) ON CONFLICT DO NOTHING`,[userId]);
  const result=await pool.query(`SELECT cuisines,moods,spicy_level AS "spicyLevel",price_sensitivity AS "priceSensitivity",adventurous_level AS "adventurousLevel",updated_at AS "updatedAt" FROM taste_preferences WHERE user_id=$1`,[userId]);
  return result.rows[0];
}
async function buildTasteDNA(userId){
  const preferences=await loadTastePreferences(userId);
  const [signals,querySignals]=await Promise.all([
    pool.query(`
      SELECT r.name,r.category,r.menu,4::float8 AS weight FROM saved_restaurants s JOIN restaurants r ON r.id=s.restaurant_id WHERE s.user_id=$1
      UNION ALL SELECT r.name,r.category,r.menu,3::float8 FROM collection_restaurants cr JOIN collections c ON c.id=cr.collection_id JOIN restaurants r ON r.id=cr.restaurant_id WHERE c.user_id=$1
      UNION ALL SELECT r.name,r.category,r.menu,LEAST(4,GREATEST(1,se.weight::float8)) FROM smart_events se JOIN restaurants r ON r.id=se.restaurant_id WHERE se.user_id=$1 AND se.created_at>NOW()-INTERVAL '120 days'
    `,[userId]),
    pool.query(`SELECT query,weight::float8 FROM smart_events WHERE user_id=$1 AND query<>'' AND created_at>NOW()-INTERVAL '120 days' ORDER BY created_at DESC LIMIT 120`,[userId])
  ]);
  const scores=new Map();
  for(const cuisine of preferences.cuisines||[]) scores.set(cuisine,(scores.get(cuisine)||0)+8);
  for(const row of signals.rows){
    const text=`${row.name||""} ${row.category||""} ${row.menu||""}`.toLowerCase();
    for(const cuisine of cuisineCatalog){
      const aliases=cuisineAliases[cuisine]||[cuisine.toLowerCase()];
      if(aliases.some(term=>text.includes(term))) scores.set(cuisine,(scores.get(cuisine)||0)+Number(row.weight||1));
    }
  }
  for(const row of querySignals.rows){
    const text=String(row.query||"").toLowerCase();
    for(const cuisine of cuisineCatalog){ const aliases=cuisineAliases[cuisine]||[cuisine.toLowerCase()];if(aliases.some(term=>text.includes(term))) scores.set(cuisine,(scores.get(cuisine)||0)+Math.min(2,Number(row.weight||1))); }
  }
  const favoriteCategories=[...scores.entries()].sort((a,b)=>b[1]-a[1]).slice(0,5).map(([name])=>name);
  if(!favoriteCategories.length) favoriteCategories.push("Indonesia","Kafe","Mi");
  const traits=[
    {name:"Food Explorer",score:clamp(45+preferences.adventurousLevel*12+(signals.rowCount>5?8:0),0,100),icon:"sparkles"},
    {name:"Spicy Hunter",score:clamp(20+preferences.spicyLevel*19,0,100),icon:"flame.fill"},
    {name:"Value Seeker",score:clamp(25+preferences.priceSensitivity*17,0,100),icon:"banknote.fill"}
  ];
  const sampleSize=signals.rowCount+querySignals.rowCount+(preferences.cuisines?.length||0);
  return {favoriteCategories,traits,sampleSize,confidence:clamp(35+sampleSize*5,35,96),preferences,updatedAt:new Date().toISOString()};
}
function matchRestaurant(restaurant,taste,mood,eventScore=0){
  const text=restaurantTerms(restaurant);let score=50+Number(restaurant.rating||0)*5;
  const matches=[];
  for(const category of taste.favoriteCategories){ const aliases=cuisineAliases[category]||[category.toLowerCase()];if(aliases.some(term=>text.includes(term))){score+=7;matches.push(category);} }
  for(const category of taste.preferences.cuisines||[]){ const aliases=cuisineAliases[category]||[String(category).toLowerCase()];if(aliases.some(term=>text.includes(term))) score+=5; }
  const desiredMood=cleanToken(mood);
  if(desiredMood && moodTerms[desiredMood]){
    const hit=moodTerms[desiredMood].some(term=>text.includes(term));
    if(hit){score+=12;matches.unshift(desiredMood);} else if(desiredMood!=="Hidden Gems") score-=5;
  }
  score+=Math.min(8,Number(eventScore||0));
  const matchScore=Math.round(clamp(score,55,99));
  let reason=matches.length?`Cocok dengan ${matches.slice(0,2).join(" • ")}`:`Rating ${Number(restaurant.rating||0).toFixed(1)} dan populer di Fodd`;
  const badges=[];if(matchScore>=90)badges.push("Best Match");if(Number(restaurant.rating)>=4.7)badges.push("Top Rated");if(desiredMood)badges.push(desiredMood);
  return {restaurant,matchScore,reason,badges};
}
function distanceKm(lat1,lon1,lat2,lon2){
  if([lat1,lon1,lat2,lon2].some(v=>v===null||v===undefined||!Number.isFinite(Number(v)))) return null;
  const rad=x=>Number(x)*Math.PI/180;const dLat=rad(lat2-lat1),dLon=rad(lon2-lon1);const a=Math.sin(dLat/2)**2+Math.cos(rad(lat1))*Math.cos(rad(lat2))*Math.sin(dLon/2)**2;return 6371*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a));
}
app.get("/api/smart/preferences",requireAuth,async(req,res,next)=>{try{res.json({data:await loadTastePreferences(req.user.id)});}catch(e){next(e);}});
app.patch("/api/smart/preferences",requireAuth,async(req,res,next)=>{
  try{
    const input=z.object({cuisines:z.array(z.string().trim().min(1).max(40)).max(12),moods:z.array(z.string().trim().min(1).max(40)).max(12),spicyLevel:z.number().int().min(0).max(4),priceSensitivity:z.number().int().min(0).max(4),adventurousLevel:z.number().int().min(0).max(4)}).parse(req.body);
    const result=await pool.query(`INSERT INTO taste_preferences(user_id,cuisines,moods,spicy_level,price_sensitivity,adventurous_level,updated_at) VALUES($1,$2,$3,$4,$5,$6,NOW()) ON CONFLICT(user_id) DO UPDATE SET cuisines=EXCLUDED.cuisines,moods=EXCLUDED.moods,spicy_level=EXCLUDED.spicy_level,price_sensitivity=EXCLUDED.price_sensitivity,adventurous_level=EXCLUDED.adventurous_level,updated_at=NOW() RETURNING cuisines,moods,spicy_level AS "spicyLevel",price_sensitivity AS "priceSensitivity",adventurous_level AS "adventurousLevel",updated_at AS "updatedAt"`,[req.user.id,input.cuisines,input.moods,input.spicyLevel,input.priceSensitivity,input.adventurousLevel]);
    res.json({data:result.rows[0]});
  }catch(e){next(e);}
});
app.post("/api/smart/events",requireAuth,async(req,res,next)=>{
  try{const input=z.object({eventType:z.enum(['view','search','save','unsave','collection_add','review','checkin','recommendation_open']),restaurantId:z.string().max(300).nullable().optional(),query:z.string().max(200).default(""),weight:z.number().min(0.1).max(10).default(1)}).parse(req.body);await pool.query(`INSERT INTO smart_events(user_id,event_type,restaurant_id,query,weight) VALUES($1,$2,$3,$4,$5)`,[req.user.id,input.eventType,input.restaurantId||null,input.query,input.weight]);res.status(204).end();}catch(e){next(e);}
});
app.get("/api/smart/dashboard",requireAuth,async(req,res,next)=>{
  try{
    const taste=await buildTasteDNA(req.user.id);const mood=cleanToken(req.query.mood);const lat=Number(req.query.lat),lon=Number(req.query.lon);
    const [restaurantResult,eventResult,memoryResult,basisResult]=await Promise.all([
      pool.query(`SELECT ${restaurantSQL},EXISTS(SELECT 1 FROM saved_restaurants sr WHERE sr.user_id=$1 AND sr.restaurant_id=r.id) AS "isSaved" FROM restaurants r`,[req.user.id]),
      pool.query(`SELECT restaurant_id,COUNT(*)::int AS events,SUM(weight)::float8 AS score FROM smart_events WHERE created_at>NOW()-INTERVAL '14 days' AND restaurant_id IS NOT NULL GROUP BY restaurant_id`,[]),
      pool.query(`SELECT m.id,m.caption,m.image,m.location_name AS "locationName",m.location_address AS "locationAddress",m.created_at AS "createdAt",GREATEST(1,EXTRACT(YEAR FROM AGE(NOW(),m.created_at))::int) AS "yearsAgo" FROM moments m WHERE m.user_id=$1 AND m.created_at<NOW()-INTERVAL '300 days' ORDER BY ABS(EXTRACT(DOY FROM NOW())-EXTRACT(DOY FROM m.created_at)),m.created_at DESC LIMIT 6`,[req.user.id]),
      pool.query(`SELECT r.name,r.category FROM saved_restaurants s JOIN restaurants r ON r.id=s.restaurant_id WHERE s.user_id=$1 ORDER BY s.created_at DESC LIMIT 1`,[req.user.id])
    ]);
    const eventMap=new Map(eventResult.rows.map(r=>[r.restaurant_id,{events:Number(r.events),score:Number(r.score||0)}]));
    const ranked=restaurantResult.rows.map(r=>{const scored=matchRestaurant(r,taste,mood,eventMap.get(r.id)?.score||0);const km=distanceKm(lat,lon,r.latitude,r.longitude);return {...scored,distanceKm:km};}).sort((a,b)=>b.matchScore-a.matchScore || Number(b.restaurant.rating)-Number(a.restaurant.rating));
    const forYou=ranked.slice(0,12);
    const nearbyRanked=ranked.filter(x=>x.distanceKm===null||x.distanceKm<=25);
    const trending=[...(nearbyRanked.length?nearbyRanked:ranked)].sort((a,b)=>(eventMap.get(b.restaurant.id)?.events||0)-(eventMap.get(a.restaurant.id)?.events||0)||(a.distanceKm??999)-(b.distanceKm??999)||Number(b.restaurant.rating)-Number(a.restaurant.rating)).slice(0,10).map(x=>({...x,badges:[...new Set(["Trending",...x.badges])]}));
    const hiddenGems=(nearbyRanked.length?nearbyRanked:ranked).filter(x=>Number(x.restaurant.rating)>=4.5&&(eventMap.get(x.restaurant.id)?.events||0)<=4).sort((a,b)=>Number(b.restaurant.rating)-Number(a.restaurant.rating)||(a.distanceKm??999)-(b.distanceKm??999)).slice(0,10).map(x=>({...x,reason:"Rating tinggi, belum terlalu ramai",badges:[...new Set(["Hidden Gem",...x.badges])]}));
    const basis=basisResult.rows[0]||null;const basisTokens=String(basis?.category||"").toLowerCase().split(/[•,]/).map(x=>x.trim()).filter(x=>x.length>2);
    const becauseYouLiked=basis ? ranked.filter(x=>x.restaurant.name!==basis.name && basisTokens.some(t=>restaurantTerms(x.restaurant).includes(t))).slice(0,8).map(x=>({...x,reason:`Karena Anda menyimpan ${basis.name}`,badges:[...new Set(["Because You Liked",...x.badges])]})) : [];
    res.json({data:{taste,forYou,becauseYouLiked,becauseBasis:basis?.name||null,trending,hiddenGems,memories:memoryResult.rows,moods:moodCatalog}});
  }catch(e){next(e);}
});


app.get("/api/smart/taste-match/:userId",requireAuth,async(req,res,next)=>{try{
  if(req.params.userId===req.user.id)return res.json({data:{score:100,label:'Ini Taste DNA Anda',commonCategories:[],commonMoods:[]}});
  if(await pairBlocked(req.user.id,req.params.userId))return res.status(403).json({error:'Taste Match tidak tersedia untuk akun ini'});
  const target=await pool.query(`SELECT is_private FROM users WHERE id=$1`,[req.params.userId]);if(!target.rowCount)return res.status(404).json({error:'User tidak ditemukan'});
  if(target.rows[0].is_private){const follow=await pool.query(`SELECT 1 FROM follows WHERE follower_id=$1 AND following_id=$2`,[req.user.id,req.params.userId]);if(!follow.rowCount)return res.status(403).json({error:'Ikuti akun privat ini untuk melihat Taste Match'});}
  const [a,b]=await Promise.all([buildTasteDNA(req.user.id),buildTasteDNA(req.params.userId)]);
  const setA=new Set([...(a.favoriteCategories||[]),...(a.preferences.cuisines||[])]),setB=new Set([...(b.favoriteCategories||[]),...(b.preferences.cuisines||[])]);
  const common=[...setA].filter(x=>setB.has(x));const union=new Set([...setA,...setB]);
  const moodA=new Set(a.preferences.moods||[]),moodB=new Set(b.preferences.moods||[]),commonMoods=[...moodA].filter(x=>moodB.has(x));
  const cuisineScore=union.size?common.length/union.size:0.45;const moodUnion=new Set([...moodA,...moodB]);const moodScore=moodUnion.size?commonMoods.length/moodUnion.size:0.45;
  const traitNames=['spicyLevel','priceSensitivity','adventurousLevel'];const traitScore=traitNames.reduce((sum,key)=>sum+(1-Math.abs(Number(a.preferences[key]||0)-Number(b.preferences[key]||0))/4),0)/traitNames.length;
  const score=Math.round(clamp(45+cuisineScore*30+moodScore*10+traitScore*15,45,99));const label=score>=90?'Taste Twins':score>=80?'Sangat Cocok':score>=68?'Banyak Kesamaan':'Seru untuk Eksplor';
  res.json({data:{score,label,commonCategories:common.slice(0,5),commonMoods:commonMoods.slice(0,4)}});
}catch(e){next(e);}});

// Fodd 6.2 — privacy, notification controls, collections, moderation
app.get("/api/settings", requireAuth, async (req,res,next) => {
  try {
    await pool.query(`INSERT INTO user_preferences(user_id) VALUES($1) ON CONFLICT DO NOTHING`,[req.user.id]);
    const result=await pool.query(`SELECT u.is_private AS "isPrivate",p.push_follows AS "pushFollows",p.push_likes AS "pushLikes",p.push_comments AS "pushComments",p.push_messages AS "pushMessages",p.push_recommendations AS "pushRecommendations",p.push_together AS "pushTogether" FROM users u JOIN user_preferences p ON p.user_id=u.id WHERE u.id=$1`,[req.user.id]);
    res.json({data:result.rows[0]});
  } catch(e){next(e);}
});
app.patch("/api/settings", requireAuth, async (req,res,next) => {
  const client=await pool.connect();
  try {
    const input=z.object({isPrivate:z.boolean(),pushFollows:z.boolean(),pushLikes:z.boolean(),pushComments:z.boolean(),pushMessages:z.boolean(),pushRecommendations:z.boolean().default(true),pushTogether:z.boolean().default(true)}).parse(req.body);
    await client.query('BEGIN');
    await client.query(`UPDATE users SET is_private=$1 WHERE id=$2`,[input.isPrivate,req.user.id]);
    await client.query(`INSERT INTO user_preferences(user_id,push_follows,push_likes,push_comments,push_messages,push_recommendations,push_together,updated_at) VALUES($1,$2,$3,$4,$5,$6,$7,NOW()) ON CONFLICT(user_id) DO UPDATE SET push_follows=EXCLUDED.push_follows,push_likes=EXCLUDED.push_likes,push_comments=EXCLUDED.push_comments,push_messages=EXCLUDED.push_messages,push_recommendations=EXCLUDED.push_recommendations,push_together=EXCLUDED.push_together,updated_at=NOW()`,[req.user.id,input.pushFollows,input.pushLikes,input.pushComments,input.pushMessages,input.pushRecommendations,input.pushTogether]);
    if(!input.isPrivate) {
      await client.query(`INSERT INTO follows(follower_id,following_id) SELECT requester_id,target_id FROM follow_requests WHERE target_id=$1 ON CONFLICT DO NOTHING`,[req.user.id]);
      await client.query(`DELETE FROM follow_requests WHERE target_id=$1`,[req.user.id]);
    }
    await client.query('COMMIT');
    res.json({data:input});
  } catch(e){await client.query('ROLLBACK');next(e);} finally {client.release();}
});

app.get("/api/collections", requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`SELECT c.id,c.name,c.description,c.is_private AS "isPrivate",c.created_at AS "createdAt",c.user_id AS "ownerId",u.name AS "ownerName",CASE WHEN c.user_id=$1 THEN 'owner' ELSE cm.role END AS "myRole",COUNT(DISTINCT cr.restaurant_id)::int AS "itemCount",COUNT(DISTINCT cm2.user_id)::int AS "memberCount" FROM collections c JOIN users u ON u.id=c.user_id LEFT JOIN collection_members cm ON cm.collection_id=c.id AND cm.user_id=$1 LEFT JOIN collection_members cm2 ON cm2.collection_id=c.id LEFT JOIN collection_restaurants cr ON cr.collection_id=c.id WHERE c.user_id=$1 OR cm.user_id=$1 GROUP BY c.id,u.name,cm.role ORDER BY c.updated_at DESC,c.created_at DESC`,[req.user.id]);
    res.json({data:result.rows});
  } catch(e){next(e);}
});
app.post("/api/collections", requireAuth, async (req,res,next) => {
  try {
    const input=z.object({name:z.string().trim().min(1).max(60),description:z.string().trim().max(240).default(""),isPrivate:z.boolean().default(true)}).parse(req.body);
    const result=await pool.query(`INSERT INTO collections(user_id,name,description,is_private) VALUES($1,$2,$3,$4) RETURNING id,name,description,is_private AS "isPrivate",created_at AS "createdAt",user_id AS "ownerId"`,[req.user.id,input.name,input.description,input.isPrivate]);
    res.status(201).json({data:{...result.rows[0],ownerName:req.user.name,myRole:'owner',memberCount:0,itemCount:0}});
  } catch(e){next(e);}
});
app.delete("/api/collections/:id", requireAuth, async (req,res,next) => {
  try { const result=await pool.query(`DELETE FROM collections WHERE id=$1 AND user_id=$2 RETURNING id`,[req.params.id,req.user.id]);if(!result.rowCount)return res.status(404).json({error:"Koleksi tidak ditemukan atau Anda bukan owner"});res.status(204).end(); } catch(e){next(e);}
});
app.get("/api/collections/:id/restaurants", requireAuth, async (req,res,next) => {
  try {
    const access=await collectionAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Koleksi tidak ditemukan"});
    const result=await pool.query(`SELECT ${restaurantSQL},EXISTS(SELECT 1 FROM saved_restaurants sr WHERE sr.user_id=$1 AND sr.restaurant_id=r.id) AS "isSaved" FROM collection_restaurants cr JOIN restaurants r ON r.id=cr.restaurant_id WHERE cr.collection_id=$2 ORDER BY cr.created_at DESC`,[req.user.id,req.params.id]);
    res.json({data:result.rows});
  } catch(e){next(e);}
});
app.put("/api/collections/:id/restaurants/:restaurantId", requireAuth, async (req,res,next) => {
  try {
    const access=await collectionAccess(req.user.id,req.params.id);if(!access || !['owner','editor'].includes(access.role))return res.status(403).json({error:"Anda tidak memiliki izin mengedit koleksi ini"});
    await pool.query(`INSERT INTO collection_restaurants(collection_id,restaurant_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[req.params.id,req.params.restaurantId]);await pool.query(`UPDATE collections SET updated_at=NOW() WHERE id=$1`,[req.params.id]);await pool.query(`INSERT INTO smart_events(user_id,event_type,restaurant_id,weight) VALUES($1,'collection_add',$2,3)`,[req.user.id,req.params.restaurantId]);res.status(204).end();
  } catch(e){next(e);}
});
app.delete("/api/collections/:id/restaurants/:restaurantId", requireAuth, async (req,res,next) => {
  try { const access=await collectionAccess(req.user.id,req.params.id);if(!access || !['owner','editor'].includes(access.role))return res.status(403).json({error:"Anda tidak memiliki izin mengedit koleksi ini"});await pool.query(`DELETE FROM collection_restaurants WHERE collection_id=$1 AND restaurant_id=$2`,[req.params.id,req.params.restaurantId]);await pool.query(`UPDATE collections SET updated_at=NOW() WHERE id=$1`,[req.params.id]);res.status(204).end(); } catch(e){next(e);}
});
app.get("/api/collections/:id/members",requireAuth,async(req,res,next)=>{
  try{const access=await collectionAccess(req.user.id,req.params.id);if(!access||!access.role)return res.status(403).json({error:"Daftar kolaborator hanya tersedia untuk anggota collection"});const result=await pool.query(`SELECT u.id,u.name,u.username,u.avatar,cm.role FROM collection_members cm JOIN users u ON u.id=cm.user_id WHERE cm.collection_id=$1 ORDER BY cm.created_at`,[req.params.id]);res.json({data:result.rows});}catch(e){next(e);}
});
app.post("/api/collections/:id/members",requireAuth,async(req,res,next)=>{
  try{const access=await collectionAccess(req.user.id,req.params.id);if(!access||access.role!=='owner')return res.status(403).json({error:"Hanya owner yang dapat membagikan koleksi"});const input=z.object({userId:z.string().uuid(),role:z.enum(['editor','viewer']).default('editor')}).parse(req.body);if(input.userId===req.user.id)return res.status(400).json({error:"Owner sudah memiliki akses"});const target=await pool.query(`SELECT 1 FROM users WHERE id=$1`,[input.userId]);if(!target.rowCount)return res.status(404).json({error:"Foodie tidak ditemukan"});if(await pairBlocked(req.user.id,input.userId))return res.status(403).json({error:"Akun ini tidak dapat ditambahkan"});const previous=await pool.query(`SELECT role FROM collection_members WHERE collection_id=$1 AND user_id=$2`,[req.params.id,input.userId]);await pool.query(`INSERT INTO collection_members(collection_id,user_id,role) VALUES($1,$2,$3) ON CONFLICT(collection_id,user_id) DO UPDATE SET role=EXCLUDED.role`,[req.params.id,input.userId,input.role]);if(!previous.rowCount){const body=`${req.user.name} membagikan collection dengan Anda`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,body) VALUES($1,$2,'together',$3)`,[input.userId,req.user.id,body]);void pushIfEnabled(input.userId,'together',{title:'Shared Collection',body,type:'together'});}res.status(204).end();}catch(e){next(e);}
});
app.delete("/api/collections/:id/members/:userId",requireAuth,async(req,res,next)=>{
  try{const access=await collectionAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Koleksi tidak ditemukan"});if(access.role!=='owner'&&req.params.userId!==req.user.id)return res.status(403).json({error:"Tidak memiliki izin"});await pool.query(`DELETE FROM collection_members WHERE collection_id=$1 AND user_id=$2`,[req.params.id,req.params.userId]);res.status(204).end();}catch(e){next(e);}
});

// Fodd 6.4 — Together: dining plans, RSVP, voting, group chat & shared album
app.get("/api/together/plans",requireAuth,async(req,res,next)=>{try{res.json({data:await loadDiningPlans(req.user.id)});}catch(e){next(e);}});
app.get("/api/together/plans/:id",requireAuth,async(req,res,next)=>{try{const rows=await loadDiningPlans(req.user.id,req.params.id);if(!rows.length)return res.status(404).json({error:"Rencana makan tidak ditemukan"});res.json({data:rows[0]});}catch(e){next(e);}});
app.put("/api/together/plans/:id/live-activity",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});const {activityToken}=z.object({activityToken:z.string().regex(/^[a-fA-F0-9]{32,512}$/)}).parse(req.body);await pool.query(`DELETE FROM live_activity_tokens WHERE activity_token=$1 AND NOT (user_id=$2 AND plan_id=$3)`,[activityToken,req.user.id,req.params.id]);await pool.query(`INSERT INTO live_activity_tokens(activity_token,user_id,plan_id) VALUES($1,$2,$3) ON CONFLICT(user_id,plan_id) DO UPDATE SET activity_token=EXCLUDED.activity_token,updated_at=NOW()`,[activityToken,req.user.id,req.params.id]);void broadcastDiningLiveActivity(req.params.id,access.status==='planned'?'update':'end');res.status(204).end();}catch(e){next(e);}
});
app.delete("/api/together/plans/:id/live-activity",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});await pool.query(`DELETE FROM live_activity_tokens WHERE user_id=$1 AND plan_id=$2`,[req.user.id,req.params.id]);res.status(204).end();}catch(e){next(e);}
});
app.post("/api/together/plans",requireAuth,async(req,res,next)=>{
  const client=await pool.connect();
  try{
    const input=z.object({title:z.string().trim().min(1).max(100),note:z.string().trim().max(500).default(''),scheduledAt:z.string().datetime(),memberIds:z.array(z.string().uuid()).max(30).default([]),candidateRestaurantIds:z.array(z.string().min(1).max(240)).max(12).default([])}).parse(req.body);ensureSafeContent(`${input.title} ${input.note}`);
    const memberIds=[...new Set(input.memberIds.filter(id=>id!==req.user.id))];
    if(memberIds.length){const found=await pool.query(`SELECT id FROM users WHERE id=ANY($1::uuid[])`,[memberIds]);if(found.rowCount!==memberIds.length)return res.status(400).json({error:"Salah satu foodie tidak ditemukan"});}
    for(const id of memberIds){if(!(await hangoutInviteAllowed(req.user.id,id)))return res.status(403).json({error:"Salah satu foodie membatasi undangan nongkrong. Minta mereka mengubah Hangout Privacy atau tambahkan sebagai teman/Close Foodie."});}
    const candidateIds=[...new Set(input.candidateRestaurantIds)];
    if(candidateIds.length){const found=await pool.query(`SELECT id FROM restaurants WHERE id=ANY($1::text[])`,[candidateIds]);if(found.rowCount!==candidateIds.length)return res.status(400).json({error:"Salah satu kandidat restoran belum tersedia di Fodd"});}
    await client.query('BEGIN');const plan=(await client.query(`INSERT INTO dining_plans(host_id,title,note,scheduled_at) VALUES($1,$2,$3,$4) RETURNING id`,[req.user.id,input.title,input.note,input.scheduledAt])).rows[0];
    for(const id of memberIds)await client.query(`INSERT INTO dining_plan_members(plan_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[plan.id,id]);
    for(const restaurantId of candidateIds)await client.query(`INSERT INTO dining_plan_candidates(plan_id,restaurant_id,proposed_by) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`,[plan.id,restaurantId,req.user.id]);
    await client.query('COMMIT');for(const id of memberIds){const body=`${req.user.name} mengundang Anda makan bareng: ${input.title}`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,plan_id,body) VALUES($1,$2,'together',$3,$4)`,[id,req.user.id,plan.id,body]);void pushIfEnabled(id,'together',{title:'Makan Bareng',body,type:'together',planId:plan.id});}
    const rows=await loadDiningPlans(req.user.id,plan.id);res.status(201).json({data:rows[0]});
  }catch(e){await client.query('ROLLBACK').catch(()=>{});next(e);}finally{client.release();}
});
app.patch("/api/together/plans/:id",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana makan tidak ditemukan"});if(access.hostId!==req.user.id)return res.status(403).json({error:"Hanya host yang dapat mengubah rencana"});const input=z.object({title:z.string().trim().min(1).max(100).optional(),note:z.string().trim().max(500).optional(),scheduledAt:z.string().datetime().optional(),status:z.enum(['planned','completed','cancelled']).optional(),selectedRestaurantId:z.string().min(1).max(240).nullable().optional()}).parse(req.body);if(input.selectedRestaurantId){const candidate=await pool.query(`SELECT 1 FROM dining_plan_candidates WHERE plan_id=$1 AND restaurant_id=$2`,[req.params.id,input.selectedRestaurantId]);if(!candidate.rowCount)return res.status(400).json({error:"Restoran terpilih harus ada di voting"});}await pool.query(`UPDATE dining_plans SET title=COALESCE($1,title),note=COALESCE($2,note),scheduled_at=COALESCE($3,scheduled_at),status=COALESCE($4,status),selected_restaurant_id=CASE WHEN $5::text IS NULL THEN selected_restaurant_id ELSE NULLIF($5,'') END,updated_at=NOW() WHERE id=$6`,[input.title??null,input.note??null,input.scheduledAt??null,input.status??null,input.selectedRestaurantId===undefined?null:(input.selectedRestaurantId||''),req.params.id]);const rows=await loadDiningPlans(req.user.id,req.params.id);void broadcastDiningLiveActivity(req.params.id,input.status==='completed'||input.status==='cancelled'?'end':'update');res.json({data:rows[0]});}catch(e){next(e);}
});
app.post("/api/together/plans/:id/invite",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access||access.hostId!==req.user.id)return res.status(403).json({error:"Hanya host yang dapat mengundang"});if(access.status!=='planned')return res.status(409).json({error:"Rencana yang sudah selesai/dibatalkan tidak dapat menerima undangan baru"});const {memberIds}=z.object({memberIds:z.array(z.string().uuid()).min(1).max(30)}).parse(req.body);for(const id of [...new Set(memberIds)]){if(id===req.user.id||!(await hangoutInviteAllowed(req.user.id,id)))continue;const exists=await pool.query(`SELECT 1 FROM users WHERE id=$1`,[id]);if(!exists.rowCount)continue;const inserted=await pool.query(`INSERT INTO dining_plan_members(plan_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING user_id`,[req.params.id,id]);if(!inserted.rowCount)continue;const body=`${req.user.name} mengundang Anda ke rencana makan`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,plan_id,body) VALUES($1,$2,'together',$3,$4)`,[id,req.user.id,req.params.id,body]);void pushIfEnabled(id,'together',{title:'Makan Bareng',body,type:'together',planId:req.params.id});}res.status(204).end();}catch(e){next(e);}
});
app.delete("/api/together/plans/:id/members/:userId",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});if(access.hostId!==req.user.id&&req.params.userId!==req.user.id)return res.status(403).json({error:"Tidak memiliki izin"});if(req.params.userId===access.hostId)return res.status(400).json({error:"Host tidak dapat dikeluarkan"});await pool.query(`DELETE FROM dining_plan_members WHERE plan_id=$1 AND user_id=$2`,[req.params.id,req.params.userId]);void broadcastDiningLiveActivity(req.params.id);res.status(204).end();}catch(e){next(e);}});
app.post("/api/together/plans/:id/rsvp",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});if(access.hostId===req.user.id)return res.json({data:{rsvp:'going'}});const {rsvp}=z.object({rsvp:z.enum(['going','maybe','declined'])}).parse(req.body);await pool.query(`UPDATE dining_plan_members SET rsvp=$1,responded_at=NOW() WHERE plan_id=$2 AND user_id=$3`,[rsvp,req.params.id,req.user.id]);const body=`${req.user.name} menjawab ${rsvp} untuk rencana makan`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,plan_id,body) VALUES($1,$2,'together',$3,$4)`,[access.hostId,req.user.id,req.params.id,body]);void pushIfEnabled(access.hostId,'together',{title:'RSVP Makan Bareng',body,type:'together',planId:req.params.id});void broadcastDiningLiveActivity(req.params.id);res.json({data:{rsvp}});}catch(e){next(e);}});
app.put("/api/together/plans/:id/candidates/:restaurantId",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access||access.status!=='planned')return res.status(403).json({error:"Rencana tidak dapat diedit"});const restaurant=await pool.query(`SELECT 1 FROM restaurants WHERE id=$1`,[req.params.restaurantId]);if(!restaurant.rowCount)return res.status(404).json({error:"Restoran belum tersedia di Fodd"});await pool.query(`INSERT INTO dining_plan_candidates(plan_id,restaurant_id,proposed_by) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`,[req.params.id,req.params.restaurantId,req.user.id]);void broadcastDiningLiveActivity(req.params.id);res.status(204).end();}catch(e){next(e);}});
app.delete("/api/together/plans/:id/candidates/:restaurantId",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});if(access.status!=='planned')return res.status(409).json({error:"Voting sudah ditutup"});const candidate=await pool.query(`SELECT proposed_by FROM dining_plan_candidates WHERE plan_id=$1 AND restaurant_id=$2`,[req.params.id,req.params.restaurantId]);if(!candidate.rowCount)return res.status(204).end();if(access.hostId!==req.user.id&&candidate.rows[0].proposed_by!==req.user.id)return res.status(403).json({error:"Tidak memiliki izin"});await pool.query(`DELETE FROM dining_plan_candidates WHERE plan_id=$1 AND restaurant_id=$2`,[req.params.id,req.params.restaurantId]);void broadcastDiningLiveActivity(req.params.id);res.status(204).end();}catch(e){next(e);}});
app.put("/api/together/plans/:id/vote",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});if(access.status!=='planned')return res.status(409).json({error:"Voting sudah ditutup"});const {restaurantId}=z.object({restaurantId:z.string().min(1).max(240)}).parse(req.body);const exists=await pool.query(`SELECT 1 FROM dining_plan_candidates WHERE plan_id=$1 AND restaurant_id=$2`,[req.params.id,restaurantId]);if(!exists.rowCount)return res.status(404).json({error:"Kandidat restoran tidak ditemukan"});await pool.query(`INSERT INTO dining_plan_votes(plan_id,restaurant_id,user_id) VALUES($1,$2,$3) ON CONFLICT(plan_id,user_id) DO UPDATE SET restaurant_id=EXCLUDED.restaurant_id,created_at=NOW()`,[req.params.id,restaurantId,req.user.id]);void broadcastDiningLiveActivity(req.params.id);res.status(204).end();}catch(e){next(e);}});
app.get("/api/together/plans/:id/messages",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});const result=await pool.query(`SELECT dm.id,dm.body,dm.created_at AS "createdAt",u.id AS "userId",u.name,u.username,u.avatar FROM dining_plan_messages dm JOIN users u ON u.id=dm.sender_id WHERE dm.plan_id=$1 ORDER BY dm.created_at`,[req.params.id]);res.json({data:result.rows});}catch(e){next(e);}});
app.post("/api/together/plans/:id/messages",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});const {body}=z.object({body:z.string().trim().min(1).max(1000)}).parse(req.body);ensureSafeContent(body);const row=(await pool.query(`INSERT INTO dining_plan_messages(plan_id,sender_id,body) VALUES($1,$2,$3) RETURNING id,body,created_at AS "createdAt"`,[req.params.id,req.user.id,body])).rows[0];const recipients=await pool.query(`SELECT user_id FROM dining_plan_members WHERE plan_id=$1 AND user_id<>$2 UNION SELECT host_id FROM dining_plans WHERE id=$1 AND host_id<>$2`,[req.params.id,req.user.id]);for(const r of recipients.rows){void pushIfEnabled(r.user_id,'together',{title:`${req.user.name} • Makan Bareng`,body,type:'together',planId:req.params.id});}void broadcastDiningLiveActivity(req.params.id);res.status(201).json({data:{...row,userId:req.user.id,name:req.user.name,username:req.user.username,avatar:req.user.avatar}});}catch(e){next(e);}});
app.get("/api/together/plans/:id/photos",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});const result=await pool.query(`SELECT dp.id,dp.image,dp.caption,dp.created_at AS "createdAt",u.id AS "userId",u.name,u.username,u.avatar FROM dining_plan_photos dp JOIN users u ON u.id=dp.user_id WHERE dp.plan_id=$1 ORDER BY dp.created_at DESC LIMIT 100`,[req.params.id]);res.json({data:result.rows});}catch(e){next(e);}});
app.post("/api/together/plans/:id/photos",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});const input=z.object({image:z.string().min(20).max(7000000),caption:z.string().trim().max(240).default('')}).parse(req.body);ensureSafeContent(input.caption);const row=(await pool.query(`INSERT INTO dining_plan_photos(plan_id,user_id,image,caption) VALUES($1,$2,$3,$4) RETURNING id,image,caption,created_at AS "createdAt"`,[req.params.id,req.user.id,input.image,input.caption])).rows[0];res.status(201).json({data:{...row,userId:req.user.id,name:req.user.name,username:req.user.username,avatar:req.user.avatar}});}catch(e){next(e);}});
app.delete("/api/together/plans/:id/photos/:photoId",requireAuth,async(req,res,next)=>{try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});if(access.hostId===req.user.id)await pool.query(`DELETE FROM dining_plan_photos WHERE id=$1 AND plan_id=$2`,[req.params.photoId,req.params.id]);else await pool.query(`DELETE FROM dining_plan_photos WHERE id=$1 AND plan_id=$2 AND user_id=$3`,[req.params.photoId,req.params.id,req.user.id]);res.status(204).end();}catch(e){next(e);}});

app.post("/api/together/plans/:id/moment",requireAuth,async(req,res,next)=>{
  try{
    const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:"Rencana tidak ditemukan"});
    const input=z.object({caption:z.string().trim().min(1).max(500),image:z.string().max(7000000).default('')}).parse(req.body);ensureSafeContent(input.caption);
    const plan=(await pool.query(`SELECT p.title,p.selected_restaurant_id,r.name AS location_name,r.address AS location_address,r.latitude,r.longitude FROM dining_plans p LEFT JOIN restaurants r ON r.id=p.selected_restaurant_id WHERE p.id=$1`,[req.params.id])).rows[0];
    const people=await pool.query(`SELECT user_id FROM dining_plan_members WHERE plan_id=$1 UNION SELECT host_id AS user_id FROM dining_plans WHERE id=$1`,[req.params.id]);
    const tagged=[...new Set(people.rows.map(x=>x.user_id).filter(id=>id!==req.user.id))];
    const result=await pool.query(`INSERT INTO moments(author,caption,image,user_id,moment_type,location_name,location_address,latitude,longitude,visibility,tagged_user_ids,restaurant_id,plan_id) VALUES($1,$2,$3,$4,'photo',$5,$6,$7,$8,'selected',$9::uuid[],$10,$11) RETURNING id`,[req.user.name,input.caption,input.image,req.user.id,plan.location_name||plan.title,plan.location_address||'',plan.latitude??null,plan.longitude??null,tagged,plan.selected_restaurant_id??null,req.params.id]);
    for(const userId of tagged)await pool.query(`INSERT INTO moment_audience(moment_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[result.rows[0].id,userId]);
    const row=(await pool.query(`${momentSelect} WHERE m.id=$2`,[req.user.id,result.rows[0].id])).rows[0];res.status(201).json({data:row});
  }catch(e){next(e);}
});

app.post("/api/reports", reportRateLimit, requireAuth, async (req,res,next) => {
  try {
    const input=z.object({targetType:z.enum(['user','moment','comment']),targetId:z.string().uuid(),reason:z.enum(['spam','harassment','hate','sexual','violence','misinformation','other']),details:z.string().trim().max(1000).default("")}).parse(req.body);
    const table={user:'users',moment:'moments',comment:'comments'}[input.targetType];
    const exists=await pool.query(`SELECT id FROM ${table} WHERE id=$1`,[input.targetId]);if(!exists.rowCount)return res.status(404).json({error:"Konten tidak ditemukan"});
    if(input.targetType==='user' && input.targetId===req.user.id) return res.status(400).json({error:"Tidak dapat melaporkan akun sendiri"});
    await pool.query(`INSERT INTO reports(reporter_id,target_type,target_id,reason,details) VALUES($1,$2,$3,$4,$5) ON CONFLICT(reporter_id,target_type,target_id,reason) DO UPDATE SET details=EXCLUDED.details,status='open',created_at=NOW()`,[req.user.id,input.targetType,input.targetId,input.reason,input.details]);
    res.status(201).json({data:{message:"Laporan diterima. Tim Fodd akan meninjaunya.",devCode:null}});
  } catch(e){next(e);}
});

app.get("/api/places/:placeId/reviews", async (req,res,next) => {
  try { const result=await pool.query(`SELECT pr.id,pr.place_id AS "placeId",pr.rating,pr.body,pr.photo,pr.created_at AS "createdAt",u.id AS "userId",u.name,u.username,u.avatar FROM place_reviews pr JOIN users u ON u.id=pr.user_id WHERE pr.place_id=$1 ORDER BY pr.updated_at DESC`,[req.params.placeId]);res.json({data:result.rows}); }
  catch(e){next(e);}
});
app.post("/api/places/:placeId/reviews", requireAuth, async (req,res,next) => {
  try {
    const input=z.object({placeName:z.string().trim().min(1).max(200),address:z.string().max(500).default(""),latitude:z.coerce.number().min(-90).max(90),longitude:z.coerce.number().min(-180).max(180),rating:z.coerce.number().int().min(1).max(5),body:z.string().trim().min(1).max(1000),photo:z.string().max(7_000_000).default("")}).parse(req.body);
    ensureSafeContent(input.body);
    const result=await pool.query(`INSERT INTO place_reviews(place_id,place_name,address,latitude,longitude,user_id,rating,body,photo) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) ON CONFLICT(place_id,user_id) DO UPDATE SET place_name=EXCLUDED.place_name,address=EXCLUDED.address,latitude=EXCLUDED.latitude,longitude=EXCLUDED.longitude,rating=EXCLUDED.rating,body=EXCLUDED.body,photo=EXCLUDED.photo,updated_at=NOW() RETURNING id,place_id AS "placeId",rating,body,photo,created_at AS "createdAt"`,[req.params.placeId,input.placeName,input.address,input.latitude,input.longitude,req.user.id,input.rating,input.body,input.photo]);
    await pool.query(`INSERT INTO smart_events(user_id,event_type,restaurant_id,query,weight) VALUES($1,'review',(SELECT id FROM restaurants WHERE id=$2 LIMIT 1),$3,5)`,[req.user.id,req.params.placeId,input.placeName]);
    res.status(201).json({data:{...result.rows[0],userId:req.user.id,name:req.user.name,username:req.user.username,avatar:req.user.avatar}});
  } catch(e){next(e);}
});

// MARK: - Food Stories 24h
const canViewStory=`NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=s.user_id) OR (b.blocker_id=s.user_id AND b.blocked_id=$1)) AND (s.user_id=$1 OR ((EXISTS(SELECT 1 FROM users owner WHERE owner.id=s.user_id AND (owner.is_private=FALSE OR EXISTS(SELECT 1 FROM follows pf WHERE pf.follower_id=$1 AND pf.following_id=s.user_id)))) AND (s.visibility='everyone' OR (s.visibility='friends' AND EXISTS(SELECT 1 FROM follows f1 WHERE f1.follower_id=$1 AND f1.following_id=s.user_id) AND EXISTS(SELECT 1 FROM follows f2 WHERE f2.follower_id=s.user_id AND f2.following_id=$1)) OR (s.visibility='close_foodies' AND EXISTS(SELECT 1 FROM close_foodies cf WHERE cf.user_id=s.user_id AND cf.member_id=$1)) OR (s.visibility='selected' AND EXISTS(SELECT 1 FROM story_audience sa WHERE sa.story_id=s.id AND sa.user_id=$1)))))`;
const storySelect=`SELECT s.id,s.media_type AS "mediaType",s.media,s.caption,s.location_name AS "locationName",s.location_address AS "locationAddress",s.latitude,s.longitude,s.visibility,s.created_at AS "createdAt",s.expires_at AS "expiresAt",s.poll_question AS "pollQuestion",s.poll_option_a AS "pollOptionA",s.poll_option_b AS "pollOptionB",u.id AS "userId",u.name,u.username,u.avatar,u.creator_verified AS "creatorVerified",ARRAY(SELECT tu.name FROM users tu WHERE tu.id=ANY(s.tagged_user_ids)) AS "taggedNames",(SELECT COUNT(*)::int FROM story_views sv WHERE sv.story_id=s.id) AS "viewCount",(s.user_id=$1 OR EXISTS(SELECT 1 FROM story_views sv WHERE sv.story_id=s.id AND sv.user_id=$1)) AS "seenByMe",jsonb_build_object('love',(SELECT COUNT(*)::int FROM story_reactions sr WHERE sr.story_id=s.id AND sr.reaction='love'),'yummy',(SELECT COUNT(*)::int FROM story_reactions sr WHERE sr.story_id=s.id AND sr.reaction='yummy'),'fire',(SELECT COUNT(*)::int FROM story_reactions sr WHERE sr.story_id=s.id AND sr.reaction='fire'),'wow',(SELECT COUNT(*)::int FROM story_reactions sr WHERE sr.story_id=s.id AND sr.reaction='wow')) AS reactions,(SELECT reaction FROM story_reactions sr WHERE sr.story_id=s.id AND sr.user_id=$1) AS "myReaction",jsonb_build_object('a',(SELECT COUNT(*)::int FROM story_poll_votes pv WHERE pv.story_id=s.id AND pv.option_key='a'),'b',(SELECT COUNT(*)::int FROM story_poll_votes pv WHERE pv.story_id=s.id AND pv.option_key='b')) AS "pollVotes",(SELECT option_key FROM story_poll_votes pv WHERE pv.story_id=s.id AND pv.user_id=$1) AS "myPollVote" FROM stories s JOIN users u ON u.id=s.user_id`;
async function visibleActiveStory(userId,storyId){const result=await pool.query(`SELECT s.user_id FROM stories s WHERE s.id=$2 AND s.expires_at>NOW() AND ${canViewStory}`,[userId,storyId]);return result.rows[0]||null;}

app.get("/api/stories",requireAuth,async(req,res,next)=>{try{const result=await pool.query(`${storySelect} WHERE s.expires_at>NOW() AND ${canViewStory} ORDER BY s.created_at ASC LIMIT 80`,[req.user.id]);res.json({data:result.rows});}catch(e){next(e);}});
app.get("/api/stories/archive",requireAuth,async(req,res,next)=>{try{const result=await pool.query(`${storySelect} WHERE s.user_id=$1 ORDER BY s.created_at DESC LIMIT 60`,[req.user.id]);res.json({data:result.rows});}catch(e){next(e);}});
app.post("/api/stories",requireAuth,async(req,res,next)=>{try{
  const input=z.object({media:z.string().max(7_000_000).default(''),caption:z.string().trim().max(500).default(''),locationName:z.string().trim().max(160).default(''),locationAddress:z.string().trim().max(300).default(''),latitude:z.number().finite().nullable().optional(),longitude:z.number().finite().nullable().optional(),visibility:z.enum(['everyone','friends','close_foodies','selected','only_me']).default('everyone'),taggedUserIds:z.array(z.string().uuid()).max(20).default([]),selectedUserIds:z.array(z.string().uuid()).max(50).default([]),pollQuestion:z.string().trim().max(120).default(''),pollOptionA:z.string().trim().max(50).default(''),pollOptionB:z.string().trim().max(50).default('')}).parse(req.body);
  if(!input.media && !input.caption && !input.pollQuestion)return res.status(400).json({error:'Tambahkan foto, teks, atau polling untuk Story'});
  if(input.pollQuestion && (!input.pollOptionA || !input.pollOptionB))return res.status(400).json({error:'Polling membutuhkan dua pilihan jawaban'});
  if(input.visibility==='selected'&&input.selectedUserIds.length===0)return res.status(400).json({error:'Pilih minimal satu teman untuk audience terpilih'});
  ensureSafeContent(input.caption);ensureSafeContent(input.pollQuestion);ensureSafeContent(input.pollOptionA);ensureSafeContent(input.pollOptionB);const mediaType=input.media?'photo':'text';
  const result=await pool.query(`INSERT INTO stories(user_id,media_type,media,caption,location_name,location_address,latitude,longitude,visibility,tagged_user_ids,poll_question,poll_option_a,poll_option_b) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10::uuid[],$11,$12,$13) RETURNING id,media_type AS "mediaType",media,caption,location_name AS "locationName",location_address AS "locationAddress",latitude,longitude,visibility,created_at AS "createdAt",expires_at AS "expiresAt",poll_question AS "pollQuestion",poll_option_a AS "pollOptionA",poll_option_b AS "pollOptionB"`,[req.user.id,mediaType,input.media,input.caption,input.locationName,input.locationAddress,input.latitude??null,input.longitude??null,input.visibility,input.taggedUserIds,input.pollQuestion,input.pollOptionA,input.pollOptionB]);
  if(input.visibility==='selected')for(const userId of input.selectedUserIds)await pool.query(`INSERT INTO story_audience(story_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[result.rows[0].id,userId]);
  const taggedNames=input.taggedUserIds.length?(await pool.query(`SELECT name FROM users WHERE id=ANY($1::uuid[])`,[input.taggedUserIds])).rows.map(x=>x.name):[];
  res.status(201).json({data:{...result.rows[0],userId:req.user.id,name:req.user.name,username:req.user.username,avatar:req.user.avatar,creatorVerified:Boolean(req.user.creator_verified),taggedNames,viewCount:0,seenByMe:true,reactions:{love:0,yummy:0,fire:0,wow:0},myReaction:null,pollVotes:{a:0,b:0},myPollVote:null}});
}catch(e){next(e);}});
app.put("/api/stories/:id/view",requireAuth,async(req,res,next)=>{try{const story=await visibleActiveStory(req.user.id,req.params.id);if(!story)return res.status(404).json({error:'Story tidak ditemukan atau sudah kedaluwarsa'});if(story.user_id!==req.user.id)await pool.query(`INSERT INTO story_views(story_id,user_id) VALUES($1,$2) ON CONFLICT(story_id,user_id) DO UPDATE SET viewed_at=NOW()`,[req.params.id,req.user.id]);res.status(204).end();}catch(e){next(e);}});
app.put("/api/stories/:id/reaction",requireAuth,async(req,res,next)=>{try{const {reaction}=z.object({reaction:z.enum(['love','yummy','fire','wow'])}).parse(req.body);const story=await visibleActiveStory(req.user.id,req.params.id);if(!story)return res.status(404).json({error:'Story tidak ditemukan atau sudah kedaluwarsa'});const previous=await pool.query(`SELECT reaction FROM story_reactions WHERE story_id=$1 AND user_id=$2`,[req.params.id,req.user.id]);await pool.query(`INSERT INTO story_reactions(story_id,user_id,reaction) VALUES($1,$2,$3) ON CONFLICT(story_id,user_id) DO UPDATE SET reaction=EXCLUDED.reaction,created_at=NOW()`,[req.params.id,req.user.id,reaction]);if(!previous.rowCount&&story.user_id!==req.user.id){const body=`${req.user.name} bereaksi pada Food Story Anda`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,body) VALUES($1,$2,'like',$3)`,[story.user_id,req.user.id,body]);void pushIfEnabled(story.user_id,'like',{title:'Reaksi Story baru',body,type:'like'});}res.status(204).end();}catch(e){next(e);}});
app.delete("/api/stories/:id/reaction",requireAuth,async(req,res,next)=>{try{const story=await visibleActiveStory(req.user.id,req.params.id);if(!story)return res.status(404).json({error:'Story tidak ditemukan atau sudah kedaluwarsa'});await pool.query(`DELETE FROM story_reactions WHERE story_id=$1 AND user_id=$2`,[req.params.id,req.user.id]);res.status(204).end();}catch(e){next(e);}});
app.get("/api/stories/:id/viewers",requireAuth,async(req,res,next)=>{try{const owner=await pool.query(`SELECT 1 FROM stories WHERE id=$1 AND user_id=$2`,[req.params.id,req.user.id]);if(!owner.rowCount)return res.status(403).json({error:'Hanya pemilik Story yang dapat melihat viewers'});const result=await pool.query(`SELECT u.id,u.name,u.username,u.avatar,sv.viewed_at AS "viewedAt",sr.reaction FROM story_views sv JOIN users u ON u.id=sv.user_id LEFT JOIN story_reactions sr ON sr.story_id=sv.story_id AND sr.user_id=sv.user_id WHERE sv.story_id=$1 ORDER BY sv.viewed_at DESC`,[req.params.id]);res.json({data:result.rows});}catch(e){next(e);}});
app.post("/api/stories/:id/reply",requireAuth,async(req,res,next)=>{try{const {body}=z.object({body:z.string().trim().min(1).max(500)}).parse(req.body);ensureSafeContent(body);const story=await visibleActiveStory(req.user.id,req.params.id);if(!story)return res.status(404).json({error:'Story tidak ditemukan atau sudah kedaluwarsa'});if(story.user_id===req.user.id)return res.status(400).json({error:'Anda tidak dapat membalas Story sendiri'});if(await pairBlocked(req.user.id,story.user_id))return res.status(403).json({error:'Pesan tidak dapat dikirim ke akun ini'});const text=`Membalas Food Story: ${body}`;const row=(await pool.query(`INSERT INTO messages(sender_id,receiver_id,body) VALUES($1,$2,$3) RETURNING id,sender_id AS "senderId",receiver_id AS "receiverId",body,is_read AS "isRead",created_at AS "createdAt"`,[req.user.id,story.user_id,text])).rows[0];const notificationBody=`${req.user.name} membalas Food Story Anda`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,body) VALUES($1,$2,'message',$3)`,[story.user_id,req.user.id,notificationBody]);void pushIfEnabled(story.user_id,'message',{title:req.user.name,body:notificationBody,type:'message'});res.status(201).json({data:row});}catch(e){next(e);}});
app.put("/api/stories/:id/poll",requireAuth,async(req,res,next)=>{try{const {option}=z.object({option:z.enum(['a','b'])}).parse(req.body);const story=await visibleActiveStory(req.user.id,req.params.id);if(!story)return res.status(404).json({error:'Story tidak ditemukan atau sudah kedaluwarsa'});const poll=await pool.query(`SELECT poll_question,poll_option_a,poll_option_b FROM stories WHERE id=$1`,[req.params.id]);if(!poll.rows[0]?.poll_question)return res.status(400).json({error:'Story ini tidak memiliki polling'});await pool.query(`INSERT INTO story_poll_votes(story_id,user_id,option_key) VALUES($1,$2,$3) ON CONFLICT(story_id,user_id) DO UPDATE SET option_key=EXCLUDED.option_key,created_at=NOW()`,[req.params.id,req.user.id,option]);const counts=await pool.query(`SELECT COUNT(*) FILTER(WHERE option_key='a')::int AS a,COUNT(*) FILTER(WHERE option_key='b')::int AS b FROM story_poll_votes WHERE story_id=$1`,[req.params.id]);res.json({data:{pollVotes:counts.rows[0],myPollVote:option}});}catch(e){next(e);}});

app.get("/api/highlights/user/:userId",requireAuth,async(req,res,next)=>{try{if(await pairBlocked(req.user.id,req.params.userId))return res.json({data:[]});const user=await pool.query(`SELECT is_private FROM users WHERE id=$1`,[req.params.userId]);if(!user.rowCount)return res.status(404).json({error:'User tidak ditemukan'});if(req.params.userId!==req.user.id&&user.rows[0].is_private){const follows=await pool.query(`SELECT 1 FROM follows WHERE follower_id=$1 AND following_id=$2`,[req.user.id,req.params.userId]);if(!follows.rowCount)return res.json({data:[]});}const base=await pool.query(`SELECT id,title,created_at AS "createdAt" FROM story_highlights WHERE user_id=$1 ORDER BY updated_at DESC LIMIT 30`,[req.params.userId]);const data=[];for(const h of base.rows){const visible=await pool.query(`${storySelect} JOIN story_highlight_items hi ON hi.story_id=s.id WHERE hi.highlight_id=$2 AND ${canViewStory} ORDER BY hi.sort_order,hi.created_at`,[req.user.id,h.id]);if(req.params.userId===req.user.id||visible.rowCount){data.push({...h,storyCount:visible.rowCount,cover:visible.rows.find(x=>x.media)?.media||''});}}res.json({data});}catch(e){next(e);}});
app.get("/api/highlights/:id/stories",requireAuth,async(req,res,next)=>{try{const owner=await pool.query(`SELECT user_id FROM story_highlights WHERE id=$1`,[req.params.id]);if(!owner.rowCount)return res.status(404).json({error:'Highlight tidak ditemukan'});if(await pairBlocked(req.user.id,owner.rows[0].user_id))return res.json({data:[]});const result=await pool.query(`${storySelect} JOIN story_highlight_items hi ON hi.story_id=s.id WHERE hi.highlight_id=$2 AND ${canViewStory} ORDER BY hi.sort_order,hi.created_at`,[req.user.id,req.params.id]);res.json({data:result.rows});}catch(e){next(e);}});
app.post("/api/highlights",requireAuth,async(req,res,next)=>{try{const {title}=z.object({title:z.string().trim().min(1).max(40)}).parse(req.body);ensureSafeContent(title);const row=(await pool.query(`INSERT INTO story_highlights(user_id,title) VALUES($1,$2) RETURNING id,title,created_at AS "createdAt",0::int AS "storyCount",''::text AS cover`,[req.user.id,title])).rows[0];res.status(201).json({data:row});}catch(e){next(e);}});
app.post("/api/highlights/:id/stories",requireAuth,async(req,res,next)=>{try{const {storyId}=z.object({storyId:z.string().uuid()}).parse(req.body);const own=await pool.query(`SELECT 1 FROM story_highlights WHERE id=$1 AND user_id=$2`,[req.params.id,req.user.id]);if(!own.rowCount)return res.status(403).json({error:'Highlight bukan milik Anda'});const story=await pool.query(`SELECT 1 FROM stories WHERE id=$1 AND user_id=$2`,[storyId,req.user.id]);if(!story.rowCount)return res.status(403).json({error:'Hanya Story Anda yang dapat dimasukkan ke Highlight'});await pool.query(`INSERT INTO story_highlight_items(highlight_id,story_id,sort_order) VALUES($1,$2,(SELECT COALESCE(MAX(sort_order),-1)+1 FROM story_highlight_items WHERE highlight_id=$1)) ON CONFLICT DO NOTHING`,[req.params.id,storyId]);await pool.query(`UPDATE story_highlights SET updated_at=NOW() WHERE id=$1`,[req.params.id]);res.status(204).end();}catch(e){next(e);}});
app.delete("/api/highlights/:id",requireAuth,async(req,res,next)=>{try{const result=await pool.query(`DELETE FROM story_highlights WHERE id=$1 AND user_id=$2 RETURNING id`,[req.params.id,req.user.id]);if(!result.rowCount)return res.status(404).json({error:'Highlight tidak ditemukan'});res.status(204).end();}catch(e){next(e);}});

app.delete("/api/stories/:id",requireAuth,async(req,res,next)=>{try{const result=await pool.query(`DELETE FROM stories WHERE id=$1 AND user_id=$2 RETURNING id`,[req.params.id,req.user.id]);if(!result.rowCount)return res.status(404).json({error:'Story tidak ditemukan'});res.status(204).end();}catch(e){next(e);}});

const canViewMoment=`NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=m.user_id) OR (b.blocker_id=m.user_id AND b.blocked_id=$1)) AND (m.user_id=$1 OR ((EXISTS(SELECT 1 FROM users owner WHERE owner.id=m.user_id AND (owner.is_private=FALSE OR EXISTS(SELECT 1 FROM follows pf WHERE pf.follower_id=$1 AND pf.following_id=m.user_id)))) AND (m.visibility='everyone' OR (m.visibility='friends' AND EXISTS(SELECT 1 FROM follows f1 WHERE f1.follower_id=$1 AND f1.following_id=m.user_id) AND EXISTS(SELECT 1 FROM follows f2 WHERE f2.follower_id=m.user_id AND f2.following_id=$1)) OR (m.visibility='close_foodies' AND EXISTS(SELECT 1 FROM close_foodies cf WHERE cf.user_id=m.user_id AND cf.member_id=$1)) OR (m.visibility='selected' AND EXISTS(SELECT 1 FROM moment_audience ma WHERE ma.moment_id=m.id AND ma.user_id=$1)))))`;
async function visibleMomentOwner(userId,momentId) {
  const result=await pool.query(`SELECT m.user_id FROM moments m WHERE m.id=$2 AND ${canViewMoment}`,[userId,momentId]);
  return result.rows[0] || null;
}
const momentSelect=`SELECT m.id,m.caption,m.image,m.moment_type AS "momentType",m.location_name AS "locationName",m.location_address AS "locationAddress",m.latitude,m.longitude,m.visibility,m.created_at AS "createdAt",u.id AS "userId",u.name,u.username,u.avatar,u.creator_verified AS "creatorVerified",ARRAY(SELECT tu.name FROM users tu WHERE tu.id=ANY(m.tagged_user_ids)) AS "taggedNames",(SELECT COUNT(*)::int FROM moment_likes ml WHERE ml.moment_id=m.id) AS likes,EXISTS(SELECT 1 FROM moment_likes ml WHERE ml.moment_id=m.id AND ml.user_id=$1) AS "isLiked",(SELECT COUNT(*)::int FROM comments c WHERE c.moment_id=m.id) AS "commentCount",jsonb_build_object('love',(SELECT COUNT(*)::int FROM moment_reactions mr WHERE mr.moment_id=m.id AND mr.reaction='love'),'yummy',(SELECT COUNT(*)::int FROM moment_reactions mr WHERE mr.moment_id=m.id AND mr.reaction='yummy'),'fire',(SELECT COUNT(*)::int FROM moment_reactions mr WHERE mr.moment_id=m.id AND mr.reaction='fire'),'wow',(SELECT COUNT(*)::int FROM moment_reactions mr WHERE mr.moment_id=m.id AND mr.reaction='wow')) AS reactions,(SELECT reaction FROM moment_reactions mr WHERE mr.moment_id=m.id AND mr.user_id=$1) AS "myReaction" FROM moments m JOIN users u ON u.id=m.user_id`;
app.get("/api/moments", requireAuth, async (req,res,next) => { try{const result=await pool.query(`${momentSelect} WHERE ${canViewMoment} ORDER BY m.created_at DESC LIMIT 100`,[req.user.id]);res.json({data:result.rows});}catch(e){next(e);} });
app.post("/api/moments", requireAuth, async (req,res,next) => {
  try {
    const input=z.object({caption:z.string().trim().min(1).max(500),image:z.string().max(7_000_000).default(""),momentType:z.enum(['photo','checkin','eating','cooking','craving','thought']).default('photo'),locationName:z.string().trim().max(160).default(""),locationAddress:z.string().trim().max(300).default(""),latitude:z.number().finite().nullable().optional(),longitude:z.number().finite().nullable().optional(),visibility:z.enum(['everyone','friends','close_foodies','selected','only_me']).default('everyone'),taggedUserIds:z.array(z.string().uuid()).max(20).default([]),selectedUserIds:z.array(z.string().uuid()).max(50).default([])}).parse(req.body);
    if(input.visibility==='selected' && input.selectedUserIds.length===0) return res.status(400).json({error:"Pilih minimal satu teman untuk audience terpilih"});
    ensureSafeContent(input.caption);
    const result=await pool.query(`INSERT INTO moments(author,caption,image,user_id,moment_type,location_name,location_address,latitude,longitude,visibility,tagged_user_ids) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11::uuid[]) RETURNING id,caption,image,moment_type AS "momentType",location_name AS "locationName",location_address AS "locationAddress",latitude,longitude,visibility,created_at AS "createdAt"`,[req.user.name,input.caption,input.image,req.user.id,input.momentType,input.locationName,input.locationAddress,input.latitude??null,input.longitude??null,input.visibility,input.taggedUserIds]);
    if(input.visibility==='selected') for(const userId of input.selectedUserIds) await pool.query(`INSERT INTO moment_audience(moment_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[result.rows[0].id,userId]);
    if(input.momentType==='checkin' && input.locationName) await pool.query(`INSERT INTO smart_events(user_id,event_type,query,weight) VALUES($1,'checkin',$2,4)`,[req.user.id,input.locationName]);
    const taggedNames=input.taggedUserIds.length ? (await pool.query(`SELECT name FROM users WHERE id=ANY($1::uuid[])`,[input.taggedUserIds])).rows.map(x=>x.name) : [];
    res.status(201).json({data:{...result.rows[0],userId:req.user.id,name:req.user.name,username:req.user.username,avatar:req.user.avatar,creatorVerified:Boolean(req.user.creator_verified),taggedNames,likes:0,isLiked:false,commentCount:0,reactions:{love:0,yummy:0,fire:0,wow:0},myReaction:null}});
  } catch(e){next(e);}
});
app.put("/api/moments/:id/like", requireAuth, async (req,res,next) => {
  try {
    const m=await visibleMomentOwner(req.user.id,req.params.id);if(!m) return res.status(404).json({error:"Momen tidak ditemukan"});
    const inserted=await pool.query(`INSERT INTO moment_likes(moment_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING RETURNING moment_id`,[req.params.id,req.user.id]);
    if(inserted.rowCount&&m.user_id!==req.user.id){const body=`${req.user.name} menyukai momen Anda`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,moment_id,body) VALUES($1,$2,'like',$3,$4)`,[m.user_id,req.user.id,req.params.id,body]);void pushIfEnabled(m.user_id,"like",{title:"Momen disukai",body,type:"like"});}
    res.status(204).end();
  } catch(e){next(e);}
});
app.delete("/api/moments/:id/like", requireAuth, async (req,res,next) => {
  try { const m=await visibleMomentOwner(req.user.id,req.params.id);if(!m) return res.status(404).json({error:"Momen tidak ditemukan"});await pool.query(`DELETE FROM moment_likes WHERE moment_id=$1 AND user_id=$2`,[req.params.id,req.user.id]);res.status(204).end(); }
  catch(e){next(e);}
});
app.put("/api/moments/:id/reaction", requireAuth, async (req,res,next) => {
  try {
    const {reaction}=z.object({reaction:z.enum(['love','yummy','fire','wow'])}).parse(req.body);
    const m=await visibleMomentOwner(req.user.id,req.params.id);if(!m) return res.status(404).json({error:"Momen tidak ditemukan"});
    const previous=await pool.query(`SELECT reaction FROM moment_reactions WHERE moment_id=$1 AND user_id=$2`,[req.params.id,req.user.id]);
    if(previous.rows[0]?.reaction===reaction) return res.status(204).end();
    await pool.query(`INSERT INTO moment_reactions(moment_id,user_id,reaction) VALUES($1,$2,$3) ON CONFLICT(moment_id,user_id) DO UPDATE SET reaction=EXCLUDED.reaction,created_at=NOW()`,[req.params.id,req.user.id,reaction]);
    if(!previous.rowCount&&m.user_id!==req.user.id){const body=`${req.user.name} bereaksi pada momen Anda`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,moment_id,body) VALUES($1,$2,'like',$3,$4)`,[m.user_id,req.user.id,req.params.id,body]);void pushIfEnabled(m.user_id,"like",{title:"Reaksi baru",body,type:"like"});}
    res.status(204).end();
  } catch(e){next(e);}
});
app.delete("/api/moments/:id/reaction", requireAuth, async (req,res,next) => {
  try { const m=await visibleMomentOwner(req.user.id,req.params.id);if(!m) return res.status(404).json({error:"Momen tidak ditemukan"});await pool.query(`DELETE FROM moment_reactions WHERE moment_id=$1 AND user_id=$2`,[req.params.id,req.user.id]);res.status(204).end(); }
  catch(e){next(e);}
});
app.get("/api/moments/:id/comments", requireAuth, async (req,res,next) => {
  try { const m=await visibleMomentOwner(req.user.id,req.params.id);if(!m) return res.status(404).json({error:"Momen tidak ditemukan"});const result=await pool.query(`SELECT c.id,c.body,c.created_at AS "createdAt",u.id AS "userId",u.name,u.username,u.avatar FROM comments c JOIN users u ON u.id=c.user_id WHERE c.moment_id=$1 AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$2 AND b.blocked_id=u.id) OR (b.blocker_id=u.id AND b.blocked_id=$2)) ORDER BY c.created_at`,[req.params.id,req.user.id]);res.json({data:result.rows}); }
  catch(e){next(e);}
});
app.post("/api/moments/:id/comments", requireAuth, async (req,res,next) => {
  try {
    const {body}=z.object({body:z.string().trim().min(1).max(500)}).parse(req.body);
    ensureSafeContent(body);
    const m=await visibleMomentOwner(req.user.id,req.params.id);if(!m) return res.status(404).json({error:"Momen tidak ditemukan"});
    const result=await pool.query(`INSERT INTO comments(moment_id,user_id,body) VALUES($1,$2,$3) RETURNING id,body,created_at AS "createdAt"`,[req.params.id,req.user.id,body]);
    if(m.user_id!==req.user.id){const notificationBody=`${req.user.name} mengomentari momen Anda`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,moment_id,body) VALUES($1,$2,'comment',$3,$4)`,[m.user_id,req.user.id,req.params.id,notificationBody]);void pushIfEnabled(m.user_id,"comment",{title:"Komentar baru",body:notificationBody,type:"comment"});}
    res.status(201).json({data:{...result.rows[0],userId:req.user.id,name:req.user.name,username:req.user.username,avatar:req.user.avatar}});
  } catch(e){next(e);}
});
app.get("/api/users/:id/moments", requireAuth, async (req,res,next) => { try{const result=await pool.query(`${momentSelect} WHERE m.user_id=$2 AND ${canViewMoment} ORDER BY m.created_at DESC`,[req.user.id,req.params.id]);res.json({data:result.rows});}catch(e){next(e);} });

app.get("/api/notifications", requireAuth, async (req,res,next) => {
  try { const result=await pool.query(`SELECT n.id,n.type,n.body,n.is_read AS "isRead",n.created_at AS "createdAt",n.plan_id AS "planId",COALESCE(u.name,'Fodd') AS "actorName" FROM notifications n LEFT JOIN users u ON u.id=n.actor_id WHERE n.user_id=$1 AND (n.actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=n.actor_id) OR (b.blocker_id=n.actor_id AND b.blocked_id=$1))) ORDER BY n.created_at DESC LIMIT 100`,[req.user.id]);if(String(req.query.markRead)==="true") await pool.query(`UPDATE notifications SET is_read=true WHERE user_id=$1`,[req.user.id]);res.json({data:result.rows}); }
  catch(e){next(e);}
});
app.post("/api/notifications/read", requireAuth, async (req,res,next) => { try{await pool.query(`UPDATE notifications SET is_read=true WHERE user_id=$1`,[req.user.id]);res.status(204).end();}catch(e){next(e);} });
app.get("/api/unread", requireAuth, async (req,res,next) => {
  try { const result=await pool.query(`SELECT (SELECT COUNT(*)::int FROM messages m WHERE receiver_id=$1 AND is_read=false AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=m.sender_id) OR (b.blocker_id=m.sender_id AND b.blocked_id=$1))) AS messages,(SELECT COUNT(*)::int FROM notifications n WHERE user_id=$1 AND is_read=false AND (n.actor_id IS NULL OR NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=n.actor_id) OR (b.blocker_id=n.actor_id AND b.blocked_id=$1)))) AS notifications`,[req.user.id]);res.json({data:result.rows[0]}); }
  catch(e){next(e);}
});

app.get("/api/conversations", requireAuth, async (req,res,next) => {
  try {
    const result=await pool.query(`WITH ranked AS (SELECT m.*,CASE WHEN m.sender_id=$1 THEN m.receiver_id ELSE m.sender_id END AS other_id,ROW_NUMBER() OVER(PARTITION BY CASE WHEN m.sender_id=$1 THEN m.receiver_id ELSE m.sender_id END ORDER BY m.created_at DESC) AS rn FROM messages m WHERE m.sender_id=$1 OR m.receiver_id=$1)
      SELECT json_build_object('id',u.id,'name',u.name,'username',u.username,'bio',u.bio,'avatar',u.avatar,'isPrivate',u.is_private,'followersCount',(SELECT COUNT(*)::int FROM follows WHERE following_id=u.id),'followingCount',(SELECT COUNT(*)::int FROM follows WHERE follower_id=u.id),'isFollowing',EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id),'isCloseFoodie',EXISTS(SELECT 1 FROM close_foodies cf WHERE cf.user_id=$1 AND cf.member_id=u.id),'followRequestPending',EXISTS(SELECT 1 FROM follow_requests fr WHERE fr.requester_id=$1 AND fr.target_id=u.id),'isBlocked',false) AS member,
      r.body AS "lastMessage",r.created_at AS "lastMessageAt",(SELECT COUNT(*)::int FROM messages um WHERE um.sender_id=u.id AND um.receiver_id=$1 AND um.is_read=false) AS "unreadCount"
      FROM ranked r JOIN users u ON u.id=r.other_id WHERE r.rn=1 AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=u.id) OR (b.blocker_id=u.id AND b.blocked_id=$1)) ORDER BY r.created_at DESC`,[req.user.id]);
    res.json({data:result.rows});
  } catch(e){next(e);}
});
app.get("/api/messages/:userId", requireAuth, async (req,res,next) => {
  try { if(await pairBlocked(req.user.id,req.params.userId)) return res.status(403).json({error:"Percakapan tidak tersedia"});await pool.query(`UPDATE messages SET is_read=true WHERE sender_id=$1 AND receiver_id=$2 AND is_read=false`,[req.params.userId,req.user.id]);const result=await pool.query(`SELECT id,sender_id AS "senderId",receiver_id AS "receiverId",body,is_read AS "isRead",created_at AS "createdAt" FROM messages WHERE (sender_id=$1 AND receiver_id=$2) OR (sender_id=$2 AND receiver_id=$1) ORDER BY created_at`,[req.user.id,req.params.userId]);res.json({data:result.rows}); }
  catch(e){next(e);}
});
app.post("/api/messages/:userId", requireAuth, async (req,res,next) => {
  try { if(await pairBlocked(req.user.id,req.params.userId)) return res.status(403).json({error:"Pesan tidak dapat dikirim ke akun ini"});const {body}=z.object({body:z.string().trim().min(1).max(1000)}).parse(req.body);ensureSafeContent(body);const result=await pool.query(`INSERT INTO messages(sender_id,receiver_id,body) VALUES($1,$2,$3) RETURNING id,sender_id AS "senderId",receiver_id AS "receiverId",body,is_read AS "isRead",created_at AS "createdAt"`,[req.user.id,req.params.userId,body]);const notificationBody=`${req.user.name} mengirim pesan baru`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,body) VALUES($1,$2,'message',$3)`,[req.params.userId,req.user.id,notificationBody]);void pushIfEnabled(req.params.userId,"message",{title:req.user.name,body,type:"message"});res.status(201).json({data:result.rows[0]}); }
  catch(e){next(e);}
});

app.get("/api/search", requireAuth, async (req,res,next) => {
  try {
    const raw=String(req.query.q||"").trim();const q=raw.startsWith("#")?raw.slice(1):raw;if(q) await pool.query(`INSERT INTO smart_events(user_id,event_type,query,weight) VALUES($1,'search',$2,1)`,[req.user.id,q]);
    const [members,restaurants,moments]=await Promise.all([
      pool.query(`SELECT ${publicUserSQL},EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id) AS "isFollowing",EXISTS(SELECT 1 FROM close_foodies cf WHERE cf.user_id=$1 AND cf.member_id=u.id) AS "isCloseFoodie",EXISTS(SELECT 1 FROM follow_requests fr WHERE fr.requester_id=$1 AND fr.target_id=u.id) AS "followRequestPending",EXISTS(SELECT 1 FROM blocks b WHERE b.blocker_id=$1 AND b.blocked_id=u.id) AS "isBlocked" FROM users u WHERE u.id<>$1 AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=u.id AND b.blocked_id=$1) OR (b.blocker_id=$1 AND b.blocked_id=u.id)) AND (u.name ILIKE '%'||$2||'%' OR u.username ILIKE '%'||$2||'%' OR u.bio ILIKE '%'||$2||'%') ORDER BY u.name LIMIT 30`,[req.user.id,q]),
      pool.query(`SELECT ${restaurantSQL},EXISTS(SELECT 1 FROM saved_restaurants sr WHERE sr.user_id=$1 AND sr.restaurant_id=r.id) AS "isSaved" FROM restaurants r WHERE r.name ILIKE '%'||$2||'%' OR r.category ILIKE '%'||$2||'%' OR r.menu ILIKE '%'||$2||'%' OR r.address ILIKE '%'||$2||'%' ORDER BY r.rating DESC LIMIT 30`,[req.user.id,q]),
      pool.query(`${momentSelect} WHERE ${canViewMoment} AND (m.caption ILIKE '%'||$2||'%' OR m.location_name ILIKE '%'||$2||'%' OR u.name ILIKE '%'||$2||'%' OR u.username ILIKE '%'||$2||'%') ORDER BY m.created_at DESC LIMIT 30`,[req.user.id,q])
    ]);
    res.json({data:{members:members.rows,restaurants:restaurants.rows,moments:moments.rows}});
  } catch(e){next(e);}
});


// Fodd 8.0 — Complete Hangout Experience
async function ensureHangoutPreferences(userId) {
  await pool.query(`INSERT INTO hangout_preferences(user_id) VALUES($1) ON CONFLICT(user_id) DO NOTHING`,[userId]);
}

app.get("/api/hangout/preferences",requireAuth,async(req,res,next)=>{
  try{await ensureHangoutPreferences(req.user.id);const result=await pool.query(`SELECT availability_status AS "availabilityStatus",availability_note AS "availabilityNote",availability_expires_at AS "availabilityExpiresAt",invite_policy AS "invitePolicy",home_city AS "homeCity",onboarding_completed AS "onboardingCompleted" FROM hangout_preferences WHERE user_id=$1`,[req.user.id]);res.json({data:result.rows[0]});}catch(e){next(e);}
});
app.patch("/api/hangout/preferences",requireAuth,async(req,res,next)=>{
  try{
    await ensureHangoutPreferences(req.user.id);
    const input=z.object({availabilityStatus:z.enum(['offline','free_now','coffee','lunch','dinner','weekend']).optional(),availabilityNote:z.string().trim().max(120).optional(),availabilityMinutes:z.number().int().min(15).max(10080).nullable().optional(),invitePolicy:z.enum(['everyone','friends','close_foodies']).optional(),homeCity:z.string().trim().max(100).optional(),onboardingCompleted:z.boolean().optional()}).parse(req.body);
    const expires=input.availabilityStatus==='offline' ? null : (input.availabilityMinutes===null ? null : input.availabilityMinutes===undefined ? undefined : new Date(Date.now()+input.availabilityMinutes*60000).toISOString());
    const keepExpiry=expires===undefined;
    const result=await pool.query(`UPDATE hangout_preferences SET availability_status=COALESCE($1,availability_status),availability_note=COALESCE($2,availability_note),availability_expires_at=CASE WHEN $3::boolean THEN availability_expires_at ELSE $4::timestamptz END,invite_policy=COALESCE($5,invite_policy),home_city=COALESCE($6,home_city),onboarding_completed=COALESCE($7,onboarding_completed),updated_at=NOW() WHERE user_id=$8 RETURNING availability_status AS "availabilityStatus",availability_note AS "availabilityNote",availability_expires_at AS "availabilityExpiresAt",invite_policy AS "invitePolicy",home_city AS "homeCity",onboarding_completed AS "onboardingCompleted"`,[input.availabilityStatus??null,input.availabilityNote??null,keepExpiry,keepExpiry?null:expires,input.invitePolicy??null,input.homeCity??null,input.onboardingCompleted??null,req.user.id]);
    res.json({data:result.rows[0]});
  }catch(e){next(e);}
});

app.get("/api/hangout/available",requireAuth,async(req,res,next)=>{
  try{
    const result=await pool.query(`SELECT ${publicUserSQL},EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id) AS "isFollowing",EXISTS(SELECT 1 FROM close_foodies cf WHERE cf.user_id=$1 AND cf.member_id=u.id) AS "isCloseFoodie",FALSE AS "followRequestPending",FALSE AS "isBlocked",hp.availability_status AS "availabilityStatus",hp.availability_note AS "availabilityNote",hp.availability_expires_at AS "availabilityExpiresAt",hp.home_city AS "homeCity" FROM hangout_preferences hp JOIN users u ON u.id=hp.user_id WHERE u.id<>$1 AND hp.availability_status<>'offline' AND (hp.availability_expires_at IS NULL OR hp.availability_expires_at>NOW()) AND (EXISTS(SELECT 1 FROM follows f WHERE f.follower_id=$1 AND f.following_id=u.id) OR EXISTS(SELECT 1 FROM close_foodies cf WHERE cf.user_id=$1 AND cf.member_id=u.id)) AND NOT EXISTS(SELECT 1 FROM blocks b WHERE (b.blocker_id=$1 AND b.blocked_id=u.id) OR (b.blocker_id=u.id AND b.blocked_id=$1)) ORDER BY CASE hp.availability_status WHEN 'free_now' THEN 0 WHEN 'coffee' THEN 1 WHEN 'lunch' THEN 2 WHEN 'dinner' THEN 3 ELSE 4 END,hp.updated_at DESC LIMIT 50`,[req.user.id]);
    res.json({data:result.rows});
  }catch(e){next(e);}
});

app.post("/api/hangout/quick",requireAuth,async(req,res,next)=>{
  const client=await pool.connect();
  try{
    const input=z.object({memberIds:z.array(z.string().uuid()).max(8).default([]),title:z.string().trim().min(1).max(100).default('Nongkrong Sekarang'),minutesFromNow:z.number().int().min(20).max(360).default(90)}).parse(req.body);
    const requested=[...new Set(input.memberIds.filter(id=>id!==req.user.id))];const allowed=[];
    for(const id of requested){if(await hangoutInviteAllowed(req.user.id,id))allowed.push(id);}
    const people=[req.user.id,...allowed];
    const restaurants=await pool.query(`WITH group_cuisines AS (SELECT DISTINCT lower(trim(cuisine)) AS term FROM taste_preferences tp CROSS JOIN LATERAL unnest(tp.cuisines) AS cuisine WHERE tp.user_id=ANY($1::uuid[]) AND trim(cuisine)<>''),group_cities AS (SELECT DISTINCT lower(trim(home_city)) AS city FROM hangout_preferences WHERE user_id=ANY($1::uuid[]) AND trim(home_city)<>'') SELECT r.id FROM restaurants r ORDER BY ((SELECT COUNT(*) FROM group_cuisines gc WHERE lower(r.name||' '||r.category||' '||r.menu) LIKE '%'||gc.term||'%')*4 + (SELECT COUNT(*) FROM group_cities gcity WHERE lower(r.address) LIKE '%'||gcity.city||'%')*3 + (SELECT COUNT(*) FROM saved_restaurants sr WHERE sr.restaurant_id=r.id AND sr.user_id=ANY($1::uuid[]))*2) DESC,r.rating DESC,r.is_verified DESC LIMIT 4`,[people]);
    if(!restaurants.rowCount)return res.status(409).json({error:'Belum ada restoran yang dapat dipakai untuk Quick Hangout'});
    const scheduledAt=new Date(Date.now()+input.minutesFromNow*60000).toISOString();
    await client.query('BEGIN');const plan=(await client.query(`INSERT INTO dining_plans(host_id,title,note,scheduled_at) VALUES($1,$2,$3,$4) RETURNING id`,[req.user.id,input.title,'Dibuat lewat Quick Hangout',scheduledAt])).rows[0];
    for(const id of allowed)await client.query(`INSERT INTO dining_plan_members(plan_id,user_id) VALUES($1,$2) ON CONFLICT DO NOTHING`,[plan.id,id]);
    for(const row of restaurants.rows)await client.query(`INSERT INTO dining_plan_candidates(plan_id,restaurant_id,proposed_by) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`,[plan.id,row.id,req.user.id]);
    await client.query(`INSERT INTO dining_plan_time_options(plan_id,proposed_by,scheduled_at) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`,[plan.id,req.user.id,scheduledAt]);
    await client.query('COMMIT');
    for(const id of allowed){const body=`${req.user.name} mengajak nongkrong sekarang`;await pool.query(`INSERT INTO notifications(user_id,actor_id,type,plan_id,body) VALUES($1,$2,'together',$3,$4)`,[id,req.user.id,plan.id,body]);void pushIfEnabled(id,'together',{title:'Quick Hangout',body,type:'together',planId:plan.id});}
    const rows=await loadDiningPlans(req.user.id,plan.id);res.status(201).json({data:rows[0]});
  }catch(e){await client.query('ROLLBACK').catch(()=>{});next(e);}finally{client.release();}
});

app.post("/api/together/plans/:id/time-options",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access||access.status!=='planned')return res.status(403).json({error:'Rencana tidak dapat diedit'});const {scheduledAt}=z.object({scheduledAt:z.string().datetime()}).parse(req.body);if(new Date(scheduledAt)<=new Date())return res.status(400).json({error:'Pilihan waktu harus di masa depan'});await pool.query(`INSERT INTO dining_plan_time_options(plan_id,proposed_by,scheduled_at) VALUES($1,$2,$3) ON CONFLICT(plan_id,scheduled_at) DO NOTHING`,[req.params.id,req.user.id,scheduledAt]);const rows=await loadDiningPlans(req.user.id,req.params.id);res.status(201).json({data:rows[0]});}catch(e){next(e);}
});
app.put("/api/together/plans/:id/time-vote",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access||access.status!=='planned')return res.status(403).json({error:'Voting waktu sudah ditutup'});const {optionId}=z.object({optionId:z.string().uuid()}).parse(req.body);const exists=await pool.query(`SELECT 1 FROM dining_plan_time_options WHERE id=$1 AND plan_id=$2`,[optionId,req.params.id]);if(!exists.rowCount)return res.status(404).json({error:'Pilihan waktu tidak ditemukan'});await pool.query(`INSERT INTO dining_plan_time_votes(plan_id,option_id,user_id) VALUES($1,$2,$3) ON CONFLICT(plan_id,user_id) DO UPDATE SET option_id=EXCLUDED.option_id,created_at=NOW()`,[req.params.id,optionId,req.user.id]);const rows=await loadDiningPlans(req.user.id,req.params.id);res.json({data:rows[0]});}catch(e){next(e);}
});
app.delete("/api/together/plans/:id/time-options/:optionId",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:'Rencana tidak ditemukan'});const option=await pool.query(`SELECT proposed_by FROM dining_plan_time_options WHERE id=$1 AND plan_id=$2`,[req.params.optionId,req.params.id]);if(!option.rowCount)return res.status(204).end();if(access.hostId!==req.user.id&&option.rows[0].proposed_by!==req.user.id)return res.status(403).json({error:'Tidak memiliki izin'});await pool.query(`DELETE FROM dining_plan_time_options WHERE id=$1 AND plan_id=$2`,[req.params.optionId,req.params.id]);res.status(204).end();}catch(e){next(e);}
});

app.put("/api/together/plans/:id/presence",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:'Rencana tidak ditemukan'});const input=z.object({status:z.enum(['not_started','otw','arrived']),etaMinutes:z.number().int().min(0).max(1440).nullable().optional()}).parse(req.body);await pool.query(`INSERT INTO dining_plan_presence(plan_id,user_id,status,eta_minutes,updated_at) VALUES($1,$2,$3,$4,NOW()) ON CONFLICT(plan_id,user_id) DO UPDATE SET status=EXCLUDED.status,eta_minutes=EXCLUDED.eta_minutes,updated_at=NOW()`,[req.params.id,req.user.id,input.status,input.status==='otw'?(input.etaMinutes??null):null]);const rows=await loadDiningPlans(req.user.id,req.params.id);res.json({data:rows[0]});}catch(e){next(e);}
});

app.get("/api/together/plans/:id/split-bill",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:'Rencana tidak ditemukan'});const bill=await pool.query(`SELECT sb.plan_id AS "planId",sb.subtotal,sb.extras,(sb.subtotal+sb.extras)::int AS total,sb.note,sb.receipt_image AS "receiptImage",sb.updated_at AS "updatedAt",COALESCE((SELECT json_agg(json_build_object('userId',p.user_id,'name',u.name,'avatar',u.avatar,'amount',p.amount,'paid',p.paid) ORDER BY u.name) FROM split_bill_participants p JOIN users u ON u.id=p.user_id WHERE p.plan_id=sb.plan_id),'[]'::json) AS participants FROM split_bills sb WHERE sb.plan_id=$1`,[req.params.id]);if(bill.rowCount)return res.json({data:bill.rows[0]});const people=await pool.query(`SELECT u.id AS "userId",u.name,u.avatar,0::int AS amount,false AS paid FROM users u WHERE u.id=(SELECT host_id FROM dining_plans WHERE id=$1) OR u.id IN (SELECT user_id FROM dining_plan_members WHERE plan_id=$1 AND rsvp<>'declined') ORDER BY u.name`,[req.params.id]);res.json({data:{planId:req.params.id,subtotal:0,extras:0,total:0,note:'',receiptImage:'',updatedAt:null,participants:people.rows}});}catch(e){next(e);}
});
app.put("/api/together/plans/:id/split-bill",requireAuth,async(req,res,next)=>{
  const client=await pool.connect();try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:'Rencana tidak ditemukan'});const input=z.object({subtotal:z.number().int().min(0).max(1000000000),extras:z.number().int().min(0).max(1000000000).default(0),note:z.string().trim().max(240).default(''),receiptImage:z.string().max(7000000).default(''),participantIds:z.array(z.string().uuid()).min(1).max(50)}).parse(req.body);const eligible=await pool.query(`SELECT user_id FROM (SELECT host_id AS user_id FROM dining_plans WHERE id=$1 UNION SELECT user_id FROM dining_plan_members WHERE plan_id=$1 AND rsvp<>'declined') x WHERE user_id=ANY($2::uuid[])`,[req.params.id,input.participantIds]);if(eligible.rowCount!==new Set(input.participantIds).size)return res.status(400).json({error:'Peserta split bill tidak valid'});const ids=[...new Set(input.participantIds)];const total=input.subtotal+input.extras;const base=Math.floor(total/ids.length);let remainder=total-base*ids.length;await client.query('BEGIN');await client.query(`INSERT INTO split_bills(plan_id,created_by,subtotal,extras,note,receipt_image,updated_at) VALUES($1,$2,$3,$4,$5,$6,NOW()) ON CONFLICT(plan_id) DO UPDATE SET subtotal=EXCLUDED.subtotal,extras=EXCLUDED.extras,note=EXCLUDED.note,receipt_image=EXCLUDED.receipt_image,updated_at=NOW()`,[req.params.id,req.user.id,input.subtotal,input.extras,input.note,input.receiptImage]);await client.query(`DELETE FROM split_bill_participants WHERE plan_id=$1`,[req.params.id]);for(const id of ids){const amount=base+(remainder>0?1:0);if(remainder>0)remainder--;await client.query(`INSERT INTO split_bill_participants(plan_id,user_id,amount) VALUES($1,$2,$3)`,[req.params.id,id,amount]);}await client.query('COMMIT');const result=await pool.query(`SELECT sb.plan_id AS "planId",sb.subtotal,sb.extras,(sb.subtotal+sb.extras)::int AS total,sb.note,sb.receipt_image AS "receiptImage",sb.updated_at AS "updatedAt",(SELECT json_agg(json_build_object('userId',p.user_id,'name',u.name,'avatar',u.avatar,'amount',p.amount,'paid',p.paid) ORDER BY u.name) FROM split_bill_participants p JOIN users u ON u.id=p.user_id WHERE p.plan_id=sb.plan_id) AS participants FROM split_bills sb WHERE sb.plan_id=$1`,[req.params.id]);res.json({data:result.rows[0]});}catch(e){await client.query('ROLLBACK').catch(()=>{});next(e);}finally{client.release();}
});
app.put("/api/together/plans/:id/split-bill/:userId/paid",requireAuth,async(req,res,next)=>{
  try{const access=await planAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:'Rencana tidak ditemukan'});if(req.user.id!==req.params.userId&&access.hostId!==req.user.id)return res.status(403).json({error:'Hanya peserta sendiri atau host yang dapat mengubah status bayar'});const {paid}=z.object({paid:z.boolean()}).parse(req.body);await pool.query(`UPDATE split_bill_participants SET paid=$1 WHERE plan_id=$2 AND user_id=$3`,[paid,req.params.id,req.params.userId]);res.status(204).end();}catch(e){next(e);}
});

async function wishlistAccess(userId,wishlistId) {
  const result=await pool.query(`SELECT w.id,w.owner_id AS "ownerId",CASE WHEN w.owner_id=$1 THEN 'owner' ELSE wm.role END AS role FROM hangout_wishlists w LEFT JOIN hangout_wishlist_members wm ON wm.wishlist_id=w.id AND wm.user_id=$1 WHERE w.id=$2 AND (w.owner_id=$1 OR wm.user_id=$1)`,[userId,wishlistId]);return result.rows[0]||null;
}
app.get("/api/hangout/wishlists",requireAuth,async(req,res,next)=>{
  try{const result=await pool.query(`SELECT w.id,w.name,w.owner_id AS "ownerId",u.name AS "ownerName",(w.owner_id=$1) AS "isOwner",CASE WHEN w.owner_id=$1 THEN 'owner' ELSE wm.role END AS role,(SELECT COUNT(*)::int FROM hangout_wishlist_restaurants wr WHERE wr.wishlist_id=w.id) AS "restaurantCount",(SELECT COUNT(*)::int+1 FROM hangout_wishlist_members x WHERE x.wishlist_id=w.id) AS "memberCount" FROM hangout_wishlists w JOIN users u ON u.id=w.owner_id LEFT JOIN hangout_wishlist_members wm ON wm.wishlist_id=w.id AND wm.user_id=$1 WHERE w.owner_id=$1 OR wm.user_id=$1 ORDER BY w.updated_at DESC`,[req.user.id]);res.json({data:result.rows});}catch(e){next(e);}
});
app.post("/api/hangout/wishlists",requireAuth,async(req,res,next)=>{try{const {name}=z.object({name:z.string().trim().min(1).max(80)}).parse(req.body);const row=(await pool.query(`INSERT INTO hangout_wishlists(owner_id,name) VALUES($1,$2) RETURNING id,name,owner_id AS "ownerId"`,[req.user.id,name])).rows[0];res.status(201).json({data:{...row,ownerName:req.user.name,isOwner:true,role:'owner',restaurantCount:0,memberCount:1}});}catch(e){next(e);}});
app.get("/api/hangout/wishlists/:id/restaurants",requireAuth,async(req,res,next)=>{try{const access=await wishlistAccess(req.user.id,req.params.id);if(!access)return res.status(404).json({error:'Wishlist tidak ditemukan'});const result=await pool.query(`SELECT ${restaurantSQL},EXISTS(SELECT 1 FROM saved_restaurants sr WHERE sr.user_id=$1 AND sr.restaurant_id=r.id) AS "isSaved" FROM hangout_wishlist_restaurants wr JOIN restaurants r ON r.id=wr.restaurant_id WHERE wr.wishlist_id=$2 ORDER BY wr.created_at DESC`,[req.user.id,req.params.id]);res.json({data:result.rows});}catch(e){next(e);}});
app.put("/api/hangout/wishlists/:id/restaurants/:restaurantId",requireAuth,async(req,res,next)=>{try{const access=await wishlistAccess(req.user.id,req.params.id);if(!access||access.role==='viewer')return res.status(403).json({error:'Wishlist hanya dapat diedit oleh owner/editor'});const exists=await pool.query(`SELECT 1 FROM restaurants WHERE id=$1`,[req.params.restaurantId]);if(!exists.rowCount)return res.status(404).json({error:'Restoran belum tersedia di Fodd'});await pool.query(`INSERT INTO hangout_wishlist_restaurants(wishlist_id,restaurant_id,added_by) VALUES($1,$2,$3) ON CONFLICT DO NOTHING`,[req.params.id,req.params.restaurantId,req.user.id]);await pool.query(`UPDATE hangout_wishlists SET updated_at=NOW() WHERE id=$1`,[req.params.id]);res.status(204).end();}catch(e){next(e);}});
app.delete("/api/hangout/wishlists/:id/restaurants/:restaurantId",requireAuth,async(req,res,next)=>{try{const access=await wishlistAccess(req.user.id,req.params.id);if(!access||access.role==='viewer')return res.status(403).json({error:'Tidak memiliki izin'});await pool.query(`DELETE FROM hangout_wishlist_restaurants WHERE wishlist_id=$1 AND restaurant_id=$2`,[req.params.id,req.params.restaurantId]);res.status(204).end();}catch(e){next(e);}});
app.post("/api/hangout/wishlists/:id/members",requireAuth,async(req,res,next)=>{try{const access=await wishlistAccess(req.user.id,req.params.id);if(!access||access.role!=='owner')return res.status(403).json({error:'Hanya owner yang dapat menambah anggota'});const {userId,role}=z.object({userId:z.string().uuid(),role:z.enum(['editor','viewer']).default('editor')}).parse(req.body);if(!(await hangoutInviteAllowed(req.user.id,userId)))return res.status(403).json({error:'Foodie ini membatasi kolaborasi'});await pool.query(`INSERT INTO hangout_wishlist_members(wishlist_id,user_id,role) VALUES($1,$2,$3) ON CONFLICT(wishlist_id,user_id) DO UPDATE SET role=EXCLUDED.role`,[req.params.id,userId,role]);res.status(204).end();}catch(e){next(e);}});

app.get("/api/hangout/passport",requireAuth,async(req,res,next)=>{
  try{const stats=(await pool.query(`SELECT (SELECT COUNT(*)::int FROM moments WHERE user_id=$1 AND char_length(trim(caption))>0) AS moments,(SELECT COUNT(*)::int FROM moments WHERE user_id=$1 AND moment_type='checkin') AS checkins,(SELECT COUNT(*)::int FROM place_reviews WHERE user_id=$1)+(SELECT COUNT(*)::int FROM restaurant_reviews WHERE user_id=$1) AS reviews,(SELECT COUNT(*)::int FROM saved_restaurants WHERE user_id=$1) AS saved,(SELECT COUNT(*)::int FROM dining_plans p WHERE p.status='completed' AND (p.host_id=$1 OR EXISTS(SELECT 1 FROM dining_plan_members m WHERE m.plan_id=p.id AND m.user_id=$1 AND m.rsvp<>'declined'))) AS completed_plans`,[req.user.id])).rows[0];const values={moments:Number(stats.moments),checkins:Number(stats.checkins),reviews:Number(stats.reviews),saved:Number(stats.saved),completedPlans:Number(stats.completed_plans)};const defs=[['first_hangout','First Hangout','Selesaikan 1 nongkrong','person.3.fill','completedPlans',1],['hangout_regular','Hangout Regular','Selesaikan 5 nongkrong','calendar.badge.checkmark','completedPlans',5],['food_diary','Food Storyteller','Buat 20 Food Moment','book.closed.fill','moments',20],['explorer','Food Explorer','Check-in di 10 tempat','map.fill','checkins',10],['reviewer','Trusted Reviewer','Tulis 10 review','star.bubble.fill','reviews',10],['collector','Wishlist Master','Simpan 20 restoran','heart.text.square.fill','saved',20]];const achievements=defs.map(([code,title,subtitle,icon,key,target])=>({code,title,subtitle,icon,progress:Math.min(values[key],target),target,unlocked:values[key]>=target}));res.json({data:{stats:values,achievements}});}catch(e){next(e);}
});
app.get("/api/hangout/recap/monthly",requireAuth,async(req,res,next)=>{
  try{const result=await pool.query(`SELECT (SELECT COUNT(*)::int FROM dining_plans p WHERE p.status='completed' AND p.scheduled_at>=date_trunc('month',NOW()) AND (p.host_id=$1 OR EXISTS(SELECT 1 FROM dining_plan_members m WHERE m.plan_id=p.id AND m.user_id=$1 AND m.rsvp<>'declined'))) AS "hangoutCount",(SELECT COUNT(*)::int FROM moments m WHERE m.user_id=$1 AND m.created_at>=date_trunc('month',NOW()) AND char_length(trim(m.caption))>0) AS "momentCount",(SELECT COUNT(DISTINCT p.selected_restaurant_id)::int FROM dining_plans p WHERE p.status='completed' AND p.selected_restaurant_id IS NOT NULL AND p.scheduled_at>=date_trunc('month',NOW()) AND (p.host_id=$1 OR EXISTS(SELECT 1 FROM dining_plan_members m WHERE m.plan_id=p.id AND m.user_id=$1 AND m.rsvp<>'declined'))) AS "restaurantCount",(SELECT COUNT(DISTINCT x.user_id)::int FROM (SELECT m.user_id,p.id FROM dining_plans p JOIN dining_plan_members m ON m.plan_id=p.id WHERE p.status='completed' AND p.scheduled_at>=date_trunc('month',NOW()) AND p.host_id=$1 UNION SELECT p.host_id AS user_id,p.id FROM dining_plans p JOIN dining_plan_members me ON me.plan_id=p.id WHERE p.status='completed' AND p.scheduled_at>=date_trunc('month',NOW()) AND me.user_id=$1 AND me.rsvp<>'declined') x WHERE x.user_id<>$1) AS "foodieCount",COALESCE((SELECT r.name FROM dining_plans p JOIN restaurants r ON r.id=p.selected_restaurant_id WHERE p.status='completed' AND p.scheduled_at>=date_trunc('month',NOW()) AND (p.host_id=$1 OR EXISTS(SELECT 1 FROM dining_plan_members m WHERE m.plan_id=p.id AND m.user_id=$1 AND m.rsvp<>'declined')) GROUP BY r.name ORDER BY COUNT(*) DESC LIMIT 1),'Belum ada') AS "topPlace"`,[req.user.id]);res.json({data:{month:new Intl.DateTimeFormat('id-ID',{month:'long',year:'numeric'}).format(new Date()),...result.rows[0]}});}catch(e){next(e);}
});

app.post("/api/product-events",requireAuth,async(req,res,next)=>{try{const input=z.object({eventName:z.string().trim().min(1).max(80),screen:z.string().trim().max(80).default(''),metadata:z.any().default({})}).parse(req.body);await pool.query(`INSERT INTO product_events(user_id,event_name,screen,metadata) VALUES($1,$2,$3,$4::jsonb)`,[req.user.id,input.eventName,input.screen,JSON.stringify(input.metadata)]);res.status(204).end();}catch(e){next(e);}});

app.get("/api/admin/restaurant-claims", requireAdmin, async (req,res,next) => {
  try {const status=String(req.query.status||'pending');const result=await pool.query(`SELECT rc.id,rc.restaurant_id AS "restaurantId",r.name AS "restaurantName",rc.user_id AS "userId",u.name AS "userName",u.username,rc.business_name AS "businessName",rc.role,rc.note,rc.status,rc.created_at AS "createdAt" FROM restaurant_claims rc JOIN restaurants r ON r.id=rc.restaurant_id JOIN users u ON u.id=rc.user_id WHERE ($1='' OR rc.status=$1) ORDER BY rc.created_at DESC LIMIT 250`,[status]);res.json({data:result.rows});}catch(e){next(e);}
});
app.patch("/api/admin/restaurant-claims/:id", requireAdmin, async (req,res,next) => {
  const client=await pool.connect();
  try {const {status}=z.object({status:z.enum(['approved','rejected'])}).parse(req.body);await client.query('BEGIN');const claim=(await client.query(`UPDATE restaurant_claims SET status=$1,reviewed_at=NOW() WHERE id=$2 RETURNING restaurant_id,user_id,role`,[status,req.params.id])).rows[0];if(!claim){await client.query('ROLLBACK');return res.status(404).json({error:'Klaim tidak ditemukan'});}if(status==='approved'){await client.query(`INSERT INTO restaurant_owners(restaurant_id,user_id,role) VALUES($1,$2,$3) ON CONFLICT(restaurant_id,user_id) DO UPDATE SET role=EXCLUDED.role`,[claim.restaurant_id,claim.user_id,claim.role]);await client.query(`UPDATE restaurants SET is_verified=TRUE WHERE id=$1`,[claim.restaurant_id]);}else{await client.query(`DELETE FROM restaurant_owners WHERE restaurant_id=$1 AND user_id=$2`,[claim.restaurant_id,claim.user_id]);await client.query(`UPDATE restaurants SET is_verified=EXISTS(SELECT 1 FROM restaurant_owners WHERE restaurant_id=$1) WHERE id=$1`,[claim.restaurant_id]);}await client.query('COMMIT');res.json({data:{id:req.params.id,status}});}catch(e){await client.query('ROLLBACK');next(e);}finally{client.release();}
});
app.patch("/api/admin/creators/:id", requireAdmin, async (req,res,next) => {
  try {const {verified}=z.object({verified:z.boolean()}).parse(req.body);const result=await pool.query(`UPDATE users SET creator_verified=$1,is_creator=CASE WHEN $1 THEN TRUE ELSE is_creator END WHERE id=$2 RETURNING id,is_creator AS "isCreator",creator_verified AS "creatorVerified"`,[verified,req.params.id]);if(!result.rowCount)return res.status(404).json({error:'Creator tidak ditemukan'});res.json({data:result.rows[0]});}catch(e){next(e);}
});

app.get("/api/admin/reports", requireAdmin, async (req,res,next) => {
  try {
    const status=String(req.query.status||"open");
    const result=await pool.query(`SELECT r.id,r.target_type AS "targetType",r.target_id AS "targetId",r.reason,r.details,r.status,r.created_at AS "createdAt",u.name AS "reporterName",u.username AS "reporterUsername" FROM reports r JOIN users u ON u.id=r.reporter_id WHERE ($1='' OR r.status=$1) ORDER BY r.created_at DESC LIMIT 250`,[status]);
    res.json({data:result.rows});
  } catch(e){next(e);}
});
app.patch("/api/admin/reports/:id", requireAdmin, async (req,res,next) => {
  try {
    const {status}=z.object({status:z.enum(['open','reviewing','resolved','dismissed'])}).parse(req.body);
    const result=await pool.query(`UPDATE reports SET status=$1 WHERE id=$2 RETURNING id,status`,[status,req.params.id]);if(!result.rowCount)return res.status(404).json({error:"Laporan tidak ditemukan"});res.json({data:result.rows[0]});
  } catch(e){next(e);}
});

app.post("/api/devices", requireAuth, async (req,res,next) => {
  try { const input=z.object({deviceToken:z.string().regex(/^[a-fA-F0-9]{32,256}$/),platform:z.literal("ios").default("ios")}).parse(req.body);await pool.query(`INSERT INTO device_tokens(device_token,user_id,platform,updated_at) VALUES($1,$2,$3,NOW()) ON CONFLICT(device_token) DO UPDATE SET user_id=EXCLUDED.user_id,platform=EXCLUDED.platform,updated_at=NOW()`,[input.deviceToken,req.user.id,input.platform]);res.status(204).end(); }
  catch(e){next(e);}
});
app.delete("/api/devices/:deviceToken", requireAuth, async (req,res,next) => {
  try { const token=z.string().regex(/^[a-fA-F0-9]{32,256}$/).parse(req.params.deviceToken);await pool.query(`DELETE FROM device_tokens WHERE device_token=$1 AND user_id=$2`,[token,req.user.id]);res.status(204).end(); }
  catch(e){next(e);}
});

app.use((error,_req,res,_next) => {
  if(error.status) return res.status(error.status).json({error:error.message});
  if(error instanceof z.ZodError) return res.status(400).json({error:"Data tidak valid",details:error.issues});
  if(error.code==="23503" || error.code==="23514" || error.code==="22P02") return res.status(400).json({error:"Data tidak dapat diproses"});
  console.error(error);res.status(500).json({error:"Terjadi kesalahan pada server"});
});

await migrateAndSeed();
app.listen(port,"0.0.0.0",()=>console.log(`Fodd API v8.0 aktif pada port ${port}`));
