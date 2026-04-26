import { Hono } from 'hono';
import { requireAuth, requireAdmin } from '../lib/middleware';
import { confirmSlot } from '../lib/slot_helpers';

export const slotRoutes = new Hono<{ Bindings: Env }>();

// POST /slots
// 管理者のみ: 出店可能日を追加
slotRoutes.post('/', async (c) => {
	const admin = await requireAdmin(c);
	if (!admin) return c.res;

	const { date } = await c.req.json();

	if (!date) {
		return c.json({ error: 'date は必須です（例: 2026-05-03）' }, 400);
	}

	// 日付フォーマットチェック（YYYY-MM-DD）
	if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
		return c.json({ error: 'date の形式が正しくありません（例: 2026-05-03）' }, 400);
	}

	// 実在する日付かチェック（例: 2026-13-50 を弾く）
	const parsed = new Date(date);
	if (isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== date) {
		return c.json({ error: 'date が実在しない日付です（例: 2026-05-03）' }, 400);
	}

	// 同じ日付の重複チェック
	const existing = await c.env.umeyui_db.prepare('SELECT id FROM slots WHERE date = ?').bind(date).first();

	if (existing) {
		return c.json({ error: 'この日付の枠はすでに存在します' }, 409);
	}

	const id = crypto.randomUUID();

	await c.env.umeyui_db
		.prepare('INSERT INTO slots (id, date, status, created_by) VALUES (?, ?, ?, ?)')
		.bind(id, date, 'open', admin.sub)
		.run();

	return c.json({ id, date, status: 'open' }, 201);
});

// GET /slots
// 全員: 枠一覧を取得（カレンダー表示用）
// 各枠の現在の予約数・参加者一覧も合わせて返す
slotRoutes.get('/', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const today = new Date().toISOString().slice(0, 10);

	const { results: slots } = await c.env.umeyui_db
		.prepare(
			`
      SELECT
        s.*,
        COUNT(r.id) AS current_count
      FROM slots s
      LEFT JOIN reservations r
        ON s.id = r.slot_id AND r.status != 'cancelled'
      WHERE s.date >= ?
      GROUP BY s.id
      ORDER BY s.date ASC
    `,
		)
		.bind(today)
		.all();

	// 全スロットの参加者を一括取得
	const { results: vendorRows } = await c.env.umeyui_db
		.prepare(
			`
      SELECT r.slot_id, u.id AS user_id, u.shop_name, u.avatar_url, r.is_initiator
      FROM reservations r
      JOIN users u ON r.user_id = u.id
      WHERE r.status != 'cancelled'
      ORDER BY r.created_at ASC
    `,
		)
		.all();

	// スロットIDごとに参加者をまとめる
	const vendorMap = new Map<string, any[]>();
	for (const v of vendorRows) {
		const sid = v.slot_id as string;
		if (!vendorMap.has(sid)) vendorMap.set(sid, []);
		vendorMap.get(sid)!.push({
			user_id: v.user_id,
			shop_name: v.shop_name,
			avatar_url: v.avatar_url,
			is_initiator: v.is_initiator,
		});
	}

	const result = slots.map((s: any) => ({
		...s,
		vendors: vendorMap.get(s.id as string) ?? [],
	}));

	return c.json(result);
});

// GET /slots/:id
// 全員: 枠の詳細 + 予約者一覧
slotRoutes.get('/:id', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	const slot = await c.env.umeyui_db
		.prepare(
			`
      SELECT
        s.*,
        COUNT(r.id) AS current_count
      FROM slots s
      LEFT JOIN reservations r
        ON s.id = r.slot_id AND r.status != 'cancelled'
      WHERE s.id = ?
      GROUP BY s.id
    `,
		)
		.bind(id)
		.first();

	if (!slot) return c.json({ error: '枠が見つかりません' }, 404);

	// 予約者一覧（アイコン表示用）
	const { results: vendors } = await c.env.umeyui_db
		.prepare(
			`
      SELECT
        u.id AS user_id,
        u.shop_name,
        u.avatar_url,
        r.is_initiator,
        r.status
      FROM reservations r
      JOIN users u ON r.user_id = u.id
      WHERE r.slot_id = ? AND r.status != 'cancelled'
      ORDER BY r.created_at ASC
    `,
		)
		.bind(id)
		.all();

	return c.json({ ...slot, vendors });
});

// PATCH /slots/:id
// 管理者 or confirmed参加者: イベント名・時間帯を編集
slotRoutes.patch('/:id', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	// 管理者以外は: 発起人 or 開催確定後の参加者のみ編集可
	if (authUser.role !== 'admin') {
		const reservation = await c.env.umeyui_db
			.prepare(
				`
        SELECT r.id FROM reservations r
        WHERE r.slot_id = ? AND r.user_id = ? AND r.status != 'cancelled'
          AND (r.is_initiator = 1 OR r.status = 'confirmed')
      `,
			)
			.bind(id, authUser.sub)
			.first();

		if (!reservation) {
			return c.json({ error: '編集権限がありません（発起人または開催確定後の参加者のみ編集できます）' }, 403);
		}
	}

	const { name, start_time, end_time, description, min_vendors, max_vendors } = await c.req.json();

	if (min_vendors !== undefined || max_vendors !== undefined) {
		const slot = await c.env.umeyui_db
			.prepare('SELECT status FROM slots WHERE id = ?')
			.bind(id)
			.first<{ status: string }>();

		if (min_vendors !== undefined && slot?.status !== 'recruiting') {
			return c.json({ error: '最低人数は募集中のみ変更できます' }, 400);
		}
		if (max_vendors !== undefined && slot?.status !== 'recruiting' && slot?.status !== 'confirmed') {
			return c.json({ error: '最大人数は募集中または開催確定中のみ変更できます' }, 400);
		}

		const countResult = await c.env.umeyui_db
			.prepare("SELECT COUNT(*) AS cnt FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(id)
			.first<{ cnt: number }>();
		const currentCount = countResult?.cnt ?? 0;

		if (max_vendors !== undefined && max_vendors < currentCount) {
			return c.json({ error: `最大人数は現在の参加者数（${currentCount}人）以上にしてください` }, 400);
		}

		// 最低人数を下げた結果、現在の参加者数が最低人数に達した場合は自動確定
		if (min_vendors !== undefined && slot?.status === 'recruiting' && currentCount >= min_vendors) {
			await c.env.umeyui_db
				.prepare('UPDATE slots SET name = ?, start_time = ?, end_time = ?, description = ?, min_vendors = ?, max_vendors = COALESCE(?, max_vendors) WHERE id = ?')
				.bind(name ?? null, start_time ?? null, end_time ?? null, description ?? null, min_vendors, max_vendors ?? null, id)
				.run();
			await confirmSlot(c.env, id);
			return c.json({ message: '枠情報を更新しました（参加者が最低人数に達したため開催が確定しました）' });
		}
	}

	await c.env.umeyui_db
		.prepare('UPDATE slots SET name = ?, start_time = ?, end_time = ?, description = ? WHERE id = ?')
		.bind(name ?? null, start_time ?? null, end_time ?? null, description ?? null, id)
		.run();

	if (min_vendors !== undefined) {
		await c.env.umeyui_db.prepare('UPDATE slots SET min_vendors = ? WHERE id = ?').bind(min_vendors, id).run();
	}
	if (max_vendors !== undefined) {
		await c.env.umeyui_db.prepare('UPDATE slots SET max_vendors = ? WHERE id = ?').bind(max_vendors, id).run();
	}

	return c.json({ message: '枠情報を更新しました' });
});

// POST /slots/:id/cancel-event
// 発起人 or 管理者: イベントを全員キャンセルして枠を募集前に戻す
slotRoutes.post('/:id/cancel-event', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const { id } = c.req.param();

	// 発起人または管理者チェック
	if (authUser.role !== 'admin') {
		const isInitiator = await c.env.umeyui_db
			.prepare(
				"SELECT r.id FROM reservations r WHERE r.slot_id = ? AND r.user_id = ? AND r.is_initiator = 1 AND r.status != 'cancelled'",
			)
			.bind(id, authUser.sub)
			.first();

		if (!isInitiator) {
			return c.json({ error: '発起人のみがイベントをキャンセルできます' }, 403);
		}
	}

	// チャットルームのIDを先に取得（メッセージ削除用）
	const chatRoom = await c.env.umeyui_db
		.prepare('SELECT id FROM chat_rooms WHERE slot_id = ?')
		.bind(id)
		.first<{ id: string }>();

	const batchOps: D1PreparedStatement[] = [
		c.env.umeyui_db
			.prepare("UPDATE reservations SET status = 'cancelled' WHERE slot_id = ? AND status != 'cancelled'")
			.bind(id),
		c.env.umeyui_db
			.prepare("UPDATE slots SET status = 'open', min_vendors = NULL, max_vendors = NULL, name = NULL, start_time = NULL, end_time = NULL WHERE id = ?")
			.bind(id),
	];

	if (chatRoom) {
		batchOps.push(
			c.env.umeyui_db.prepare('DELETE FROM user_room_reads WHERE room_id = ?').bind(chatRoom.id),
			c.env.umeyui_db.prepare('DELETE FROM messages WHERE room_id = ?').bind(chatRoom.id),
			c.env.umeyui_db.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(chatRoom.id),
		);
	}

	await c.env.umeyui_db.batch(batchOps);

	if (c.env.VERCEL_DEPLOY_HOOK_URL) {
		await fetch(c.env.VERCEL_DEPLOY_HOOK_URL, { method: 'POST' }).catch(() => {});
	}

	return c.json({ message: 'イベントをキャンセルしました' });
});

// DELETE /slots/:id
// 管理者のみ: 募集前（open）の枠のみ完全削除。それ以外は cancel-event を使う。
slotRoutes.delete('/:id', async (c) => {
	const admin = await requireAdmin(c);
	if (!admin) return c.res;

	const { id } = c.req.param();

	const slot = await c.env.umeyui_db
		.prepare('SELECT id, status FROM slots WHERE id = ?')
		.bind(id)
		.first<{ id: string; status: string }>();

	if (!slot) return c.json({ error: '枠が見つかりません' }, 404);

	// open以外の枠は管理者が発起人の場合のみ削除可
	if (slot.status !== 'open') {
		const isAdminInitiator = await c.env.umeyui_db
			.prepare("SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND is_initiator = 1 AND status != 'cancelled'")
			.bind(id, admin.sub)
			.first();

		if (!isAdminInitiator) {
			return c.json(
				{ error: '募集前（open）の枠のみ削除できます。発起人でない場合はイベントキャンセルを使用してください。' },
				400,
			);
		}
	}

	// チャットルームのメッセージを先に削除（FK制約）
	const chatRoom = await c.env.umeyui_db
		.prepare('SELECT id FROM chat_rooms WHERE slot_id = ?')
		.bind(id)
		.first<{ id: string }>();

	const batchOps: D1PreparedStatement[] = [
		c.env.umeyui_db.prepare('DELETE FROM join_requests WHERE slot_id = ?').bind(id),
		c.env.umeyui_db.prepare('DELETE FROM notifications WHERE slot_id = ?').bind(id),
		c.env.umeyui_db.prepare('DELETE FROM reservations WHERE slot_id = ?').bind(id),
	];
	if (chatRoom) {
		batchOps.push(
			c.env.umeyui_db.prepare('DELETE FROM messages WHERE room_id = ?').bind(chatRoom.id),
			c.env.umeyui_db.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(chatRoom.id),
		);
	}
	await c.env.umeyui_db.batch(batchOps);
	await c.env.umeyui_db.prepare('DELETE FROM slots WHERE id = ?').bind(id).run();

	if (c.env.VERCEL_DEPLOY_HOOK_URL) {
		await fetch(c.env.VERCEL_DEPLOY_HOOK_URL, { method: 'POST' }).catch(() => {});
	}

	return c.json({ message: '枠を削除しました' });
});
