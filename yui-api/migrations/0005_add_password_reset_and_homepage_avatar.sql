-- パスワードリセット用トークンテーブル（未ログイン状態でのリセット用）
CREATE TABLE IF NOT EXISTS password_reset_tokens (
    id TEXT PRIMARY KEY,
    email TEXT NOT NULL,
    code TEXT NOT NULL,
    new_password_hash TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_password_reset_tokens_email ON password_reset_tokens(email);

-- ホームページ用プロフィール画像カラム
ALTER TABLE users ADD COLUMN homepage_avatar_url TEXT;
