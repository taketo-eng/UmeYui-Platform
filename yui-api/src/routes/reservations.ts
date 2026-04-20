import { Hono } from 'hono';
import { requireAuth } from '../lib/middleware';
import { confirmSlot, deleteChatRoom, createNotificationsForAllVendors, sendPushToAllActive } from '../lib/slot_helpers';
import { sendPushToUser } from '../lib/fcm';

export const reservationRoutes = new Hono<{ Bindings: Env }>();

// POST /slots/:id/reservations
// 出店者: 枠に予約する
// 最初の予約者（発起人）は min_vendors / max_vendors も送る
reservationRoutes.post('/:id/reservations', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const slotId = c.req.param('id');

	// 管理者は発起人（最初の予約者）としてのみ参加可能
	if (authUser.role === 'admin') {
		const adminCountResult = await c.env.umeyui_db
			.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(slotId)
			.first<{ count: number }>();
		if ((adminCountResult?.count ?? 0) > 0) {
			return c.json({ error: '管理者は発起人としてのみ参加できます' }, 403);
		}
	}

	// 枠の存在確認
	const slot = await c.env.umeyui_db.prepare('SELECT * FROM slots WHERE id = ?').bind(slotId).first<{
		id: string;
		status: string;
		min_vendors: number | null;
		max_vendors: number | null;
	}>();

	if (!slot) return c.json({ error: '枠が見つかりません' }, 404);

	// キャンセル済みの枠には予約不可
	if (slot.status === 'cancelled') {
		return c.json({ error: 'この枠はキャンセルされています' }, 400);
	}

	// すでに確定済みで max に達している場合は締め切り
	if (slot.status === 'confirmed' && slot.max_vendors !== null) {
		const { results: existing } = await c.env.umeyui_db
			.prepare("SELECT id FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(slotId)
			.all();
		if (existing.length >= slot.max_vendors) {
			return c.json({ error: 'この枠は満員です' }, 400);
		}
	}

	// 同じ枠に重複予約していないかチェック
	const duplicate = await c.env.umeyui_db
		.prepare("SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND status != 'cancelled'")
		.bind(slotId, authUser.sub)
		.first();

	if (duplicate) {
		return c.json({ error: 'すでにこの枠に予約済みです' }, 409);
	}

	// 現在の予約数を取得
	const countResult = await c.env.umeyui_db
		.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
		.bind(slotId)
		.first<{ count: number }>();

	const currentCount = countResult?.count ?? 0;
	const isInitiator = currentCount === 0; // 最初の予約者が発起人

	// 発起人の場合は min / max が必須
	if (isInitiator) {
		const { min_vendors, max_vendors } = await c.req.json();

		if (!min_vendors || !max_vendors) {
			return c.json({ error: '最初の予約者は min_vendors と max_vendors を設定してください' }, 400);
		}
		if (min_vendors < 1 || min_vendors > 15) {
			return c.json({ error: 'min_vendors は 1〜15 の範囲で設定してください' }, 400);
		}
		if (max_vendors < min_vendors || max_vendors > 15) {
			return c.json({ error: 'max_vendors は min_vendors 以上 15 以下で設定してください' }, 400);
		}

		// キャンセル済みの既存レコードがあればUPDATE、なければINSERT
		const existingCancelledInitiator = await c.env.umeyui_db
			.prepare("SELECT id FROM reservations WHERE slot_id = ? AND user_id = ? AND status = 'cancelled'")
			.bind(slotId, authUser.sub)
			.first<{ id: string }>();

		const reservationId = existingCancelledInitiator?.id ?? crypto.randomUUID();

		// トランザクション: 予約追加 + 枠を recruiting に更新 + min/max を設定
		await c.env.umeyui_db.batch([
			existingCancelledInitiator
				? c.env.umeyui_db
						.prepare("UPDATE reservations SET status = 'pending', is_initiator = 1 WHERE id = ?")
						.bind(reservationId)
				: c.env.umeyui_db
						.prepare('INSERT INTO reservations (id, slot_id, user_id, is_initiator, status) VALUES (?, ?, ?, 1, ?)')
						.bind(reservationId, slotId, authUser.sub, 'pending'),
			c.env.umeyui_db
				.prepare("UPDATE slots SET status = 'recruiting', min_vendors = ?, max_vendors = ? WHERE id = ?")
				.bind(min_vendors, max_vendors, slotId),
		]);

		// 枠の日付を取得
		const slotInfo = await c.env.umeyui_db
			.prepare('SELECT date FROM slots WHERE id = ?')
			.bind(slotId)
			.first<{ date: string }>();

		// 全出店者にアプリ内通知
		await createNotificationsForAllVendors(
			c.env.umeyui_db,
			authUser.sub,
			'recruitment_started',
			slotId,
			`${slotInfo?.date ?? ''}の枠で出店者の募集が始まりました（最低${min_vendors}人・最大${max_vendors}人）`,
		);

		// min_vendors=1 の場合は発起人1人で即確定（確定通知はconfirmSlot内で送信）
		if (min_vendors === 1) {
			await confirmSlot(c.env, slotId);
		} else {
			// 2人以上が必要な場合のみ募集開始通知をプッシュ
			await sendPushToAllActive(
				c.env,
				authUser.sub,
				'出店枠の募集が始まりました',
				`${slotInfo?.date ?? ''}の枠で出店者の募集が始まりました（最低${min_vendors}人）`,
			);
		}

		return c.json({ id: reservationId, status: 'pending', is_initiator: true }, 201);
	} else {
		// 2人目以降は参加申請 (POST /slots/:id/join-requests) を使う
		return c.json({ error: '2人目以降の参加は申請制です。参加申請を送ってください。' }, 403);
	}
});

// DELETE /slots/:id/reservations
// 出店者: 自分の予約をキャンセル
reservationRoutes.delete('/:id/reservations', async (c) => {
	const authUser = await requireAuth(c);
	if (!authUser) return c.res;

	const slotId = c.req.param('id');

	// 自分の予約を取得
	const reservation = await c.env.umeyui_db
		.prepare("SELECT * FROM reservations WHERE slot_id = ? AND user_id = ? AND status != 'cancelled'")
		.bind(slotId, authUser.sub)
		.first<{ id: string; is_initiator: number; status: string }>();

	if (!reservation) {
		return c.json({ error: 'キャンセルできる予約が見つかりません' }, 404);
	}

	// キャンセルする本人の情報を取得（通知用）
	const canceller = await c.env.umeyui_db
		.prepare('SELECT shop_name FROM users WHERE id = ?')
		.bind(authUser.sub)
		.first<{ shop_name: string | null }>();
	const cancellerName = canceller?.shop_name ?? '参加者';
	const isInitiator = reservation.is_initiator === 1;

	// キャンセル前に他の参加者のuser_idを取得
	const { results: otherMembers } = await c.env.umeyui_db
		.prepare(
			`SELECT user_id FROM reservations
       WHERE slot_id = ? AND user_id != ? AND status != 'cancelled'`,
		)
		.bind(slotId, authUser.sub)
		.all<{ user_id: string }>();

	// 自分の予約をキャンセル
	await c.env.umeyui_db.prepare("UPDATE reservations SET status = 'cancelled' WHERE id = ?").bind(reservation.id).run();

	// キャンセル後の残り予約数を取得
	const countResult = await c.env.umeyui_db
		.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
		.bind(slotId)
		.first<{ count: number }>();

	const remainingCount = countResult?.count ?? 0;

	if (remainingCount === 0) {
		// 全員いなくなった → チャットルーム削除・openに戻してmin/maxをリセット
		await deleteChatRoom(c.env.umeyui_db, slotId);
		await c.env.umeyui_db
			.prepare("UPDATE slots SET status = 'open', min_vendors = NULL, max_vendors = NULL, name = NULL, start_time = NULL, end_time = NULL WHERE id = ?")
			.bind(slotId)
			.run();
	} else {
		// 発起人が抜けた場合 → 次の人（古い順）を発起人に
		if (reservation.is_initiator === 1) {
			const nextReservation = await c.env.umeyui_db
				.prepare("SELECT id FROM reservations WHERE slot_id = ? AND status != 'cancelled' ORDER BY created_at ASC LIMIT 1")
				.bind(slotId)
				.first<{ id: string }>();

			if (nextReservation) {
				await c.env.umeyui_db.prepare('UPDATE reservations SET is_initiator = 1 WHERE id = ?').bind(nextReservation.id).run();
			}
		}

		// 残り人数が min を下回ったら recruiting に戻す
		const slot = await c.env.umeyui_db
			.prepare('SELECT min_vendors, status FROM slots WHERE id = ?')
			.bind(slotId)
			.first<{ min_vendors: number | null; status: string }>();

		if (slot && slot.min_vendors !== null && remainingCount < slot.min_vendors) {
			// confirmed → recruiting に戻る場合はチャットルームを削除
			if (slot.status === 'confirmed') {
				await deleteChatRoom(c.env.umeyui_db, slotId);
			}
			// recruiting に戻して全員の予約を pending に
			await c.env.umeyui_db.batch([
				c.env.umeyui_db.prepare("UPDATE slots SET status = 'recruiting' WHERE id = ?").bind(slotId),
				c.env.umeyui_db.prepare("UPDATE reservations SET status = 'pending' WHERE slot_id = ? AND status = 'confirmed'").bind(slotId),
			]);
		}
	}

	// 他の参加者にプッシュ通知
	if (otherMembers.length > 0) {
		const { title, body } = isInitiator
			? { title: '開催が中止になりました', body: `発起人（${cancellerName}）が参加を取りやめたため、この枠の開催予定がなくなりました` }
			: { title: `${cancellerName}がキャンセルしました`, body: '参加者が出店をキャンセルしました。人数をご確認ください' };
		await Promise.all(otherMembers.map((m) => sendPushToUser(c.env, m.user_id, title, body)));
	}

	return c.json({ message: '予約をキャンセルしました' });
});

