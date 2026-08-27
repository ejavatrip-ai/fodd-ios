import express from "express";
import cors from "cors";
import { z } from "zod";
import { migrateAndSeed, pool } from "./database.js";

if (!process.env.DATABASE_URL) {
  console.error("DATABASE_URL wajib tersedia");
  process.exit(1);
}

const app = express();
const port = Number(process.env.PORT || 3000);
app.disable("x-powered-by");
app.use(cors({ origin: process.env.ALLOWED_ORIGIN || "*" }));
app.use(express.json({ limit: "256kb" }));

app.get("/health", async (_req, res, next) => {
  try {
    await pool.query("SELECT 1");
    res.json({ status: "ok", service: "fodd-api" });
  } catch (error) { next(error); }
});

app.get("/api/restaurants", async (req, res, next) => {
  try {
    const search = String(req.query.search || "").trim();
    const result = await pool.query(
      `SELECT id,name,category,image,rating::float8 AS rating,distance,price
       FROM restaurants WHERE ($1 = '' OR name ILIKE '%' || $1 || '%' OR category ILIKE '%' || $1 || '%')
       ORDER BY rating DESC`, [search]
    );
    res.json({ data: result.rows });
  } catch (error) { next(error); }
});

app.get("/api/moments", async (_req, res, next) => {
  try {
    const result = await pool.query(
      `SELECT id,author,caption,restaurant_id AS "restaurantId",image,likes,created_at AS "createdAt"
       FROM moments ORDER BY created_at DESC LIMIT 50`
    );
    res.json({ data: result.rows });
  } catch (error) { next(error); }
});

const momentSchema = z.object({
  author: z.string().trim().min(2).max(80).default("Food Explorer"),
  caption: z.string().trim().min(1).max(500),
  restaurantId: z.string().trim().min(1).max(100).nullable().optional(),
  image: z.enum(["FoodHero", "Cafe", "Noodles", "Burgers"]).default("Noodles")
});

app.post("/api/moments", async (req, res, next) => {
  try {
    const input = momentSchema.parse(req.body);
    const result = await pool.query(
      `INSERT INTO moments (author,caption,restaurant_id,image) VALUES ($1,$2,$3,$4)
       RETURNING id,author,caption,restaurant_id AS "restaurantId",image,likes,created_at AS "createdAt"`,
      [input.author, input.caption, input.restaurantId ?? null, input.image]
    );
    res.status(201).json({ data: result.rows[0] });
  } catch (error) { next(error); }
});

app.use((error, _req, res, _next) => {
  if (error instanceof z.ZodError) return res.status(400).json({ error: "Data tidak valid", details: error.issues });
  console.error(error);
  res.status(500).json({ error: "Terjadi kesalahan pada server" });
});

await migrateAndSeed();
app.listen(port, "0.0.0.0", () => console.log(`Fodd API aktif pada port ${port}`));
