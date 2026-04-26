import { Hono } from 'hono';
import { hashPassword } from '../lib/auth';
import { requireAuth, requireAdmin } from '../lib/middleware';

export const userRoutes = new Hono<{ Bindings: Env }>();

// POST /users
// 管理者のみ: 出店者アカウントを新規作成
userRoutes.post('/', async (c) => {
	const admin = await requireAdmin(c);
	if (!admin) return c.res;

	const { email, password, shop_name } = await c.req.json();

	if (!email || !password) {
		return c.json({ error: 'メールアドレスとパスワードは必須です' }, 400);
	}
	if (password.length < 8) {
		return c.json({ error: 'パスワードは8文字以上にしてください' }, 400);
	}

	// メールアドレスの重複チェック
	const existing = await c.env.umeyui_db.prepare('SELECT id FROM users WHERE email = ?').bind(email).first();

	if (existing) {
		return c.json({ error: 'このメールアドレスはすでに使用されています' }, 409);
	}

	const id = crypto.randomUUID();
	const password_hash = await hashPassword(password);

	await c.env.umeyui_db
		.prepare('INSERT INTO users (id, email, password_hash, role, shop_name, is_active) VALUES (?, ?, ?, ?, ?, 1)')
		.bind(id, email, password_hash, 'vendor', shop_name ?? null)
		.run();

	return c.json({ id, email, shop_name: shop_name ?? null, role: 'vendor' }, 201);
});

// GET /users
// 管理者のみ: 出店者一覧を取得
userRoutes.get('/', async (c) => {
	const admin = await requireAdmin(c);
	if (!admin) return c.res;

	const { results } = await c.env.umeyui_db
		.prepare(
			"SELECT id, email, role, shop_name, bio, homepage_bio, category, avatar_url, homepage_avatar_url, website_url, instagram_url, x_url, line_url, facebook_url, is_active, created_at FROM users WHERE id != 'system' ORDER BY created_at DESC",
		)
		.all();

	return c.json(results);
});

// GET /users/:id
// 認証済みユーザー全員: プロフィール取得（チャット・カレンダーから他ユーザーを閲覧するため）
userRoutes.get('/:id', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	const isSelfOrAdmin = authUser.sub === id || authUser.role === 'admin';

	const user = await c.env.umeyui_db
		.prepare(
			isSelfOrAdmin
				? 'SELECT id, email, role, shop_name, bio, homepage_bio, category, avatar_url, homepage_avatar_url, website_url, instagram_url, x_url, line_url, facebook_url, is_active, created_at FROM users WHERE id = ?'
				: 'SELECT id, email, role, shop_name, bio, category, avatar_url, website_url, instagram_url, x_url, line_url, facebook_url, is_active, created_at FROM users WHERE id = ?',
		)
		.bind(id)
		.first();

	if (!user) return c.json({ error: 'ユーザーが見つかりません' }, 404);

	return c.json(user);
});

// PATCH /users/:id
// 管理者 or 本人: プロフィール編集（屋号・自己紹介）
userRoutes.patch('/:id', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	if (authUser.sub !== id && authUser.role !== 'admin') {
		return c.json({ error: '権限がありません' }, 403);
	}

	const body = await c.req.json();

	// 送られてきたフィールドだけ UPDATE する（未送信フィールドは既存値を維持）
	const allowedFields = ['shop_name', 'bio', 'homepage_bio', 'category', 'website_url', 'instagram_url', 'x_url', 'line_url', 'facebook_url'] as const;
	const updates = allowedFields.filter((f) => f in body);

	if (updates.length === 0) {
		return c.json({ message: 'プロフィールを更新しました' });
	}

	const setClauses = updates.map((f) => `${f} = ?`).join(', ');
	const values = [...updates.map((f) => (body[f] === '' ? null : (body[f] ?? null))), id];

	await c.env.umeyui_db
		.prepare(`UPDATE users SET ${setClauses} WHERE id = ?`)
		.bind(...values)
		.run();

	if (!(authUser.is_test ?? false) && c.env.VERCEL_DEPLOY_HOOK_URL) {
		await fetch(c.env.VERCEL_DEPLOY_HOOK_URL, { method: 'POST' }).catch(() => {});
	}

	return c.json({ message: 'プロフィールを更新しました' });
});

// PATCH /users/:id/active
// 管理者のみ: アカウント有効/無効切り替え
userRoutes.patch('/:id/active', async (c) => {
	const admin = await requireAdmin(c);
	if (!admin) return c.res;

	const { id } = c.req.param();
	if (admin.sub === id) {
		return c.json({ error: '自分自身のアカウントは無効化できません' }, 400);
	}
	const { is_active } = await c.req.json();

	if (typeof is_active !== 'number' || (is_active !== 0 && is_active !== 1)) {
		return c.json({ error: 'is_active は 0 か 1 を指定してください' }, 400);
	}

	await c.env.umeyui_db.prepare('UPDATE users SET is_active = ? WHERE id = ?').bind(is_active, id).run();

	return c.json({ message: is_active === 1 ? 'アカウントを有効化しました' : 'アカウントを無効化しました' });
});

// PATCH /users/:id/push-token
// 本人のみ: デバイスのFCMトークンを登録・更新（複数デバイス対応）
userRoutes.patch('/:id/push-token', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	if (authUser.sub !== id) {
		return c.json({ error: '権限がありません' }, 403);
	}

	const { push_token } = await c.req.json();
	if (!push_token) {
		return c.json({ error: 'push_token は必須です' }, 400);
	}

	await c.env.umeyui_db
		.prepare(
			`INSERT INTO fcm_tokens (id, user_id, token, updated_at)
       VALUES (?, ?, ?, CURRENT_TIMESTAMP)
       ON CONFLICT(token) DO UPDATE SET user_id = ?, updated_at = CURRENT_TIMESTAMP`,
		)
		.bind(crypto.randomUUID(), id, push_token, id)
		.run();

	return c.json({ message: 'プッシュトークンを更新しました' });
});

// PATCH /users/:id/email
// 管理者のみ: 出店者のメールアドレスを直接変更（ハッキング等の復旧用）
userRoutes.patch('/:id/email', async (c) => {
	const admin = await requireAdmin(c);
	if (!admin) return c.res;

	const { id } = c.req.param();
	const { new_email } = await c.req.json();

	if (!new_email) return c.json({ error: '新しいメールアドレスを入力してください' }, 400);

	if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(new_email)) {
		return c.json({ error: 'メールアドレスの形式が正しくありません' }, 400);
	}

	const user = await c.env.umeyui_db.prepare('SELECT id FROM users WHERE id = ? AND role = ?').bind(id, 'vendor').first();
	if (!user) return c.json({ error: '出店者が見つかりません' }, 404);

	const existing = await c.env.umeyui_db.prepare('SELECT id FROM users WHERE email = ? AND id != ?').bind(new_email, id).first();
	if (existing) return c.json({ error: 'このメールアドレスはすでに使用されています' }, 409);

	// token_versionインクリメントで既存セッションを無効化
	await c.env.umeyui_db.prepare('UPDATE users SET email = ?, token_version = token_version + 1 WHERE id = ?').bind(new_email, id).run();

	return c.json({ message: 'メールアドレスを変更しました' });
});

// PATCH /users/:id/reset-password
// 管理者のみ: 出店者のパスワードを強制リセット（現在のパスワード不要）
userRoutes.patch('/:id/reset-password', async (c) => {
	const admin = await requireAdmin(c);
	if (!admin) return c.res;

	const { id } = c.req.param();
	const { new_password } = await c.req.json();

	if (!new_password || new_password.length < 8) {
		return c.json({ error: 'パスワードは8文字以上にしてください' }, 400);
	}

	const user = await c.env.umeyui_db.prepare('SELECT id FROM users WHERE id = ? AND role = ?').bind(id, 'vendor').first();

	if (!user) {
		return c.json({ error: '出店者が見つかりません' }, 404);
	}

	const newHash = await hashPassword(new_password);
	// token_versionもインクリメントして既存セッションを無効化
	await c.env.umeyui_db
		.prepare('UPDATE users SET password_hash = ?, token_version = token_version + 1 WHERE id = ?')
		.bind(newHash, id)
		.run();

	return c.json({ message: 'パスワードをリセットしました' });
});

// POST /users/:id/avatar
// 本人 or 管理者: アバター画像をアップロード → R2 に保存して avatar_url を更新
userRoutes.post('/:id/avatar', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	if (authUser.sub !== id && authUser.role !== 'admin') {
		return c.json({ error: '権限がありません' }, 403);
	}

	const formData = await c.req.formData();
	const file = formData.get('avatar') as File | null;

	if (!file) {
		return c.json({ error: 'avatar フィールドに画像ファイルを指定してください' }, 400);
	}
	if (!file.type.startsWith('image/')) {
		return c.json({ error: '画像ファイル（JPEG / PNG / WebP）のみアップロードできます' }, 400);
	}
	if (file.size > 5 * 1024 * 1024) {
		return c.json({ error: 'ファイルサイズは 5MB 以下にしてください' }, 400);
	}

	const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
	const key = `avatars/${id}.${ext}`;

	await c.env.AVATAR_BUCKET.put(key, await file.arrayBuffer(), {
		httpMetadata: { contentType: file.type },
	});

	// 以前の拡張子が異なる場合は古いオブジェクトを削除
	for (const oldExt of ['jpg', 'png', 'webp']) {
		if (oldExt !== ext) {
			await c.env.AVATAR_BUCKET.delete(`avatars/${id}.${oldExt}`);
		}
	}

	const avatarUrl = `/avatars/${id}.${ext}`;

	await c.env.umeyui_db.prepare('UPDATE users SET avatar_url = ? WHERE id = ?').bind(avatarUrl, id).run();

	if (!(authUser.is_test ?? false) && c.env.VERCEL_DEPLOY_HOOK_URL) {
		await fetch(c.env.VERCEL_DEPLOY_HOOK_URL, { method: 'POST' }).catch(() => {});
	}

	return c.json({ avatar_url: avatarUrl });
});

// POST /users/:id/homepage-avatar
// 本人のみ: ホームページ用縦長プロフィール画像をアップロード
userRoutes.post('/:id/homepage-avatar', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	if (authUser.sub !== id) {
		return c.json({ error: '権限がありません' }, 403);
	}

	const formData = await c.req.formData();
	const file = formData.get('image') as File | null;

	if (!file) {
		return c.json({ error: 'image フィールドに画像ファイルを指定してください' }, 400);
	}
	if (!file.type.startsWith('image/')) {
		return c.json({ error: '画像ファイル（JPEG / PNG / WebP）のみアップロードできます' }, 400);
	}
	if (file.size > 10 * 1024 * 1024) {
		return c.json({ error: 'ファイルサイズは 10MB 以下にしてください' }, 400);
	}

	const ext = file.type === 'image/png' ? 'png' : file.type === 'image/webp' ? 'webp' : 'jpg';
	const key = `homepage-avatars/${id}.${ext}`;

	await c.env.AVATAR_BUCKET.put(key, await file.arrayBuffer(), {
		httpMetadata: { contentType: file.type },
	});

	for (const oldExt of ['jpg', 'png', 'webp']) {
		if (oldExt !== ext) {
			await c.env.AVATAR_BUCKET.delete(`homepage-avatars/${id}.${oldExt}`);
		}
	}

	const homepageAvatarUrl = `/homepage-avatars/${id}.${ext}`;
	await c.env.umeyui_db.prepare('UPDATE users SET homepage_avatar_url = ? WHERE id = ?').bind(homepageAvatarUrl, id).run();

	if (!(authUser.is_test ?? false) && c.env.VERCEL_DEPLOY_HOOK_URL) {
		await fetch(c.env.VERCEL_DEPLOY_HOOK_URL, { method: 'POST' }).catch(() => {});
	}

	return c.json({ homepage_avatar_url: homepageAvatarUrl });
});

// DELETE /users/:id
// 管理者のみ: アカウント削除（関連する予約・枠・チャットルームも整合性を保って処理）
userRoutes.delete('/:id', async (c) => {
	const admin = await requireAdmin(c);
	if (!admin) return c.res;

	const { id } = c.req.param();

	// 管理者自身は削除不可
	if (admin.sub === id) {
		return c.json({ error: '自分自身のアカウントは削除できません' }, 400);
	}

	const db = c.env.umeyui_db;

	// このユーザーの有効な予約を全取得
	const { results: activeReservations } = await db
		.prepare("SELECT id, slot_id, is_initiator FROM reservations WHERE user_id = ? AND status != 'cancelled'")
		.bind(id)
		.all<{ id: string; slot_id: string; is_initiator: number }>();

	for (const res of activeReservations) {
		if (res.is_initiator === 1) {
			// 発起人の場合: 枠全体をキャンセルして open に戻す
			const chatRoom = await db.prepare('SELECT id FROM chat_rooms WHERE slot_id = ?').bind(res.slot_id).first<{ id: string }>();

			const batchOps: D1PreparedStatement[] = [
				db.prepare("UPDATE reservations SET status = 'cancelled' WHERE slot_id = ? AND status != 'cancelled'").bind(res.slot_id),
				db.prepare("UPDATE slots SET status = 'open', min_vendors = NULL, max_vendors = NULL WHERE id = ?").bind(res.slot_id),
				db.prepare("UPDATE join_requests SET status = 'rejected' WHERE slot_id = ? AND status = 'pending'").bind(res.slot_id),
			];
			if (chatRoom) {
				batchOps.push(db.prepare('DELETE FROM messages WHERE room_id = ?').bind(chatRoom.id));
				batchOps.push(db.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(chatRoom.id));
			}
			await db.batch(batchOps);
		} else {
			// 非発起人: 自分の予約だけキャンセル
			await db.prepare("UPDATE reservations SET status = 'cancelled' WHERE id = ?").bind(res.id).run();

			const countResult = await db
				.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
				.bind(res.slot_id)
				.first<{ count: number }>();
			const remaining = countResult?.count ?? 0;

			const slot = await db
				.prepare('SELECT min_vendors, status FROM slots WHERE id = ?')
				.bind(res.slot_id)
				.first<{ min_vendors: number | null; status: string }>();

			if (remaining === 0) {
				// 全員いなくなった → open に戻す
				const chatRoom = await db.prepare('SELECT id FROM chat_rooms WHERE slot_id = ?').bind(res.slot_id).first<{ id: string }>();
				const ops: D1PreparedStatement[] = [
					db.prepare("UPDATE slots SET status = 'open', min_vendors = NULL, max_vendors = NULL WHERE id = ?").bind(res.slot_id),
				];
				if (chatRoom) {
					ops.push(db.prepare('DELETE FROM messages WHERE room_id = ?').bind(chatRoom.id));
					ops.push(db.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(chatRoom.id));
				}
				await db.batch(ops);
			} else if (slot && slot.min_vendors !== null && remaining < slot.min_vendors) {
				// min を下回った → recruiting に戻す
				if (slot.status === 'confirmed') {
					const chatRoom = await db.prepare('SELECT id FROM chat_rooms WHERE slot_id = ?').bind(res.slot_id).first<{ id: string }>();
					if (chatRoom) {
						await db.batch([
							db.prepare('DELETE FROM messages WHERE room_id = ?').bind(chatRoom.id),
							db.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(chatRoom.id),
						]);
					}
				}
				await db.batch([
					db.prepare("UPDATE slots SET status = 'recruiting' WHERE id = ?").bind(res.slot_id),
					db.prepare("UPDATE reservations SET status = 'pending' WHERE slot_id = ? AND status = 'confirmed'").bind(res.slot_id),
				]);
			}
		}
	}

	// FK制約のある行を削除してからユーザー削除
	// reservations と messages は FOREIGN KEY (user_id) REFERENCES users(id) があるため DELETE が必要
	await db.batch([
		db.prepare('DELETE FROM reservations WHERE user_id = ?').bind(id),
		db.prepare('DELETE FROM messages WHERE user_id = ?').bind(id),
	]);
	// FK制約なし（クリーンアップのみ）
	await db.batch([
		db.prepare('DELETE FROM join_requests WHERE requester_id = ?').bind(id),
		db.prepare('DELETE FROM notifications WHERE user_id = ?').bind(id),
	]);

	// ユーザー削除
	await db.prepare('DELETE FROM users WHERE id = ?').bind(id).run();

	return c.json({ message: 'アカウントを削除しました' });
});
