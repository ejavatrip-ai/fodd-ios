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
      avatar TEXT NOT NULL DEFAULT '',
      email_verified BOOLEAN NOT NULL DEFAULT FALSE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    ALTER TABLE users ADD COLUMN IF NOT EXISTS avatar TEXT NOT NULL DEFAULT '';
    ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified BOOLEAN NOT NULL DEFAULT FALSE;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS is_private BOOLEAN NOT NULL DEFAULT FALSE;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS is_creator BOOLEAN NOT NULL DEFAULT FALSE;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS creator_verified BOOLEAN NOT NULL DEFAULT FALSE;
    ALTER TABLE users ADD COLUMN IF NOT EXISTS creator_category TEXT NOT NULL DEFAULT '';
    ALTER TABLE users ADD COLUMN IF NOT EXISTS creator_website TEXT NOT NULL DEFAULT '';
    ALTER TABLE users ADD COLUMN IF NOT EXISTS creator_since TIMESTAMPTZ;

    CREATE TABLE IF NOT EXISTS sessions (
      token_hash TEXT PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      expires_at TIMESTAMPTZ NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS auth_codes (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      purpose TEXT NOT NULL CHECK (purpose IN ('email_verify','password_reset')),
      code_hash TEXT NOT NULL,
      expires_at TIMESTAMPTZ NOT NULL,
      consumed_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS follows (
      follower_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      following_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (follower_id,following_id),
      CHECK (follower_id <> following_id)
    );


    CREATE TABLE IF NOT EXISTS user_preferences (
      user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      push_follows BOOLEAN NOT NULL DEFAULT TRUE,
      push_likes BOOLEAN NOT NULL DEFAULT TRUE,
      push_comments BOOLEAN NOT NULL DEFAULT TRUE,
      push_messages BOOLEAN NOT NULL DEFAULT TRUE,
      push_recommendations BOOLEAN NOT NULL DEFAULT TRUE,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS push_recommendations BOOLEAN NOT NULL DEFAULT TRUE;
    ALTER TABLE user_preferences ADD COLUMN IF NOT EXISTS push_together BOOLEAN NOT NULL DEFAULT TRUE;

    CREATE TABLE IF NOT EXISTS taste_preferences (
      user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
      cuisines TEXT[] NOT NULL DEFAULT '{}',
      moods TEXT[] NOT NULL DEFAULT '{}',
      spicy_level INTEGER NOT NULL DEFAULT 2 CHECK (spicy_level BETWEEN 0 AND 4),
      price_sensitivity INTEGER NOT NULL DEFAULT 2 CHECK (price_sensitivity BETWEEN 0 AND 4),
      adventurous_level INTEGER NOT NULL DEFAULT 2 CHECK (adventurous_level BETWEEN 0 AND 4),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS follow_requests (
      requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      target_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (requester_id,target_id),
      CHECK (requester_id <> target_id)
    );

    CREATE TABLE IF NOT EXISTS blocks (
      blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (blocker_id,blocked_id),
      CHECK (blocker_id <> blocked_id)
    );

    CREATE TABLE IF NOT EXISTS reports (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      reporter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      target_type TEXT NOT NULL CHECK (target_type IN ('user','moment','comment')),
      target_id UUID NOT NULL,
      reason TEXT NOT NULL CHECK (reason IN ('spam','harassment','hate','sexual','violence','misinformation','other')),
      details TEXT NOT NULL DEFAULT '' CHECK (char_length(details) <= 1000),
      status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','reviewing','resolved','dismissed')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (reporter_id,target_type,target_id,reason)
    );

    CREATE TABLE IF NOT EXISTS collections (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
      description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 240),
      is_private BOOLEAN NOT NULL DEFAULT TRUE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );


    CREATE TABLE IF NOT EXISTS restaurants (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT NOT NULL,
      image TEXT NOT NULL,
      rating NUMERIC(2,1) NOT NULL CHECK (rating BETWEEN 0 AND 5),
      distance TEXT NOT NULL,
      price TEXT NOT NULL,
      address TEXT NOT NULL DEFAULT '',
      phone TEXT NOT NULL DEFAULT '',
      hours TEXT NOT NULL DEFAULT '',
      menu TEXT NOT NULL DEFAULT '',
      website TEXT NOT NULL DEFAULT '',
      latitude DOUBLE PRECISION,
      longitude DOUBLE PRECISION,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS address TEXT NOT NULL DEFAULT '';
    ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS phone TEXT NOT NULL DEFAULT '';
    ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS hours TEXT NOT NULL DEFAULT '';
    ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS menu TEXT NOT NULL DEFAULT '';
    ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS website TEXT NOT NULL DEFAULT '';
    ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
    ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
    ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS is_verified BOOLEAN NOT NULL DEFAULT FALSE;
    ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS owner_note TEXT NOT NULL DEFAULT '';


    CREATE TABLE IF NOT EXISTS restaurant_claims (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      business_name TEXT NOT NULL CHECK (char_length(business_name) BETWEEN 1 AND 160),
      role TEXT NOT NULL CHECK (role IN ('owner','manager','staff')),
      note TEXT NOT NULL DEFAULT '' CHECK (char_length(note) <= 1000),
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected')),
      reviewed_at TIMESTAMPTZ,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (restaurant_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS restaurant_owners (
      restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role TEXT NOT NULL DEFAULT 'owner' CHECK (role IN ('owner','manager','staff')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (restaurant_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS restaurant_menu_items (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
      name TEXT NOT NULL CHECK (char_length(name) BETWEEN 1 AND 120),
      description TEXT NOT NULL DEFAULT '' CHECK (char_length(description) <= 500),
      category TEXT NOT NULL DEFAULT 'Menu' CHECK (char_length(category) <= 80),
      price INTEGER NOT NULL DEFAULT 0 CHECK (price >= 0),
      image TEXT NOT NULL DEFAULT '',
      is_available BOOLEAN NOT NULL DEFAULT TRUE,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS restaurant_posts (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
      author_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      caption TEXT NOT NULL CHECK (char_length(caption) BETWEEN 1 AND 1000),
      image TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS smart_events (
      id BIGSERIAL PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      event_type TEXT NOT NULL CHECK (event_type IN ('view','search','save','unsave','collection_add','review','checkin','recommendation_open')),
      restaurant_id TEXT REFERENCES restaurants(id) ON DELETE SET NULL,
      query TEXT NOT NULL DEFAULT '',
      weight NUMERIC(4,2) NOT NULL DEFAULT 1,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS collection_restaurants (
      collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
      restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (collection_id,restaurant_id)
    );


    CREATE TABLE IF NOT EXISTS collection_members (
      collection_id UUID NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role TEXT NOT NULL DEFAULT 'viewer' CHECK (role IN ('editor','viewer')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (collection_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS dining_plans (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      host_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 100),
      note TEXT NOT NULL DEFAULT '' CHECK (char_length(note) <= 500),
      scheduled_at TIMESTAMPTZ NOT NULL,
      status TEXT NOT NULL DEFAULT 'planned' CHECK (status IN ('planned','completed','cancelled')),
      selected_restaurant_id TEXT REFERENCES restaurants(id) ON DELETE SET NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS dining_plan_members (
      plan_id UUID NOT NULL REFERENCES dining_plans(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rsvp TEXT NOT NULL DEFAULT 'pending' CHECK (rsvp IN ('pending','going','maybe','declined')),
      invited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      responded_at TIMESTAMPTZ,
      PRIMARY KEY (plan_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS dining_plan_candidates (
      plan_id UUID NOT NULL REFERENCES dining_plans(id) ON DELETE CASCADE,
      restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
      proposed_by UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (plan_id,restaurant_id)
    );

    CREATE TABLE IF NOT EXISTS dining_plan_votes (
      plan_id UUID NOT NULL,
      restaurant_id TEXT NOT NULL,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (plan_id,user_id),
      FOREIGN KEY (plan_id,restaurant_id) REFERENCES dining_plan_candidates(plan_id,restaurant_id) ON DELETE CASCADE
    );

    CREATE TABLE IF NOT EXISTS live_activity_tokens (
      activity_token TEXT PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      plan_id UUID NOT NULL REFERENCES dining_plans(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (user_id,plan_id)
    );

    CREATE INDEX IF NOT EXISTS live_activity_tokens_plan_idx ON live_activity_tokens(plan_id);

    CREATE TABLE IF NOT EXISTS dining_plan_messages (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      plan_id UUID NOT NULL REFERENCES dining_plans(id) ON DELETE CASCADE,
      sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS dining_plan_photos (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      plan_id UUID NOT NULL REFERENCES dining_plans(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      image TEXT NOT NULL CHECK (char_length(image) <= 7000000),
      caption TEXT NOT NULL DEFAULT '' CHECK (char_length(caption) <= 240),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS stories (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      media_type TEXT NOT NULL DEFAULT 'photo' CHECK (media_type IN ('photo','text')),
      media TEXT NOT NULL DEFAULT '',
      caption TEXT NOT NULL DEFAULT '' CHECK (char_length(caption) <= 500),
      location_name TEXT NOT NULL DEFAULT '',
      location_address TEXT NOT NULL DEFAULT '',
      latitude DOUBLE PRECISION,
      longitude DOUBLE PRECISION,
      visibility TEXT NOT NULL DEFAULT 'everyone' CHECK (visibility IN ('everyone','friends','close_foodies','selected','only_me')),
      tagged_user_ids UUID[] NOT NULL DEFAULT '{}',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '24 hours')
    );

    CREATE TABLE IF NOT EXISTS story_audience (
      story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      PRIMARY KEY (story_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS story_views (
      story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (story_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS story_reactions (
      story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      reaction TEXT NOT NULL CHECK (reaction IN ('love','yummy','fire','wow')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (story_id,user_id)
    );

    ALTER TABLE stories ADD COLUMN IF NOT EXISTS poll_question TEXT NOT NULL DEFAULT '';
    ALTER TABLE stories ADD COLUMN IF NOT EXISTS poll_option_a TEXT NOT NULL DEFAULT '';
    ALTER TABLE stories ADD COLUMN IF NOT EXISTS poll_option_b TEXT NOT NULL DEFAULT '';

    CREATE TABLE IF NOT EXISTS story_poll_votes (
      story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      option_key TEXT NOT NULL CHECK (option_key IN ('a','b')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (story_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS story_highlights (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title TEXT NOT NULL CHECK (char_length(title) BETWEEN 1 AND 40),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS story_highlight_items (
      highlight_id UUID NOT NULL REFERENCES story_highlights(id) ON DELETE CASCADE,
      story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (highlight_id,story_id)
    );

    CREATE TABLE IF NOT EXISTS moments (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      author TEXT NOT NULL,
      caption TEXT NOT NULL CHECK (char_length(caption) BETWEEN 1 AND 500),
      restaurant_id TEXT REFERENCES restaurants(id) ON DELETE SET NULL,
      image TEXT NOT NULL DEFAULT 'Noodles',
      likes INTEGER NOT NULL DEFAULT 0 CHECK (likes >= 0),
      user_id UUID REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES users(id) ON DELETE CASCADE;
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS moment_type TEXT NOT NULL DEFAULT 'photo';
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS location_name TEXT NOT NULL DEFAULT '';
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS location_address TEXT NOT NULL DEFAULT '';
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS visibility TEXT NOT NULL DEFAULT 'everyone';
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS tagged_user_ids UUID[] NOT NULL DEFAULT '{}';
    ALTER TABLE moments ADD COLUMN IF NOT EXISTS plan_id UUID REFERENCES dining_plans(id) ON DELETE SET NULL;
    ALTER TABLE moments DROP CONSTRAINT IF EXISTS moments_moment_type_check;
    ALTER TABLE moments ADD CONSTRAINT moments_moment_type_check CHECK (moment_type IN ('photo','checkin','eating','cooking','craving','thought'));
    ALTER TABLE moments DROP CONSTRAINT IF EXISTS moments_visibility_check;
    ALTER TABLE moments ADD CONSTRAINT moments_visibility_check CHECK (visibility IN ('everyone','friends','close_foodies','selected','only_me'));

    CREATE TABLE IF NOT EXISTS close_foodies (
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      member_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id,member_id),
      CHECK (user_id <> member_id)
    );

    CREATE TABLE IF NOT EXISTS moment_audience (
      moment_id UUID NOT NULL REFERENCES moments(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      PRIMARY KEY (moment_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS moment_reactions (
      moment_id UUID NOT NULL REFERENCES moments(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      reaction TEXT NOT NULL CHECK (reaction IN ('love','yummy','fire','wow')),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (moment_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS moment_likes (
      moment_id UUID NOT NULL REFERENCES moments(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (moment_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS comments (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      moment_id UUID NOT NULL REFERENCES moments(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 500),
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS messages (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      sender_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
      is_read BOOLEAN NOT NULL DEFAULT FALSE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      CHECK (sender_id <> receiver_id)
    );
    ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_read BOOLEAN NOT NULL DEFAULT FALSE;

    CREATE TABLE IF NOT EXISTS saved_restaurants (
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (user_id,restaurant_id)
    );

    CREATE TABLE IF NOT EXISTS notifications (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      actor_id UUID REFERENCES users(id) ON DELETE CASCADE,
      type TEXT NOT NULL,
      moment_id UUID REFERENCES moments(id) ON DELETE CASCADE,
      plan_id UUID REFERENCES dining_plans(id) ON DELETE CASCADE,
      body TEXT NOT NULL,
      is_read BOOLEAN NOT NULL DEFAULT FALSE,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    ALTER TABLE notifications ADD COLUMN IF NOT EXISTS plan_id UUID REFERENCES dining_plans(id) ON DELETE CASCADE;
    ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
    ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN ('follow','like','comment','message','recommendation','together'));

    CREATE TABLE IF NOT EXISTS restaurant_reviews (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      restaurant_id TEXT NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
      body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
      photo TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (restaurant_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS place_reviews (
      id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
      place_id TEXT NOT NULL,
      place_name TEXT NOT NULL,
      address TEXT NOT NULL DEFAULT '',
      latitude DOUBLE PRECISION,
      longitude DOUBLE PRECISION,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      rating INTEGER NOT NULL CHECK (rating BETWEEN 1 AND 5),
      body TEXT NOT NULL CHECK (char_length(body) BETWEEN 1 AND 1000),
      photo TEXT NOT NULL DEFAULT '',
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      UNIQUE (place_id,user_id)
    );

    CREATE TABLE IF NOT EXISTS device_tokens (
      device_token TEXT PRIMARY KEY,
      user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      platform TEXT NOT NULL DEFAULT 'ios',
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE INDEX IF NOT EXISTS auth_codes_user_idx ON auth_codes(user_id,purpose,created_at DESC);
    CREATE INDEX IF NOT EXISTS place_reviews_place_idx ON place_reviews(place_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS notifications_user_created_idx ON notifications(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS stories_active_idx ON stories(expires_at DESC,created_at DESC);
    CREATE INDEX IF NOT EXISTS stories_user_created_idx ON stories(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS story_audience_user_idx ON story_audience(user_id,story_id);
    CREATE INDEX IF NOT EXISTS story_views_story_idx ON story_views(story_id,viewed_at DESC);
    CREATE INDEX IF NOT EXISTS story_reactions_story_idx ON story_reactions(story_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS story_poll_votes_story_idx ON story_poll_votes(story_id,option_key);
    CREATE INDEX IF NOT EXISTS story_highlights_user_idx ON story_highlights(user_id,updated_at DESC);
    CREATE INDEX IF NOT EXISTS story_highlight_items_idx ON story_highlight_items(highlight_id,sort_order,created_at);
    CREATE INDEX IF NOT EXISTS moments_user_created_idx ON moments(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS close_foodies_user_idx ON close_foodies(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS moment_audience_user_idx ON moment_audience(user_id,moment_id);
    CREATE INDEX IF NOT EXISTS moment_reactions_moment_idx ON moment_reactions(moment_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS comments_moment_created_idx ON comments(moment_id,created_at);
    CREATE INDEX IF NOT EXISTS messages_participants_idx ON messages(sender_id,receiver_id,created_at);
    CREATE INDEX IF NOT EXISTS messages_unread_idx ON messages(receiver_id,is_read,created_at DESC);
    CREATE INDEX IF NOT EXISTS follow_requests_target_idx ON follow_requests(target_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS blocks_blocked_idx ON blocks(blocked_id,blocker_id);
    CREATE INDEX IF NOT EXISTS reports_status_created_idx ON reports(status,created_at DESC);
    CREATE INDEX IF NOT EXISTS collections_user_idx ON collections(user_id,updated_at DESC);
    CREATE INDEX IF NOT EXISTS collection_restaurants_collection_idx ON collection_restaurants(collection_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS collection_members_user_idx ON collection_members(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS dining_plans_host_idx ON dining_plans(host_id,scheduled_at DESC);
    CREATE INDEX IF NOT EXISTS dining_plan_members_user_idx ON dining_plan_members(user_id,invited_at DESC);
    CREATE INDEX IF NOT EXISTS dining_plan_candidates_plan_idx ON dining_plan_candidates(plan_id,created_at);
    CREATE INDEX IF NOT EXISTS dining_plan_messages_plan_idx ON dining_plan_messages(plan_id,created_at);
    CREATE INDEX IF NOT EXISTS dining_plan_photos_plan_idx ON dining_plan_photos(plan_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS restaurant_claims_user_idx ON restaurant_claims(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS restaurant_claims_status_idx ON restaurant_claims(status,created_at DESC);
    CREATE INDEX IF NOT EXISTS restaurant_owners_user_idx ON restaurant_owners(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS restaurant_menu_items_restaurant_idx ON restaurant_menu_items(restaurant_id,sort_order,created_at);
    CREATE INDEX IF NOT EXISTS restaurant_posts_restaurant_idx ON restaurant_posts(restaurant_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS smart_events_user_created_idx ON smart_events(user_id,created_at DESC);
    CREATE INDEX IF NOT EXISTS smart_events_restaurant_idx ON smart_events(restaurant_id,created_at DESC);
  `);

  const values = [
    ["kopi-nok", "Kopi Nok", "Kafe • Sarapan", "Cafe", 4.8, "", "Rp20–45K", "", "", "", "Kopi, sarapan, camilan", "", null, null],
    ["dapur-nusantara", "Dapur Nusantara", "Indonesia • Halal", "FoodHero", 4.9, "", "Rp25–60K", "", "", "", "Nasi nusantara, lauk harian", "", null, null],
    ["mie-ceria", "Mie Ceria", "Mi • Asia", "Noodles", 4.7, "", "Rp18–35K", "", "", "", "Mi ayam, mi goreng", "", null, null],
    ["burger-social", "Burger Social", "Burger • Barat", "Burgers", 4.6, "", "Rp35–80K", "", "", "", "Burger, kentang, minuman", "", null, null]
  ];
  for (const row of values) {
    await pool.query(
      `INSERT INTO restaurants (id,name,category,image,rating,distance,price,address,phone,hours,menu,website,latitude,longitude)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14) ON CONFLICT (id) DO NOTHING`, row
    );
  }
}
