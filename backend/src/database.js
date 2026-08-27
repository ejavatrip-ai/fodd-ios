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
    CREATE EXTENSION IF NOT EXISTS pgcrypto;
    CREATE TABLE IF NOT EXISTS users (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      name TEXT NOT NULL CHECK (char_length(name) BETWEEN 2 AND 80),
      username TEXT NOT NULL UNIQUE CHECK (username ~ '^[a-z0-9_]{3,30}$'),
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      password_salt TEXT NOT NULL,
      bio TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS follows (
      follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (follower_id,following_id),
      CHECK (follower_id <> following_id)
    );
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
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE CASCADE;
    CREATE TABLE IF NOT EXISTS messages (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CHECK (sender_id <> receiver_id)
    );
    CREATE INDEX IF NOT EXISTS moments_user_created_idx ON moments(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS messages_participants_idx ON messages(sender_id,receiver_id,created_at);
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
