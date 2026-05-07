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

	const todayJst = toJstDate(0);
	const yesterdayJst = toJstDate(-1);
	const sevenDaysAgoJst = toJstDate(-7);

	// --- 過去の recruiting スロット: 参加者に「最低人数未達で中止」を通知してから削除 ---
	const { results: expiredRecruitingSlots } = await env.umeyui_db
		.prepare("SELECT id, date, name FROM slots WHERE date < ? AND status = 'recruiting'")
		.bind(todayJst)
		.all<{ id: string; date: string; name: string | null }>();

	for (const slot of expiredRecruitingSlots) {
		const { results: participants } = await env.umeyui_db
			.prepare("SELECT user_id FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(slot.id)
			.all<{ user_id: string }>();

		if (participants.length > 0) {
			const label = slot.name ?? slot.date;
			const message = `${label}の出店枠は最低人数に達しなかったため、中止となりました。`;
			const now = new Date().toISOString();

			// slot_id は null（スロットを削除するため FK 参照しない）
			await Promise.all(
				participants.map((p) =>
					env.umeyui_db
						.prepare("INSERT INTO notifications (id, user_id, type, message, is_read, created_at) VALUES (?, ?, 'slot_cancelled', ?, 0, ?)")
						.bind(crypto.randomUUID(), p.user_id, message, now)
						.run(),
				),
			);
			await Promise.all(participants.map((p) => sendPushToUser(env, p.user_id, '出店枠の中止', message)));
		}

		await env.umeyui_db.batch([
			env.umeyui_db.prepare('DELETE FROM join_requests WHERE slot_id = ?').bind(slot.id),
			env.umeyui_db.prepare('DELETE FROM notifications WHERE slot_id = ?').bind(slot.id),
			env.umeyui_db.prepare('DELETE FROM reservations WHERE slot_id = ?').bind(slot.id),
		]);
		await env.umeyui_db.prepare('DELETE FROM slots WHERE id = ?').bind(slot.id).run();
	}

	// --- 過去の open スロット: 誰も予約していないため黙って削除 ---
	const { results: expiredOpenSlots } = await env.umeyui_db
		.prepare("SELECT id FROM slots WHERE date < ? AND status = 'open'")
		.bind(todayJst)
		.all<{ id: string }>();

	if (expiredOpenSlots.length > 0) {
		await env.umeyui_db.batch(
			expiredOpenSlots.map((s) => env.umeyui_db.prepare('DELETE FROM slots WHERE id = ?').bind(s.id)),
		);
	}

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