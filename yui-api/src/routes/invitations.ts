import { Hono } from 'hono';
import { requireAuth } from '../lib/middleware';
import { confirmSlot, createNotification } from '../lib/slot_helpers';
import { sendPushToUser } from '../lib/fcm';

// /slots/:id/... にマウント
export const slotInvitationRoutes = new Hono<{ Bindings: Env }>();
// /invitations/... にマウント
export const invitationRoutes = new Hono<{ Bindings: Env }>();

// 共通: 指定ユーザーがその枠の発起人かどうか
async function isInitiator(env: Env, slotId: string, userId: string): Promise<boolean> {
	const row = await env.umeyui_db
		.prepare(
			"SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND is_initiator = 1 AND status != 'cancelled'",
		)
		.bind(slotId, userId)
		.first();
	return !!row;
}

// ----------------------------------------------------------------
// GET /slots/:id/invitable-users
// 発起人のみ: この枠に招待できるユーザー一覧
// ----------------------------------------------------------------
slotInvitationRoutes.get('/:id/invitable-users', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const slotId = c.req.param('id');
	if (!(await isInitiator(c.env, slotId, authUser.sub))) {
		return c.json({ error: '発起人のみが招待できます' }, 403);
	}

	// vendor かつ有効、system除外、自分除外、すでに枠に参加している人は除外。
	// pending な招待が既にある人には already_invited フラグを立てる（UIで「招待済み」表示）
	const { results } = await c.env.umeyui_db
		.prepare(
			`
      SELECT u.id, u.shop_name, u.avatar_url, u.category,
             EXISTS(
               SELECT 1 FROM invitations i
               WHERE i.slot_id = ? AND i.invitee_id = u.id AND i.status = 'pending'
             ) AS already_invited
      FROM users u
      WHERE u.role = 'vendor'
        AND u.is_active = 1
        AND u.id != 'system'
        AND u.id != ?
        AND u.id NOT IN (
          SELECT user_id FROM reservations WHERE slot_id = ? AND status != 'cancelled'
        )
      ORDER BY u.shop_name COLLATE NOCASE ASC
    `,
		)
		.bind(slotId, authUser.sub, slotId)
		.all();

	return c.json(results);
});

// ----------------------------------------------------------------
// POST /slots/:id/invitations
// 発起人のみ: ユーザーを枠に招待する
// body: { invitee_id: string, message?: string }
// ----------------------------------------------------------------
slotInvitationRoutes.post('/:id/invitations', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const slotId = c.req.param('id');
	const { invitee_id, message } = await c.req.json<{ invitee_id: string; message?: string }>();

	if (!invitee_id) return c.json({ error: '招待相手を指定してください' }, 400);
	if (invitee_id === authUser.sub) return c.json({ error: '自分自身は招待できません' }, 400);

	// 発起人チェック
	if (!(await isInitiator(c.env, slotId, authUser.sub))) {
		return c.json({ error: '発起人のみが招待できます' }, 403);
	}

	// 枠の状態チェック（参加申請と同じく open/cancelled は不可、recruiting/confirmed は可）
	const slot = await c.env.umeyui_db
		.prepare('SELECT id, status, max_vendors FROM slots WHERE id = ?')
		.bind(slotId)
		.first<{ id: string; status: string; max_vendors: number | null }>();
	if (!slot) return c.json({ error: '枠が見つかりません' }, 404);
	if (slot.status === 'cancelled') return c.json({ error: 'この枠はキャンセルされています' }, 400);
	if (slot.status === 'open') return c.json({ error: 'この枠はまだ募集開始されていません' }, 400);

	// 招待相手が存在する有効なvendorか
	const invitee = await c.env.umeyui_db
		.prepare("SELECT id, shop_name FROM users WHERE id = ? AND role = 'vendor' AND is_active = 1")
		.bind(invitee_id)
		.first<{ id: string; shop_name: string | null }>();
	if (!invitee) return c.json({ error: '招待相手が見つかりません' }, 404);

	// すでに参加済みでないか
	const already = await c.env.umeyui_db
		.prepare("SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND status != 'cancelled'")
		.bind(slotId, invitee_id)
		.first();
	if (already) return c.json({ error: 'この人はすでにこの枠に参加しています' }, 409);

	// 満員チェック
	if (slot.max_vendors !== null) {
		const cnt = await c.env.umeyui_db
			.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(slotId)
			.first<{ count: number }>();
		if ((cnt?.count ?? 0) >= slot.max_vendors) return c.json({ error: 'この枠は満員です' }, 400);
	}

	// 既存の招待があるか（declined からの再招待は UPDATE で pending に戻す）
	const existing = await c.env.umeyui_db
		.prepare('SELECT id, status FROM invitations WHERE slot_id = ? AND invitee_id = ?')
		.bind(slotId, invitee_id)
		.first<{ id: string; status: string }>();

	if (existing) {
		if (existing.status === 'pending') return c.json({ error: 'すでに招待済みです' }, 409);
		if (existing.status === 'accepted') return c.json({ error: 'すでに承認済みです' }, 409);
		// declined → 再招待
		await c.env.umeyui_db
			.prepare(
				"UPDATE invitations SET status = 'pending', message = ?, response_message = NULL, created_at = CURRENT_TIMESTAMP WHERE id = ?",
			)
			.bind(message ?? null, existing.id)
			.run();
		await notifyInvitee(c.env, slotId, authUser.sub, invitee_id);
		return c.json({ id: existing.id, status: 'pending' }, 200);
	}

	const id = crypto.randomUUID();
	await c.env.umeyui_db
		.prepare('INSERT INTO invitations (id, slot_id, inviter_id, invitee_id, message) VALUES (?, ?, ?, ?, ?)')
		.bind(id, slotId, authUser.sub, invitee_id, message ?? null)
		.run();

	await notifyInvitee(c.env, slotId, authUser.sub, invitee_id);
	return c.json({ id, status: 'pending' }, 201);
});

// ----------------------------------------------------------------
// GET /invitations/incoming
// 自分宛に届いた pending な招待一覧（招待された側 = 通知「受信」タブ用）
// ----------------------------------------------------------------
invitationRoutes.get('/incoming', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { results } = await c.env.umeyui_db
		.prepare(
			`
      SELECT inv.id, inv.slot_id, inv.status, inv.message, inv.created_at,
             u.id AS inviter_id, u.shop_name, u.avatar_url,
             s.date, s.name AS slot_name, s.start_time, s.end_time, s.description
      FROM invitations inv
      JOIN users u ON inv.inviter_id = u.id
      JOIN slots s ON inv.slot_id = s.id
      WHERE inv.invitee_id = ? AND inv.status = 'pending'
      ORDER BY inv.created_at DESC
    `,
		)
		.bind(authUser.sub)
		.all();

	return c.json(results);
});

// ----------------------------------------------------------------
// GET /invitations/outgoing
// 自分が送った招待一覧（発起人 = 通知「送信」タブ用・全ステータス）
// ----------------------------------------------------------------
invitationRoutes.get('/outgoing', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { results } = await c.env.umeyui_db
		.prepare(
			`
      SELECT inv.id, inv.slot_id, inv.status, inv.message, inv.response_message, inv.created_at,
             u.id AS invitee_id, u.shop_name, u.avatar_url,
             s.date, s.name AS slot_name, s.start_time, s.end_time, s.description
      FROM invitations inv
      JOIN users u ON inv.invitee_id = u.id
      JOIN slots s ON inv.slot_id = s.id
      WHERE inv.inviter_id = ?
      ORDER BY inv.created_at DESC
    `,
		)
		.bind(authUser.sub)
		.all();

	return c.json(results);
});

// ----------------------------------------------------------------
// PATCH /invitations/:invitationId
// 招待された側: 承認 or 辞退
// body: { action: 'accept' | 'decline', response_message?: string }
// ----------------------------------------------------------------
invitationRoutes.patch('/:invitationId', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { invitationId } = c.req.param();
	const { action, response_message } = await c.req.json<{
		action: 'accept' | 'decline';
		response_message?: string;
	}>();

	if (action !== 'accept' && action !== 'decline') {
		return c.json({ error: 'action は accept または decline を指定してください' }, 400);
	}

	const inv = await c.env.umeyui_db
		.prepare('SELECT * FROM invitations WHERE id = ?')
		.bind(invitationId)
		.first<{ id: string; slot_id: string; inviter_id: string; invitee_id: string; status: string }>();

	if (!inv) return c.json({ error: '招待が見つかりません' }, 404);
	// 招待された本人だけが返答できる
	if (inv.invitee_id !== authUser.sub) return c.json({ error: 'この招待に返答する権限がありません' }, 403);
	if (inv.status !== 'pending') return c.json({ error: 'この招待はすでに処理済みです' }, 400);

	const slotDate = await c.env.umeyui_db
		.prepare('SELECT date FROM slots WHERE id = ?')
		.bind(inv.slot_id)
		.first<{ date: string }>();

	// ---- 辞退 ----
	if (action === 'decline') {
		await c.env.umeyui_db
			.prepare("UPDATE invitations SET status = 'declined', response_message = ? WHERE id = ?")
			.bind(response_message ?? null, invitationId)
			.run();

		await createNotification(
			c.env.umeyui_db,
			inv.inviter_id,
			'invitation_declined',
			inv.slot_id,
			`${slotDate?.date ?? ''}への招待が辞退されました`,
		);
		await sendPushToUser(
			c.env,
			inv.inviter_id,
			'招待が辞退されました',
			`${slotDate?.date ?? ''}への招待が辞退されました`,
		);
		return c.json({ message: '招待を辞退しました' });
	}

	// ---- 承認（join_requests の approve と同じ確定ロジック）----
	const slot = await c.env.umeyui_db
		.prepare('SELECT status, min_vendors, max_vendors FROM slots WHERE id = ?')
		.bind(inv.slot_id)
		.first<{ status: string; min_vendors: number | null; max_vendors: number | null }>();
	if (!slot) return c.json({ error: '枠が見つかりません' }, 404);
	if (slot.status === 'cancelled') return c.json({ error: 'この枠はキャンセルされています' }, 400);

	// 満員チェック
	if (slot.max_vendors !== null) {
		const cnt = await c.env.umeyui_db
			.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(inv.slot_id)
			.first<{ count: number }>();
		if ((cnt?.count ?? 0) >= slot.max_vendors) return c.json({ error: 'この枠は満員になりました' }, 400);
	}

	// キャンセル済みレコードがあれば再利用、なければ新規
	const existingCancelled = await c.env.umeyui_db
		.prepare("SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND status = 'cancelled'")
		.bind(inv.slot_id, inv.invitee_id)
		.first<{ id: string }>();

	const reservationId = existingCancelled?.id ?? crypto.randomUUID();
	const targetStatus = slot.status === 'confirmed' ? 'confirmed' : 'pending';

	await c.env.umeyui_db.batch([
		existingCancelled
			? c.env.umeyui_db
					.prepare('UPDATE reservations SET status = ?, is_initiator = 0 WHERE id = ?')
					.bind(targetStatus, reservationId)
			: c.env.umeyui_db
					.prepare('INSERT INTO reservations (id, slot_id, user_id, is_initiator, status) VALUES (?, ?, ?, 0, ?)')
					.bind(reservationId, inv.slot_id, inv.invitee_id, targetStatus),
		c.env.umeyui_db
			.prepare("UPDATE invitations SET status = 'accepted', response_message = ? WHERE id = ?")
			.bind(response_message ?? null, invitationId),
	]);

	// 最低人数に達したら開催確定
	const cnt = await c.env.umeyui_db
		.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
		.bind(inv.slot_id)
		.first<{ count: number }>();
	const newCount = cnt?.count ?? 0;
	if (slot.min_vendors !== null && newCount >= slot.min_vendors && slot.status !== 'confirmed') {
		await confirmSlot(c.env, inv.slot_id);
	}

	// 発起人へ通知
	await createNotification(
		c.env.umeyui_db,
		inv.inviter_id,
		'invitation_accepted',
		inv.slot_id,
		`${slotDate?.date ?? ''}への招待が承認されました`,
	);
	await sendPushToUser(
		c.env,
		inv.inviter_id,
		'招待が承認されました',
		`${slotDate?.date ?? ''}への招待が承認されました`,
	);
	return c.json({ message: '招待を承認しました', reservation_id: reservationId });
});

// ---- ヘルパー ----

// 招待された側へ push + アプリ内通知
async function notifyInvitee(env: Env, slotId: string, inviterId: string, inviteeId: string): Promise<void> {
	const inviter = await env.umeyui_db
		.prepare('SELECT shop_name FROM users WHERE id = ?')
		.bind(inviterId)
		.first<{ shop_name: string | null }>();
	const slot = await env.umeyui_db
		.prepare('SELECT date FROM slots WHERE id = ?')
		.bind(slotId)
		.first<{ date: string }>();

	const name = inviter?.shop_name ?? '発起人';
	const msg = `${name}さんから${slot?.date ?? ''}への招待が届きました`;

	await createNotification(env.umeyui_db, inviteeId, 'invitation_received', slotId, msg);
	await sendPushToUser(env, inviteeId, '招待が届きました', msg);
}
