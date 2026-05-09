import { sendPushToUser } from '../lib/fcm';

export class SlotAlarm implements DurableObject {
	constructor(private ctx: DurableObjectState, private env: Env) {}

	async fetch(request: Request): Promise<Response> {
		const url = new URL(request.url);

		if (request.method === 'POST' && url.pathname === '/schedule') {
			const { deadline_at } = await request.json<{ deadline_at: string }>();
			await this.ctx.storage.setAlarm(new Date(deadline_at).getTime());
			return new Response('OK');
		}

		if (request.method === 'DELETE') {
			await this.ctx.storage.deleteAlarm();
			return new Response('OK');
		}

		return new Response('Not found', { status: 404 });
	}

	async alarm(): Promise<void> {
		const slotId = this.ctx.id.name;
		if (!slotId) return;

		const slot = await this.env.umeyui_db
			.prepare('SELECT status, min_vendors, name, date FROM slots WHERE id = ?')
			.bind(slotId)
			.first<{ status: string; min_vendors: number | null; name: string | null; date: string }>();

		// 既に確定済み・キャンセル済みなら何もしない
		if (!slot || slot.status !== 'recruiting') return;

		const countResult = await this.env.umeyui_db
			.prepare("SELECT COUNT(*) AS count FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(slotId)
			.first<{ count: number }>();

		const count = countResult?.count ?? 0;
		// 最低人数に達していたら何もしない
		if (slot.min_vendors !== null && count >= slot.min_vendors) return;

		// 参加者一覧（通知用）
		const { results: participants } = await this.env.umeyui_db
			.prepare("SELECT user_id FROM reservations WHERE slot_id = ? AND status != 'cancelled'")
			.bind(slotId)
			.all<{ user_id: string }>();

		// 発起人の屋号
		const initiator = await this.env.umeyui_db
			.prepare(
				`SELECT u.shop_name FROM users u
         JOIN reservations r ON u.id = r.user_id
         WHERE r.slot_id = ? AND r.is_initiator = 1 AND r.status != 'cancelled'`,
			)
			.bind(slotId)
			.first<{ shop_name: string | null }>();

		const label = slot.name ?? slot.date;
		const initiatorName = initiator?.shop_name ?? '出店者';
		const message = `募集期限までに最低人数に達しなかったため、${initiatorName}さん主催の${label}のイベントはキャンセルされました。`;

		// チャットルーム削除
		const chatRoom = await this.env.umeyui_db
			.prepare('SELECT id FROM chat_rooms WHERE slot_id = ?')
			.bind(slotId)
			.first<{ id: string }>();

		const batchOps: D1PreparedStatement[] = [
			this.env.umeyui_db
				.prepare("UPDATE reservations SET status = 'cancelled' WHERE slot_id = ? AND status != 'cancelled'")
				.bind(slotId),
			this.env.umeyui_db
				.prepare(
					"UPDATE slots SET status = 'open', min_vendors = NULL, max_vendors = NULL, name = NULL, start_time = NULL, end_time = NULL, deadline_at = NULL WHERE id = ?",
				)
				.bind(slotId),
		];
		if (chatRoom) {
			batchOps.push(
				this.env.umeyui_db.prepare('DELETE FROM user_room_reads WHERE room_id = ?').bind(chatRoom.id),
				this.env.umeyui_db.prepare('DELETE FROM messages WHERE room_id = ?').bind(chatRoom.id),
				this.env.umeyui_db.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(chatRoom.id),
			);
		}
		await this.env.umeyui_db.batch(batchOps);

		const now = new Date().toISOString();

		// 参加者にアプリ内通知 + プッシュ通知
		if (participants.length > 0) {
			const notifStmts = participants.map(({ user_id }) =>
				this.env.umeyui_db
					.prepare("INSERT INTO notifications (id, user_id, type, message, is_read, created_at) VALUES (?, ?, 'slot_cancelled', ?, 0, ?)")
					.bind(crypto.randomUUID(), user_id, message, now),
			);
			for (let i = 0; i < notifStmts.length; i += 100) {
				await this.env.umeyui_db.batch(notifStmts.slice(i, i + 100));
			}
			await Promise.all(participants.map(({ user_id }) => sendPushToUser(this.env, user_id, '募集期限切れ', message)));
		}

		// 参加者でない管理者にも通知
		const { results: admins } = await this.env.umeyui_db
			.prepare("SELECT id FROM users WHERE role = 'admin' AND is_active = 1")
			.all<{ id: string }>();

		const participantIds = new Set(participants.map((p) => p.user_id));
		const nonParticipantAdmins = admins.filter((a) => !participantIds.has(a.id));

		if (nonParticipantAdmins.length > 0) {
			const adminNotifStmts = nonParticipantAdmins.map(({ id }) =>
				this.env.umeyui_db
					.prepare("INSERT INTO notifications (id, user_id, type, message, is_read, created_at) VALUES (?, ?, 'slot_cancelled', ?, 0, ?)")
					.bind(crypto.randomUUID(), id, message, now),
			);
			await this.env.umeyui_db.batch(adminNotifStmts);
			await Promise.all(nonParticipantAdmins.map(({ id }) => sendPushToUser(this.env, id, '募集期限切れ', message)));
		}
	}
}
