import { Hono } from 'hono';
import { requireAuth } from '../lib/middleware';

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
