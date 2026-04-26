-- systemユーザー（ログイン不可・一覧非表示）
INSERT OR IGNORE INTO users (id, email, password_hash, role, shop_name, is_active)
VALUES ('system', 'system@internal', '', 'vendor', 'システム', 0);
