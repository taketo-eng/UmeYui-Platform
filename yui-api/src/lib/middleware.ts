import { Context } from 'hono';
import { getAuthUser, JwtPayload } from './auth';

// ログイン済みかチェック（role問わず）
// JWTの署名・有効期限に加え、token_versionがDBと一致するか検証
export async function requireAuth(c: Context<{ Bindings: Env }>): Promise<JwtPayload | null> {
	const user = await getAuthUser(c.req.raw, c.env.JWT_SECRET);
	if (!user) {
		c.res = c.json({ error: '認証が必要です' }, 401) as any;
		return null;
	}

	// token_versionをDBと照合（ログアウト済みトークンを無効化）
	const dbUser = await c.env.umeyui_db
		.prepare('SELECT token_version FROM users WHERE id = ?')
		.bind(user.sub)
		.first<{ token_version: number }>();

	if (!dbUser || user.tv !== dbUser.token_version) {
		c.res = c.json({ error: '認証が必要です' }, 401) as any;
		return null;
	}

	return user;
}

// 管理者のみ許可
export async function requireAdmin(c: Context<{ Bindings: Env }>): Promise<JwtPayload | null> {
	const user = await requireAuth(c);
	if (!user) return null;
	if (user.role !== 'admin') {
		c.res = c.json({ error: '管理者権限が必要です' }, 403) as any;
		return null;
	}
	return user;
}
