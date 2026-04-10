-- メールアドレス変更の確認コード（旧メアドに送って本人確認）
CREATE TABLE IF NOT EXISTS email_change_tokens (
    id TEXT PRIMARY KEY,
    user_id TEXT NOT NULL UNIQUE,
    code TEXT NOT NULL,
    expires_at TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (user_id) REFERENCES users(id)
);
