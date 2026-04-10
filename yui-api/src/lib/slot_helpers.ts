// 枠確定・チャットルーム削除・通知作成の共通処理

export async function confirmSlot(db: D1Database, slotId: string): Promise<void> {
	const roomId = crypto.randomUUID();
	await db.batch([
		db.prepare("UPDATE slots SET status = 'confirmed' WHERE id = ?").bind(slotId),
		db.prepare("UPDATE reservations SET status = 'confirmed' WHERE slot_id = ? AND status = 'pending'").bind(slotId),
		db.prepare('INSERT INTO chat_rooms (id, slot_id) VALUES (?, ?)').bind(roomId, slotId),
	]);
	await sendPushToParticipants(db, slotId, {
		title: '開催確定！',
		body: 'チャットルームが開きました。当日に向けて話し合いましょう！',
	});
}

async function sendPushToParticipants(db: D1Database, slotId: string, payload: { title: string; body: string }): Promise<void> {
	const { results } = await db
		.prepare(
			`
      SELECT u.push_token FROM users u
      JOIN reservations r ON u.id = r.user_id
      WHERE r.slot_id = ? AND r.status = 'confirmed' AND u.push_token IS NOT NULL
    `,
		)
		.bind(slotId)
		.all<{ push_token: string }>();

	// TODO: FCM / APNs への実際の送信処理はFlutter連携時に実装
	console.log('[Push] 参加者への通知:', payload.title, '→', results.length, '件');
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
			db.prepare('DELETE FROM messages WHERE room_id = ?').bind(room.id),
			db.prepare('DELETE FROM chat_rooms WHERE id = ?').bind(room.id),
		]);
	}
}
