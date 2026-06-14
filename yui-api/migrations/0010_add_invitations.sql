-- 招待（発起人 → ユーザー）
CREATE TABLE IF NOT EXISTS invitations (
    id TEXT PRIMARY KEY,
    slot_id TEXT NOT NULL,
    inviter_id TEXT NOT NULL,   -- 招待した発起人
    invitee_id TEXT NOT NULL,   -- 招待されたユーザー
    status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending', 'accepted', 'declined')),
    message TEXT,               -- 招待時に添えるメッセージ（任意）
    response_message TEXT,      -- 招待された側の回答メッセージ（任意）
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    FOREIGN KEY (slot_id) REFERENCES slots(id),
    FOREIGN KEY (inviter_id) REFERENCES users(id),
    FOREIGN KEY (invitee_id) REFERENCES users(id)
);

-- 同じ枠×同じ相手の重複招待を防ぐ
CREATE UNIQUE INDEX IF NOT EXISTS idx_invitations_slot_invitee
    ON invitations(slot_id, invitee_id);
