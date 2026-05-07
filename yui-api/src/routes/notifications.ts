import { Hono } from 'hono';
import { requireAdmin, requireAuth } from '../lib/middleware';
import { sendPushToUser } from '../lib/fcm';

export const notificationRoutes = new Hono<{ Bindings: Env }>();

// GET /notifications
// 自分宛の通知一覧（未読優先・最大100件）
notificationRoutes.get('/', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { results } = await c.env.umeyui_db
		.prepare(
			`
      SELECT id, type, slot_id, message, is_read, created_at
      FROM notifications
      WHERE user_id = ?
      ORDER BY is_read ASC, created_at DESC
      LIMIT 100
    `,
		)
		.bind(authUser.sub)
		.all();

	return c.json(results);
});

// POST /notifications/broadcast（管理者のみ）
// 全アクティブ出店者にお知らせ通知＋プッシュ通知を送信
notificationRoutes.post('/broadcast', async (c) => {
	const authUser = await requireAdmin(c);
	if (!authUser) return c.res;

	const { title, body } = await c.req.json<{ title?: string; body?: string }>();
	if (!title?.trim() || !body?.trim()) {
		return c.json({ error: 'タイトルと本文は必須です' }, 400);
	}

	const { results: vendors } = await c.env.umeyui_db
		.prepare("SELECT id FROM users WHERE role = 'vendor' AND is_active = 1")
		.all<{ id: string }>();

	if (vendors.length === 0) {
		return c.json({ message: '送信対象のユーザーがいません', count: 0 });
	}

	const now = new Date().toISOString();
	await Promise.all(
		vendors.map((v) =>
			c.env.umeyui_db
				.prepare("INSERT INTO notifications (id, user_id, type, message, is_read, created_at) VALUES (?, ?, 'announcement', ?, 0, ?)")
				.bind(crypto.randomUUID(), v.id, body.trim(), now)
				.run(),
		),
	);

	await Promise.all(vendors.map((v) => sendPushToUser(c.env, v.id, title.trim(), body.trim())));

	return c.json({ message: `${vendors.length}人に送信しました`, count: vendors.length });
});

// PATCH /notifications/read-all
// 全通知を既読にする
notificationRoutes.patch('/read-all', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	await c.env.umeyui_db
		.prepare('UPDATE notifications SET is_read = 1 WHERE user_id = ?')
		.bind(authUser.sub)
		.run();

	return c.json({ message: '既読にしました' });
});
