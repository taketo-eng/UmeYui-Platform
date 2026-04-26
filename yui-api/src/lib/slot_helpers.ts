// 枠確定・チャットルーム削除・通知作成の共通処理
import { sendPushNotification } from './fcm';


export async function confirmSlot(env: Env, slotId: string, skipSideEffects = false): Promise<void> {
	// 再確定時は既存のチャットルームを再利用し、会話履歴を保持する
	const existingRoom = await env.umeyui_db
		.prepare('SELECT id FROM chat_rooms WHERE slot_id = ?')
		.bind(slotId)
		.first<{ id: string }>();

	const batchOps: D1PreparedStatement[] = [
		env.umeyui_db.prepare("UPDATE slots SET status = 'confirmed' WHERE id = ?").bind(slotId),
		env.umeyui_db.prepare("UPDATE reservations SET status = 'confirmed' WHERE slot_id = ? AND status = 'pending'").bind(slotId),
	];
	if (!existingRoom) {
		batchOps.push(
			env.umeyui_db.prepare('INSERT INTO chat_rooms (id, slot_id) VALUES (?, ?)').bind(crypto.randomUUID(), slotId),
		);
	}
	await env.umeyui_db.batch(batchOps);

	const initiator = await env.umeyui_db
		.prepare('SELECT u.shop_name FROM users u JOIN reservations r ON u.id = r.user_id WHERE r.slot_id = ? AND r.is_initiator = 1')
		.bind(slotId)
		.first<{ shop_name: string | null }>();
	const initiatorName = initiator?.shop_name ?? '出店者';

	if (!skipSideEffects) {
		await sendPushToConfirmedParticipants(env, slotId, {
			title: '開催確定！',
			body: 'チャットルームが開きました。当日に向けて話し合いましょう！',
		});
		await sendPushToNonParticipantAdmins(env, slotId, {
			title: '開催確定！',
			body: `${initiatorName}主催のイベントが確定しました！`,
		});

		if (env.VERCEL_DEPLOY_HOOK_URL) {
			await fetch(env.VERCEL_DEPLOY_HOOK_URL, { method: 'POST' }).catch(() => {});
		}
	}
}

async function sendPushToConfirmedParticipants(env: Env, slotId: string, payload: { title: string; body: string }): Promise<void> {
	const { results } = await env.umeyui_db
		.prepare(
			`SELECT DISTINCT f.token FROM fcm_tokens f
       JOIN reservations r ON f.user_id = r.user_id
       WHERE r.slot_id = ? AND r.status = 'confirmed'`,
		)
		.bind(slotId)
		.all<{ token: string }>();
	await Promise.all(results.map((r) => sendPushNotification(env, r.token, payload.title, payload.body)));
}

async function sendPushToNonParticipantAdmins(env: Env, slotId: string, payload: { title: string; body: string }): Promise<void> {
	const { results } = await env.umeyui_db
		.prepare(
			`SELECT DISTINCT f.token FROM fcm_tokens f
       JOIN users u ON f.user_id = u.id
       WHERE u.role = 'admin'
         AND u.id NOT IN (
           SELECT user_id FROM reservations WHERE slot_id = ? AND status = 'confirmed'
         )`,
		)
		.bind(slotId)
		.all<{ token: string }>();
	await Promise.all(results.map((r) => sendPushNotification(env, r.token, payload.title, payload.body)));
}

export async function sendPushToAllActive(env: Env, excludeUserId: string, title: string, body: string): Promise<void> {
	const { results } = await env.umeyui_db
		.prepare("SELECT f.token FROM fcm_tokens f JOIN users u ON f.user_id = u.id WHERE u.is_active = 1 AND u.id != ?")
		.bind(excludeUserId)
		.all<{ token: string }>();

	await Promise.all(results.map((r) => sendPushNotification(env, r.token, title, body)));
}

// 特定ユーザーに通知を作成する
export async function createNotification(
	db: D1Database,
	userId: string,
	type: string,
	slotId: string,
	message: string,
): Promise<void> {
	await db
		.prepare('INSERT INTO notifications (id, user_id, type, slot_id, message) VALUES (?, ?, ?, ?, ?)')
		.bind(crypto.randomUUID(), userId, type, slotId, message)
		.run();
}

// 全出店者（発起人除く）に通知を一括作成する
export async function createNotificationsForAllVendors(
	db: D1Database,
	excludeUserId: string,
	type: string,
	slotId: string,
	message: string,
): Promise<void> {
	const { results } = await db
		.prepare("SELECT id FROM users WHERE role = 'vendor' AND is_active = 1 AND id != ?")
		.bind(excludeUserId)
		.all<{ id: string }>();

	if (results.length === 0) return;

	// D1 batch は 100件ずつ
	const stmts = results.map(({ id }) =>
		db
			.prepare('INSERT INTO notifications (id, user_id, type, slot_id, message) VALUES (?, ?, ?, ?, ?)')
			.bind(crypto.randomUUID(), id, type, slotId, message),
	);
	for (let i = 0; i < stmts.length; i += 100) {
		await db.batch(stmts.slice(i, i + 100));
	}
}

export async function deleteChatRoom(db: D1Database, slotId: string): Promise<void> {
	const room = await db
		.prepare('SELECT id FROM chat_rooms WHERE slot_id = ?')
		.bind(slotId)
		.first<{ id: string }>();
	if (room) {
		await db.batch([
			db.prepare('DELETE FROM user_room_reads WHERE room_id = ?').bind(room.id),
			db.prepare('DELETE FROM messages WHERE room_id = ?').bind(room.id),
			db.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(room.id),
		]);
	}
}
