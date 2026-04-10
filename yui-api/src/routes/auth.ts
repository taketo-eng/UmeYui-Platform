import { Hono } from 'hono';
import { verifyPassword, createJwt, getAuthUser, hashPassword } from '../lib/auth';
import { sendPasswordChangeCode, sendEmailChangeCode } from '../lib/email';

export const authRoutes = new Hono<{ Bindings: Env }>();

const LOGIN_MAX_ATTEMPTS = 10;
const LOGIN_WINDOW_MINUTES = 15;

// POST /auth/login
authRoutes.post('/login', async (c) => {
	const { email, password } = await c.req.json();

	if (!email || !password) {
		return c.json({ error: 'メールアドレスとパスワードを入力してください' }, 400);
	}

	// ---- レート制限チェック ----
	const ip = c.req.header('CF-Connecting-IP') ?? c.req.header('X-Forwarded-For') ?? 'unknown';
	const cutoff = new Date(Date.now() - LOGIN_WINDOW_MINUTES * 60 * 1000).toISOString().replace('T', ' ').slice(0, 19);

	// 古いレコードを削除してからカウント
	await c.env.umeyui_db.prepare('DELETE FROM login_attempts WHERE attempted_at < ?').bind(cutoff).run();

	const attemptResult = await c.env.umeyui_db
		.prepare('SELECT COUNT(*) AS count FROM login_attempts WHERE ip = ?')
		.bind(ip)
		.first<{ count: number }>();

	if ((attemptResult?.count ?? 0) >= LOGIN_MAX_ATTEMPTS) {
		return c.json({ error: `ログイン試行が多すぎます。${LOGIN_WINDOW_MINUTES}分後にお試しください。` }, 429);
	}

	// ---- ユーザー認証 ----
	const user = await c.env.umeyui_db
		.prepare('SELECT * FROM users WHERE email = ? AND is_active = 1')
		.bind(email)
		.first<{
			id: string;
			email: string;
			role: string;
			shop_name: string;
			bio: string | null;
			avatar_url: string | null;
			is_active: number;
			password_hash: string;
			token_version: number;
		}>();

	if (!user) {
		await c.env.umeyui_db.prepare('INSERT INTO login_attempts (ip) VALUES (?)').bind(ip).run();
		return c.json({ error: 'メールアドレスまたはパスワードが違います' }, 401);
	}

	const valid = await verifyPassword(password, user.password_hash);

	if (!valid) {
		await c.env.umeyui_db.prepare('INSERT INTO login_attempts (ip) VALUES (?)').bind(ip).run();
		return c.json({ error: 'メールアドレスまたはパスワードが違います' }, 401);
	}

	// ログイン成功: 試行記録をクリア
	await c.env.umeyui_db.prepare('DELETE FROM login_attempts WHERE ip = ?').bind(ip).run();

	// 旧SHA-256ハッシュのユーザーを自動でPBKDF2に移行
	if (!user.password_hash.startsWith('pbkdf2:')) {
		const newHash = await hashPassword(password);
		await c.env.umeyui_db.prepare('UPDATE users SET password_hash = ? WHERE id = ?').bind(newHash, user.id).run();
	}

	const token = await createJwt(
		{
			sub: user.id,
			role: user.role,
			exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 30,
			tv: user.token_version,
		},
		c.env.JWT_SECRET,
	);

	return c.json({
		token,
		user: {
			id: user.id,
			email: user.email,
			role: user.role,
			shop_name: user.shop_name,
			bio: user.bio,
			avatar_url: user.avatar_url,
			is_active: user.is_active,
		},
	});
});

// POST /auth/logout
// token_versionをインクリメントして既存トークンを無効化
authRoutes.post('/logout', async (c) => {
	const authUser = await getAuthUser(c.req.raw, c.env.JWT_SECRET);
	if (authUser) {
		await c.env.umeyui_db
			.prepare('UPDATE users SET token_version = token_version + 1 WHERE id = ?')
			.bind(authUser.sub)
			.run();
	}
	return c.json({ message: 'ログアウトしました' });
});

// POST /auth/change-password
// 現在のパスワードを確認し、確認コードをメールで送信する（仮申請）
authRoutes.post('/change-password', async (c) => {
	const authUser = await getAuthUser(c.req.raw, c.env.JWT_SECRET);
	if (!authUser) {
		return c.json({ error: '認証が必要です' }, 401);
	}

	const { current_password, new_password } = await c.req.json();
	if (!current_password || !new_password) {
		return c.json({ error: 'パスワードを入力してください' }, 400);
	}
	if (new_password.length < 8) {
		return c.json({ error: 'パスワードは8文字以上にしてください' }, 400);
	}

	const user = await c.env.umeyui_db
		.prepare('SELECT password_hash, email FROM users WHERE id = ?')
		.bind(authUser.sub)
		.first<{ password_hash: string; email: string }>();

	if (!user) return c.json({ error: 'ユーザーが見つかりません' }, 404);

	const valid = await verifyPassword(current_password, user.password_hash);
	if (!valid) return c.json({ error: '現在のパスワードが違います' }, 401);

	// 同じユーザーの既存トークンを削除して新規発行
	await c.env.umeyui_db.prepare('DELETE FROM password_change_tokens WHERE user_id = ?').bind(authUser.sub).run();

	const codeArray = new Uint32Array(1);
	crypto.getRandomValues(codeArray);
	const code = (100000 + (codeArray[0] % 900000)).toString();
	const tokenId = crypto.randomUUID();
	const newHash = await hashPassword(new_password);
	const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString().replace('T', ' ').slice(0, 19);

	await c.env.umeyui_db
		.prepare('INSERT INTO password_change_tokens (id, user_id, code, new_password_hash, expires_at) VALUES (?, ?, ?, ?, ?)')
		.bind(tokenId, authUser.sub, code, newHash, expiresAt)
		.run();

	await sendPasswordChangeCode(c.env.RESEND_API_KEY, user.email, code);

	// メールアドレスを一部マスクして返す（フロントで表示用）
	const [localPart, domain] = user.email.split('@');
	const maskedEmail = `${localPart.slice(0, 2)}****@${domain}`;

	return c.json({ message: '確認コードをメールで送信しました', email_hint: maskedEmail });
});

// POST /auth/change-email
// 現在のパスワードを確認して確認コードを旧メアドに送信
authRoutes.post('/change-email', async (c) => {
	const authUser = await getAuthUser(c.req.raw, c.env.JWT_SECRET);
	if (!authUser) return c.json({ error: '認証が必要です' }, 401);

	const { current_password } = await c.req.json();
	if (!current_password) return c.json({ error: 'パスワードを入力してください' }, 400);

	const user = await c.env.umeyui_db
		.prepare('SELECT password_hash, email FROM users WHERE id = ?')
		.bind(authUser.sub)
		.first<{ password_hash: string; email: string }>();

	if (!user) return c.json({ error: 'ユーザーが見つかりません' }, 404);

	const valid = await verifyPassword(current_password, user.password_hash);
	if (!valid) return c.json({ error: 'パスワードが違います' }, 401);

	// 既存トークンを削除して新規発行
	await c.env.umeyui_db.prepare('DELETE FROM email_change_tokens WHERE user_id = ?').bind(authUser.sub).run();

	const codeArray = new Uint32Array(1);
	crypto.getRandomValues(codeArray);
	const code = (100000 + (codeArray[0] % 900000)).toString();
	const tokenId = crypto.randomUUID();
	const expiresAt = new Date(Date.now() + 30 * 60 * 1000).toISOString().replace('T', ' ').slice(0, 19);

	await c.env.umeyui_db
		.prepare('INSERT INTO email_change_tokens (id, user_id, code, expires_at) VALUES (?, ?, ?, ?)')
		.bind(tokenId, authUser.sub, code, expiresAt)
		.run();

	await sendEmailChangeCode(c.env.RESEND_API_KEY, user.email, code);

	const [localPart, domain] = user.email.split('@');
	const maskedEmail = `${localPart.slice(0, 2)}****@${domain}`;

	return c.json({ message: '確認コードをメールで送信しました', email_hint: maskedEmail });
});

// POST /auth/verify-email-change
// 確認コード + 新しいメールアドレスを受け取って変更確定
authRoutes.post('/verify-email-change', async (c) => {
	const authUser = await getAuthUser(c.req.raw, c.env.JWT_SECRET);
	if (!authUser) return c.json({ error: '認証が必要です' }, 401);

	const { code, new_email } = await c.req.json();
	if (!code || !new_email) return c.json({ error: 'コードと新しいメールアドレスを入力してください' }, 400);

	if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(new_email)) {
		return c.json({ error: 'メールアドレスの形式が正しくありません' }, 400);
	}

	const now = new Date().toISOString().replace('T', ' ').slice(0, 19);
	const token = await c.env.umeyui_db
		.prepare('SELECT id FROM email_change_tokens WHERE user_id = ? AND code = ? AND expires_at > ?')
		.bind(authUser.sub, code, now)
		.first<{ id: string }>();

	if (!token) return c.json({ error: '確認コードが無効または期限切れです' }, 400);

	// 重複チェック
	const existing = await c.env.umeyui_db
		.prepare('SELECT id FROM users WHERE email = ? AND id != ?')
		.bind(new_email, authUser.sub)
		.first();
	if (existing) return c.json({ error: 'このメールアドレスはすでに使用されています' }, 409);

	// メール変更 + token_versionインクリメント（他端末のセッションを無効化）
	await c.env.umeyui_db.batch([
		c.env.umeyui_db
			.prepare('UPDATE users SET email = ?, token_version = token_version + 1 WHERE id = ?')
			.bind(new_email, authUser.sub),
		c.env.umeyui_db.prepare('DELETE FROM email_change_tokens WHERE id = ?').bind(token.id),
	]);

	return c.json({ message: 'メールアドレスを変更しました' });
});

// POST /auth/verify-password-change
// 確認コードを検証してパスワードを確定する
authRoutes.post('/verify-password-change', async (c) => {
	const authUser = await getAuthUser(c.req.raw, c.env.JWT_SECRET);
	if (!authUser) {
		return c.json({ error: '認証が必要です' }, 401);
	}

	const { code } = await c.req.json();
	if (!code) return c.json({ error: '確認コードを入力してください' }, 400);

	const now = new Date().toISOString().replace('T', ' ').slice(0, 19);
	const token = await c.env.umeyui_db
		.prepare('SELECT * FROM password_change_tokens WHERE user_id = ? AND code = ? AND expires_at > ?')
		.bind(authUser.sub, code, now)
		.first<{ id: string; new_password_hash: string }>();

	if (!token) {
		return c.json({ error: '確認コードが無効または期限切れです' }, 400);
	}

	// パスワード変更 + token_versionインクリメント（他端末のセッションを無効化）
	await c.env.umeyui_db.batch([
		c.env.umeyui_db
			.prepare('UPDATE users SET password_hash = ?, token_version = token_version + 1 WHERE id = ?')
			.bind(token.new_password_hash, authUser.sub),
		c.env.umeyui_db.prepare('DELETE FROM password_change_tokens WHERE id = ?').bind(token.id),
	]);

	return c.json({ message: 'パスワードを変更しました' });
});
