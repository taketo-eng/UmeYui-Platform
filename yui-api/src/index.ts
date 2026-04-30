import {Hono} from 'hono'
import { authRoutes } from './routes/auth'
import { userRoutes } from './routes/users'
import { slotRoutes } from './routes/slots'
import { reservationRoutes } from './routes/reservations'
import { chatRoutes } from './routes/chat'
import { slotJoinRequestRoutes, joinRequestRoutes } from './routes/join_requests'
import { notificationRoutes } from './routes/notifications'
import { publicRoutes } from './routes/public'
import { sendPushToUser } from './lib/fcm'
import { requireAuth } from './lib/middleware'

const app = new Hono<{ Bindings: Env }>()

app.route('/auth', authRoutes)
app.route('/users', userRoutes)
app.route('/slots', slotRoutes)
app.route('/slots', reservationRoutes)
app.route('/slots', slotJoinRequestRoutes)
app.route('/join-requests', joinRequestRoutes)
app.route('/notifications', notificationRoutes)
app.route('/chat-rooms', chatRoutes)
app.route('/public', publicRoutes)

// GET /avatars/:filename
// 認証不要: R2 からアバター画像を配信
app.get('/avatars/:filename', async (c) => {
	const { filename } = c.req.param()
	const object = await c.env.AVATAR_BUCKET.get(`avatars/${filename}`)

	if (!object) return c.json({ error: 'Not found' }, 404)

	const headers = new Headers()
	object.writeHttpMetadata(headers)
	headers.set('etag', object.httpEtag)
	headers.set('cache-control', 'public, max-age=86400')

	return new Response(object.body, { headers })
})

// GET /chat-images/:filename
// 要認証: R2 からチャット画像を配信（アプリ内限定）
app.get('/chat-images/:filename', async (c) => {
	const user = await requireAuth(c)
	if (!user) return c.res

	const { filename } = c.req.param()
	const object = await c.env.AVATAR_BUCKET.get(`chat-images/${filename}`)

	if (!object) return c.json({ error: 'Not found' }, 404)

	const headers = new Headers()
	object.writeHttpMetadata(headers)
	headers.set('etag', object.httpEtag)
	headers.set('cache-control', 'private, max-age=86400')

	return new Response(object.body, { headers })
})

// GET /homepage-avatars/:filename
// 認証不要: R2 からホームページ用プロフィール画像を配信
app.get('/homepage-avatars/:filename', async (c) => {
	const { filename } = c.req.param()
	const object = await c.env.AVATAR_BUCKET.get(`homepage-avatars/${filename}`)

	if (!object) return c.json({ error: 'Not found' }, 404)

	const headers = new Headers()
	object.writeHttpMetadata(headers)
	headers.set('etag', object.httpEtag)
	headers.set('cache-control', 'public, max-age=86400')

	return new Response(object.body, { headers })
})

async function scheduledHandler(_event: ScheduledEvent, env: Env, _ctx: ExecutionContext) {
	// JST = UTC + 9h
	const nowJst = new Date(Date.now() + 9 * 60 * 60 * 1000);
	const toJstDate = (offsetDays: number) =>
		new Date(nowJst.getTime() + offsetDays * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

	const yesterdayJst = toJstDate(-1);
	const sevenDaysAgoJst = toJstDate(-7);

	// --- Day +1: 開催翌日 → システムメッセージ送信（未送信のルームのみ） ---
	const { results: endingSlots } = await env.umeyui_db
		.prepare(
			`SELECT s.id, cr.id AS room_id
       FROM slots s
       JOIN chat_rooms cr ON cr.slot_id = s.id
       WHERE s.date = ? AND s.status = 'confirmed'
       AND NOT EXISTS (
         SELECT 1 FROM messages WHERE room_id = cr.id AND user_id = 'system'
       )`,
		)
		.bind(yesterdayJst)
		.all<{ id: string; room_id: string }>();

	for (const slot of endingSlots) {
		const msgBody = 'ご参加ありがとうございました。このチャットルームは7日後に削除されます。';

		await env.umeyui_db
			.prepare('INSERT INTO messages (id, room_id, user_id, body) VALUES (?, ?, ?, ?)')
			.bind(crypto.randomUUID(), slot.room_id, 'system', msgBody)
			.run();

		const { results: members } = await env.umeyui_db
			.prepare("SELECT user_id FROM reservations WHERE slot_id = ? AND status = 'confirmed'")
			.bind(slot.id)
			.all<{ user_id: string }>();

		await Promise.all(
			members.map((m) =>
				sendPushToUser(env, m.user_id, 'チャットルーム', msgBody, { type: 'system_message', room_id: slot.room_id }),
			),
		);
	}

	// --- Day +8: チャットルーム削除（開催から7日以上経過かつルームが残っているもの） ---
	const { results: expiredSlots } = await env.umeyui_db
		.prepare(
			`SELECT s.id AS slot_id, cr.id AS room_id
       FROM slots s
       JOIN chat_rooms cr ON cr.slot_id = s.id
       WHERE s.date <= ? AND s.status = 'confirmed'`,
		)
		.bind(sevenDaysAgoJst)
		.all<{ slot_id: string; room_id: string }>();

	for (const slot of expiredSlots) {
		await env.umeyui_db.batch([
			env.umeyui_db.prepare('DELETE FROM user_room_reads WHERE room_id = ?').bind(slot.room_id),
			env.umeyui_db.prepare('DELETE FROM messages WHERE room_id = ?').bind(slot.room_id),
			env.umeyui_db.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(slot.room_id),
		]);
	}
}

export default {
	fetch: app.fetch,
	scheduled: scheduledHandler,
}