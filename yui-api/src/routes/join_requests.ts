import { Hono } from 'hono';
import { requireAuth } from '../lib/middleware';
import { confirmSlot, createNotification } from '../lib/slot_helpers';

// /slots/:id/join-requests にマウント
export const slotJoinRequestRoutes = new Hono<{ Bindings: Env }>();

// /join-requests にマウント
export const joinRequestRoutes = new Hono<{ Bindings: Env }>();

// POST /slots/:id/join-requests
// 非発起人出店者: 参加申請を送る
slotJoinRequestRoutes.post('/:id/join-requests', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	if (authUser.role === 'admin') {
		return c.json({ error: '管理者は参加申請できません' }, 403);
	}

	const slotId = c.req.param('id');

	// 枠の存在・状態確認
	const slot = await c.env.umeyui_db
		.prepare('SELECT id, status, max_vendors FROM slots WHERE id = ?')
		.bind(slotId)
		.first<{ id: string; status: string; max_vendors: number | null }>();

	if (!slot) return c.json({ error: '枠が見つかりません' }, 404);
	if (slot.status === 'cancelled') return c.json({ error: 'この枠はキャンセルされています' }, 400);
	if (slot.status === 'open') return c.json({ error: 'この枠はまだ募集開始されていません' }, 400);

	// 満員チェック
	if (slot.max_vendors !== null) {
		const countResult = await c.env.umeyui_db
			.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(slotId)
			.first<{ count: number }>();
		if ((countResult?.count ?? 0) >= slot.max_vendors) {
			return c.json({ error: 'この枠は満員です' }, 400);
		}
	}

	// 既に予約済みでないかチェック
	const existing = await c.env.umeyui_db
		.prepare("SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND status != 'cancelled'")
		.bind(slotId, authUser.sub)
		.first();
	if (existing) return c.json({ error: 'すでにこの枠に参加済みです' }, 409);

	// 自分が発起人でないかチェック（発起人は申請不要）
	const isInitiator = await c.env.umeyui_db
		.prepare("SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND is_initiator = 1 AND status != 'cancelled'")
		.bind(slotId, authUser.sub)
		.first();
	if (isInitiator) return c.json({ error: '発起人は申請不要です' }, 400);

	// 既に申請中でないかチェック
	const existingRequest = await c.env.umeyui_db
		.prepare('SELECT id, status FROM join_requests WHERE slot_id = ? AND requester_id = ?')
		.bind(slotId, authUser.sub)
		.first<{ id: string; status: string }>();

	const { message } = await c.req.json();

	if (existingRequest) {
		if (existingRequest.status === 'pending') {
			return c.json({ error: 'すでに申請中です' }, 409);
		}
		// rejected の場合は再申請可能 → UPDATE
		await c.env.umeyui_db
			.prepare(
				"UPDATE join_requests SET status = 'pending', message = ?, created_at = CURRENT_TIMESTAMP WHERE id = ?",
			)
			.bind(message ?? null, existingRequest.id)
			.run();

		await notifyInitiator(c.env.umeyui_db, slotId, authUser.sub);
		return c.json({ id: existingRequest.id, status: 'pending' }, 200);
	}

	const id = crypto.randomUUID();
	await c.env.umeyui_db
		.prepare('INSERT INTO join_requests (id, slot_id, requester_id, message) VALUES (?, ?, ?, ?)')
		.bind(id, slotId, authUser.sub, message ?? null)
		.run();

	await notifyInitiator(c.env.umeyui_db, slotId, authUser.sub);

	return c.json({ id, status: 'pending' }, 201);
});

// GET /slots/:id/join-requests
// 発起人のみ: 枠への申請一覧を取得
slotJoinRequestRoutes.get('/:id/join-requests', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const slotId = c.req.param('id');

	// 発起人チェック（管理者はスキップ）
	if (authUser.role !== 'admin') {
		const isInitiator = await c.env.umeyui_db
			.prepare(
				"SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND is_initiator = 1 AND status != 'cancelled'",
			)
			.bind(slotId, authUser.sub)
			.first();
		if (!isInitiator) return c.json({ error: '発起人のみが申請一覧を確認できます' }, 403);
	}

	const { results } = await c.env.umeyui_db
		.prepare(
			`
      SELECT jr.id, jr.status, jr.message, jr.response_message, jr.created_at,
             u.id AS requester_id, u.shop_name, u.avatar_url, u.email
      FROM join_requests jr
      JOIN users u ON jr.requester_id = u.id
      WHERE jr.slot_id = ?
      ORDER BY jr.created_at ASC
    `,
		)
		.bind(slotId)
		.all();

	return c.json(results);
});

// GET /join-requests/incoming
// 発起人として受け取った pending な申請一覧
joinRequestRoutes.get('/incoming', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { results } = await c.env.umeyui_db
		.prepare(
			`
      SELECT jr.id, jr.slot_id, jr.status, jr.message, jr.created_at,
             u.id AS requester_id, u.shop_name, u.avatar_url, u.email,
             s.date, s.name AS slot_name, s.start_time, s.end_time, s.description
      FROM join_requests jr
      JOIN users u ON jr.requester_id = u.id
      JOIN slots s ON jr.slot_id = s.id
      JOIN reservations r
        ON r.slot_id = jr.slot_id
        AND r.user_id = ?
        AND r.is_initiator = 1
        AND r.status != 'cancelled'
      WHERE jr.status = 'pending'
      ORDER BY jr.created_at DESC
    `,
		)
		.bind(authUser.sub)
		.all();

	return c.json(results);
});

// GET /join-requests/outgoing
// 自分が送った申請の一覧（全ステータス）
joinRequestRoutes.get('/outgoing', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { results } = await c.env.umeyui_db
		.prepare(
			`
      SELECT jr.id, jr.slot_id, jr.status, jr.message, jr.response_message, jr.created_at,
             s.date, s.name AS slot_name, s.start_time, s.end_time, s.description
      FROM join_requests jr
      JOIN slots s ON jr.slot_id = s.id
      WHERE jr.requester_id = ?
      ORDER BY jr.created_at DESC
    `,
		)
		.bind(authUser.sub)
		.all();

	return c.json(results);
});

// PATCH /join-requests/:requestId
// 発起人: 申請を承認 or 却下
joinRequestRoutes.patch('/:requestId', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { requestId } = c.req.param();
	const { action, response_message } = await c.req.json<{
		action: 'approve' | 'reject';
		response_message?: string;
	}>();

	if (action !== 'approve' && action !== 'reject') {
		return c.json({ error: 'action は approve または reject を指定してください' }, 400);
	}

	// 申請を取得
	const request = await c.env.umeyui_db
		.prepare('SELECT * FROM join_requests WHERE id = ?')
		.bind(requestId)
		.first<{ id: string; slot_id: string; requester_id: string; status: string }>();

	if (!request) return c.json({ error: '申請が見つかりません' }, 404);
	if (request.status !== 'pending') return c.json({ error: 'この申請はすでに処理済みです' }, 400);

	// 発起人チェック（管理者はスキップ）
	if (authUser.role !== 'admin') {
		const isInitiator = await c.env.umeyui_db
			.prepare(
				"SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND is_initiator = 1 AND status != 'cancelled'",
			)
			.bind(request.slot_id, authUser.sub)
			.first();
		if (!isInitiator) return c.json({ error: '発起人のみが申請を処理できます' }, 403);
	}

	if (action === 'reject') {
		await c.env.umeyui_db
			.prepare("UPDATE join_requests SET status = 'rejected', response_message = ? WHERE id = ?")
			.bind(response_message ?? null, requestId)
			.run();

		// 申請者にアプリ内通知
		const rejectSlot = await c.env.umeyui_db
			.prepare('SELECT date FROM slots WHERE id = ?')
			.bind(request.slot_id)
			.first<{ date: string }>();
		await createNotification(
			c.env.umeyui_db,
			request.requester_id,
			'request_rejected',
			request.slot_id,
			`${rejectSlot?.date ?? ''}の参加申請が却下されました`,
		);
		console.log('[Push] 参加申請却下通知 → requester:', request.requester_id);
		return c.json({ message: '申請を却下しました' });
	}

	// approve: 枠チェック
	const slot = await c.env.umeyui_db
		.prepare('SELECT status, min_vendors, max_vendors FROM slots WHERE id = ?')
		.bind(request.slot_id)
		.first<{ status: string; min_vendors: number | null; max_vendors: number | null }>();

	if (!slot) return c.json({ error: '枠が見つかりません' }, 404);
	if (slot.status === 'cancelled') return c.json({ error: 'この枠はキャンセルされています' }, 400);

	// 満員チェック
	if (slot.max_vendors !== null) {
		const countResult = await c.env.umeyui_db
			.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(request.slot_id)
			.first<{ count: number }>();
		if ((countResult?.count ?? 0) >= slot.max_vendors) {
			return c.json({ error: 'この枠は満員です' }, 400);
		}
	}

	// キャンセル済みレコードがあればUPDATE、なければINSERT
	const existingCancelled = await c.env.umeyui_db
		.prepare("SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND status = 'cancelled'")
		.bind(request.slot_id, request.requester_id)
		.first<{ id: string }>();

	const reservationId = existingCancelled?.id ?? crypto.randomUUID();

	await c.env.umeyui_db.batch([
		existingCancelled
			? c.env.umeyui_db
					.prepare("UPDATE reservations SET status = 'pending', is_initiator = 0 WHERE id = ?")
					.bind(reservationId)
			: c.env.umeyui_db
					.prepare('INSERT INTO reservations (id, slot_id, user_id, is_initiator, status) VALUES (?, ?, ?, 0, ?)')
					.bind(reservationId, request.slot_id, request.requester_id, 'pending'),
		c.env.umeyui_db
			.prepare("UPDATE join_requests SET status = 'approved', response_message = ? WHERE id = ?")
			.bind(response_message ?? null, requestId),
	]);

	// 参加者数チェック → min 達成で開催確定
	const countResult = await c.env.umeyui_db
		.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
		.bind(request.slot_id)
		.first<{ count: number }>();

	const newCount = countResult?.count ?? 0;

	if (slot.min_vendors !== null && newCount >= slot.min_vendors) {
		await confirmSlot(c.env.umeyui_db, request.slot_id);
	}

	// 申請者にアプリ内通知
	const approveSlot = await c.env.umeyui_db
		.prepare('SELECT date FROM slots WHERE id = ?')
		.bind(request.slot_id)
		.first<{ date: string }>();
	await createNotification(
		c.env.umeyui_db,
		request.requester_id,
		'request_approved',
		request.slot_id,
		`${approveSlot?.date ?? ''}の参加申請が承認されました`,
	);
	console.log('[Push] 参加申請承認通知 → requester:', request.requester_id);
	return c.json({ message: '申請を承認しました', reservation_id: reservationId });
});

// ---- ヘルパー ----

async function notifyInitiator(db: D1Database, slotId: string, requesterId: string): Promise<void> {
	const initiator = await db
		.prepare(
			`SELECT u.push_token, u.shop_name FROM users u
       JOIN reservations r ON r.user_id = u.id
       WHERE r.slot_id = ? AND r.is_initiator = 1 AND r.status != 'cancelled'`,
		)
		.bind(slotId)
		.first<{ push_token: string | null; shop_name: string | null }>();

	const requester = await db.prepare('SELECT shop_name FROM users WHERE id = ?').bind(requesterId).first<{
		shop_name: string | null;
	}>();

	// TODO: FCM / APNs 送信
	console.log('[Push] 発起人への参加申請通知:', initiator?.shop_name, '←', requester?.shop_name ?? requesterId);
}
