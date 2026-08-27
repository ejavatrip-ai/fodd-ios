import pg from "pg";

const { Pool } = pg;

export const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === "production" ? { rejectUnauthorized: false } : false,
  max: 10,
  idleTimeoutMillis: 30_000
});

export async function migrateAndSeed() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS restaurants (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      image TEXT NOT NULL,
      rating NUMERIC(2,1) NOT NULL CHECK (rating BETWEEN 0 AND 5),
      distance TEXT NOT NULL,
      price TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS moments (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      author TEXT NOT NULL,
      caption TEXT NOT NULL CHECK (char_length(caption) BETWEEN 1 AND 500),
      restaurant_id TEXT REFERENCES restaurants(id) ON DELETE SET NULL,
      image TEXT NOT NULL DEFAULT 'Noodles',
      likes INTEGER NOT NULL DEFAULT 0 CHECK (likes >= 0),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  const values = [
    ["kopi-nok", "Kopi Nok", "Kafe • Sarapan", "Cafe", 4.8, "600 m", "Rp20–45K"],
    ["dapur-nusantara", "Dapur Nusantara", "Indonesia • Halal", "FoodHero", 4.9, "1,2 km", "Rp25–60K"],
    ["mie-ceria", "Mie Ceria", "Mi • Asia", "Noodles", 4.7, "1,8 km", "Rp18–35K"],
    ["burger-social", "Burger Social", "Burger • Barat", "Burgers", 4.6, "2,1 km", "Rp35–80K"]
  ];
  for (const row of values) {
    await pool.query(
      `INSERT INTO restaurants (id,name,category,image,rating,distance,price)
       VALUES ($1,$2,$3,$4,$5,$6,$7) ON CONFLICT (id) DO NOTHING`, row
    );
  }
}
