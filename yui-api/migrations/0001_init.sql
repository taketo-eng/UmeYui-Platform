-- users table
CREATE TABLE IF NOT EXISTS users (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role TEXT NOT NULL CHECK(role IN ('admin', 'vendor')),
    shop_name TEXT,
    bio TEXT,
    avatar_url TEXT,
    is_active INTEGER NOT NULL DEFAULT 1,
    push_token TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- slots
CREATE TABLE IF NOT EXISTS slots (
    id TEXT PRIMARY KEY,
    date TEXT NOT NULL UNIQUE,
    name TEXT,
    start_time TEXT,
    end_time TEXT,
    min_vendors INTEGER,
    max_vendors INTEGER,
    status TEXT NOT NULL DEFAULT 'open' CHECK(status IN ('open', 'recruiting', 'confirmed', 'cancelled')),
    created_by TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (created_by) REFERENCES users(id)
);

-- reservations
CREATE TABLE IF NOT EXISTS reservations (
    id TEXT PRIMARY KEY,
    slot_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    is_initiator INTEGER NOT NULL DEFAULT 0,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'confirmed', 'cancelled')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    UNIQUE(slot_id, user_id),
    FOREIGN KEY (slot_id) REFERENCES slots(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- chat_rooms
CREATE TABLE IF NOT EXISTS chat_rooms (
    id TEXT PRIMARY KEY,
    slot_id TEXT NOT NULL UNIQUE,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (slot_id) REFERENCES slots(id)
);

-- messages
CREATE TABLE IF NOT EXISTS messages (
    id TEXT PRIMARY KEY,
    room_id TEXT NOT NULL,
    user_id TEXT NOT NULL,
    body TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (room_id) REFERENCES chat_rooms(id),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

