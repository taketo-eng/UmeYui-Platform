-- users に token_version カラムを追加（ログアウト時のトークン無効化に使用）
ALTER TABLE users ADD COLUMN token_version INTEGER NOT NULL DEFAULT 0;

-- slots に description カラムを追加
ALTER TABLE slots ADD COLUMN description TEXT;

-- ログイン試行ログ（レート制限用）
CREATE TABLE IF NOT EXISTS login_attempts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ip TEXT NOT NULL,
    attempted_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- アプリ内通知
CREATE TABLE IF NOT EXISTS notifications (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    type TEXT NOT NULL,
    slot_id TEXT,
    message TEXT NOT NULL,
    is_read INTEGER NOT NULL DEFAULT 0,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (slot_id) REFERENCES slots(id)
);

-- 参加申請
CREATE TABLE IF NOT EXISTS join_requests (
    id TEXT PRIMARY KEY,
    slot_id TEXT NOT NULL,
    requester_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'approved', 'rejected')),
    message TEXT,
    response_message TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (slot_id) REFERENCES slots(id),
    FOREIGN KEY (requester_id) REFERENCES users(id)
);

-- パスワード変更の確認コード（メール送信フロー用）
CREATE TABLE IF NOT EXISTS password_change_tokens (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE,
    code TEXT NOT NULL,
    new_password_hash TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id)
);

-- チャット既読管理
CREATE TABLE IF NOT EXISTS user_room_reads (
    user_id TEXT NOT NULL,
    room_id TEXT NOT NULL,
    last_read_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, room_id),
    FOREIGN KEY (user_id) REFERENCES users(id),
    FOREIGN KEY (room_id) REFERENCES chat_rooms(id)
);
