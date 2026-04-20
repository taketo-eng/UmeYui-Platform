import { Hono } from 'hono';
import { requireAuth } from '../lib/middleware';
import { sendPushToUser } from '../lib/fcm';

export const chatRoutes = new Hono<{ Bindings: Env }>();

// 共通処理: チャットルームへのアクセス権チェック
// confirmed の参加者のみアクセス可能
async function getAccessibleRoom(db: D1Database, roomId: string, userId: string): Promise<{ id: string; slot_id: string } | null> {
	return db
		.prepare(
			`
      SELECT cr.id, cr.slot_id
      FROM chat_rooms cr
      JOIN reservations r ON cr.slot_id = r.slot_id
      WHERE cr.id = ? AND r.user_id = ? AND r.status = 'confirmed'
    `,
		)
		.bind(roomId, userId)
		.first<{ id: string; slot_id: string }>();
}

// GET /chat-rooms
// 自分が参加確定しているチャットルーム一覧
chatRoutes.get('/', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { results } = await c.env.umeyui_db
		.prepare(
			`
      SELECT
        cr.id AS room_id,
        s.id AS slot_id,
        s.date,
        s.name AS slot_name,
        s.start_time,
        s.end_time,
        (SELECT body FROM messages WHERE room_id = cr.id ORDER BY created_at DESC LIMIT 1) AS last_message_body,
        (SELECT created_at FROM messages WHERE room_id = cr.id ORDER BY created_at DESC LIMIT 1) AS last_message_at,
        (SELECT COUNT(*) FROM messages
          WHERE room_id = cr.id
          AND created_at > COALESCE(
            (SELECT last_read_at FROM user_room_reads WHERE user_id = ? AND room_id = cr.id),
            '1970-01-01'
          )
        ) AS unread_count
      FROM chat_rooms cr
      JOIN slots s ON cr.slot_id = s.id
      JOIN reservations r ON cr.slot_id = r.slot_id
      WHERE r.user_id = ? AND r.status = 'confirmed'
      ORDER BY COALESCE(last_message_at, s.date) DESC
    `,
		)
		.bind(authUser.sub, authUser.sub)
		.all();

	// 各ルームの参加者一覧を取得
	const rooms = await Promise.all(
		results.map(async (row: any) => {
			const { results: members } = await c.env.umeyui_db
				.prepare(
					`
          SELECT u.id, u.shop_name, u.avatar_url, r.is_initiator
          FROM users u
          JOIN reservations r ON u.id = r.user_id
          WHERE r.slot_id = ? AND r.status = 'confirmed'
          ORDER BY r.created_at ASC
        `,
				)
				.bind(row.slot_id)
				.all();
			return { ...row, members };
		}),
	);

	return c.json({ rooms });
});

// GET /chat-rooms/:id
// confirmed参加者のみ: ルーム情報を取得
chatRoutes.get('/:id', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	const room = await getAccessibleRoom(c.env.umeyui_db, id, authUser.sub);
	if (!room) {
		return c.json({ error: 'チャットルームが見つかりません、またはアクセス権がありません' }, 404);
	}

	// ルーム情報 + 参加者一覧を返す
	const { results: members } = await c.env.umeyui_db
		.prepare(
			`
      SELECT u.id, u.shop_name, u.avatar_url, r.is_initiator
      FROM users u
      JOIN reservations r ON u.id = r.user_id
      WHERE r.slot_id = ? AND r.status = 'confirmed'
      ORDER BY r.created_at ASC
    `,
		)
		.bind(room.slot_id)
		.all();

	return c.json({ ...room, members });
});

// GET /chat-rooms/:id/messages
// confirmed参加者のみ: メッセージ一覧（ページネーション対応）
chatRoutes.get('/:id/messages', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	const room = await getAccessibleRoom(c.env.umeyui_db, id, authUser.sub);
	if (!room) {
		return c.json({ error: 'チャットルームが見つかりません、またはアクセス権がありません' }, 404);
	}

	// クエリパラメータ
	// limit: 取得件数（デフォルト20）
	// before: このメッセージIDより古いものを取得（無限スクロール用）
	const limit = Math.min(Number(c.req.query('limit') ?? 20), 100);
	const before = c.req.query('before');

	let messages;

	if (before) {
		// before に指定したメッセージIDより古いものを取得
		const beforeMsg = await c.env.umeyui_db
			.prepare('SELECT created_at FROM messages WHERE id = ?')
			.bind(before)
			.first<{ created_at: string }>();

		if (!beforeMsg) return c.json({ messages: [] });

		const { results } = await c.env.umeyui_db
			.prepare(
				`
        SELECT
          m.id, m.body, m.created_at,
          u.id AS user_id, u.shop_name, u.avatar_url
        FROM messages m
        JOIN users u ON m.user_id = u.id
        WHERE m.room_id = ? AND m.created_at < ?
        ORDER BY m.created_at DESC
        LIMIT ?
      `,
			)
			.bind(id, beforeMsg.created_at, limit)
			.all();

		messages = results.reverse(); // 古い順に並べ直す
	} else {
		// 最新のメッセージを取得
		const { results } = await c.env.umeyui_db
			.prepare(
				`
        SELECT
          m.id, m.body, m.created_at,
          u.id AS user_id, u.shop_name, u.avatar_url
        FROM messages m
        JOIN users u ON m.user_id = u.id
        WHERE m.room_id = ?
        ORDER BY m.created_at DESC
        LIMIT ?
      `,
			)
			.bind(id, limit)
			.all();

		messages = results.reverse(); // 古い順に並べ直す
	}

	// メッセージを取得したら既読を更新
	await c.env.umeyui_db
		.prepare(
			`INSERT INTO user_room_reads (user_id, room_id, last_read_at)
       VALUES (?, ?, CURRENT_TIMESTAMP)
       ON CONFLICT(user_id, room_id) DO UPDATE SET last_read_at = CURRENT_TIMESTAMP`,
		)
		.bind(authUser.sub, id)
		.run();

	return c.json({ messages });
});

// POST /chat-rooms/:id/messages
// confirmed参加者のみ: メッセージを送信
chatRoutes.post('/:id/messages', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	const room = await getAccessibleRoom(c.env.umeyui_db, id, authUser.sub);
	if (!room) {
		return c.json({ error: 'チャットルームが見つかりません、またはアクセス権がありません' }, 404);
	}

	const { body } = await c.req.json();

	if (!body || body.trim() === '') {
		return c.json({ error: 'メッセージを入力してください' }, 400);
	}

	if (body.length > 1000) {
		return c.json({ error: 'メッセージは1000文字以内にしてください' }, 400);
	}

	const messageId = crypto.randomUUID();

	await c.env.umeyui_db
		.prepare('INSERT INTO messages (id, room_id, user_id, body) VALUES (?, ?, ?, ?)')
		.bind(messageId, id, authUser.sub, body.trim())
		.run();

	// 送信者の名前を取得
	const sender = await c.env.umeyui_db
		.prepare('SELECT shop_name FROM users WHERE id = ?')
		.bind(authUser.sub)
		.first<{ shop_name: string | null }>();
	const senderName = sender?.shop_name ?? '参加者';
	const preview = body.trim().length > 40 ? body.trim().substring(0, 40) + '…' : body.trim();

	// 同じルームの他の参加者にアプリ内通知 + プッシュ通知
	const { results: otherMembers } = await c.env.umeyui_db
		.prepare(
			`SELECT r.user_id FROM reservations r
       WHERE r.slot_id = ? AND r.status = 'confirmed' AND r.user_id != ?`,
		)
		.bind(room.slot_id, authUser.sub)
		.all<{ user_id: string }>();

	if (otherMembers.length > 0) {
		const notifBatch = otherMembers.map((m) =>
			c.env.umeyui_db
				.prepare('INSERT INTO notifications (id, user_id, type, slot_id, message) VALUES (?, ?, ?, ?, ?)')
				.bind(crypto.randomUUID(), m.user_id, 'new_message', room.slot_id, `${senderName}：${preview}`)
		);
		await c.env.umeyui_db.batch(notifBatch);

		await Promise.all(otherMembers.map((m) => sendPushToUser(c.env, m.user_id, senderName, preview)));
	}

	return c.json(
		{
			id: messageId,
			body: body.trim(),
			user_id: authUser.sub,
			created_at: new Date().toISOString(),
		},
		201,
	);
});
