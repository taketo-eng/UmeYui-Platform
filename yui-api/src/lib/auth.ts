const PBKDF2_ITERATIONS = 100_000;

// パスワードをPBKDF2でハッシュ化（ソルト付き）
export async function hashPassword(password: string): Promise<string> {
	const encoder = new TextEncoder();
	const salt = crypto.getRandomValues(new Uint8Array(16));

	const keyMaterial = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
	const bits = await crypto.subtle.deriveBits(
		{ name: 'PBKDF2', salt, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
		keyMaterial,
		256,
	);

	const saltHex = Array.from(salt)
		.map((b) => b.toString(16).padStart(2, '0'))
		.join('');
	const hashHex = Array.from(new Uint8Array(bits))
		.map((b) => b.toString(16).padStart(2, '0'))
		.join('');
	return `pbkdf2:${saltHex}:${hashHex}`;
}

// パスワード検証（PBKDF2 / 旧SHA-256の両方に対応）
export async function verifyPassword(password: string, stored: string): Promise<boolean> {
	if (stored.startsWith('pbkdf2:')) {
		const parts = stored.split(':');
		if (parts.length !== 3) return false;
		const [, saltHex, hashHex] = parts;
		const salt = new Uint8Array(saltHex.match(/.{2}/g)!.map((b) => parseInt(b, 16)));
		const encoder = new TextEncoder();
		const keyMaterial = await crypto.subtle.importKey('raw', encoder.encode(password), 'PBKDF2', false, ['deriveBits']);
		const bits = await crypto.subtle.deriveBits(
			{ name: 'PBKDF2', salt, iterations: PBKDF2_ITERATIONS, hash: 'SHA-256' },
			keyMaterial,
			256,
		);
		const inputHash = Array.from(new Uint8Array(bits))
			.map((b) => b.toString(16).padStart(2, '0'))
			.join('');
		return inputHash === hashHex;
	} else {
		// 旧形式: SHA-256（ソルトなし）— ログイン後に自動移行される
		const encoder = new TextEncoder();
		const hashBuffer = await crypto.subtle.digest('SHA-256', encoder.encode(password));
		const hashHex = Array.from(new Uint8Array(hashBuffer))
			.map((b) => b.toString(16).padStart(2, '0'))
			.join('');
		return hashHex === stored.trim();
	}
}

// ---- JWT ----

export type JwtPayload = {
	sub: string       // user id
	role: string      // admin or vendor
	exp: number       // expiration time (unix timestamp)
	tv: number        // token version（ログアウト時に無効化するために使用）
	is_test?: boolean // テストアカウント（@example.com）
}

export async function createJwt(payload: JwtPayload, secret: string): Promise<string> {
	const encoder = new TextEncoder();

	const header = btoa(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))
		.replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

	const body = btoa(JSON.stringify(payload))
		.replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

	const key = await crypto.subtle.importKey(
		'raw',
		encoder.encode(secret),
		{ name: 'HMAC', hash: 'SHA-256' },
		false,
		['sign'],
	);

	const signature = await crypto.subtle.sign('HMAC', key, encoder.encode(`${header}.${body}`));

	const sigB64 = btoa(String.fromCharCode(...new Uint8Array(signature)))
		.replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');

	return `${header}.${body}.${sigB64}`;
}

export async function verifyJwt(token: string, secret: string): Promise<JwtPayload | null> {
	try {
		const [header, body, sig] = token.split('.');
		if (!header || !body || !sig) return null;

		const encoder = new TextEncoder();
		const key = await crypto.subtle.importKey(
			'raw',
			encoder.encode(secret),
			{ name: 'HMAC', hash: 'SHA-256' },
			false,
			['verify'],
		);

		const sigBuffer = Uint8Array.from(atob(sig.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));

		const valid = await crypto.subtle.verify('HMAC', key, sigBuffer, encoder.encode(`${header}.${body}`));
		if (!valid) return null;

		const payload: JwtPayload = JSON.parse(atob(body.replace(/-/g, '+').replace(/_/g, '/')));

		if (payload.exp < Math.floor(Date.now() / 1000)) return null;

		return payload;
	} catch {
		return null;
	}
}

export async function getAuthUser(request: Request, secret: string): Promise<JwtPayload | null> {
	const authHeader = request.headers.get('Authorization');
	if (!authHeader?.startsWith('Bearer ')) return null;

	const token = authHeader.slice(7);
	return verifyJwt(token, secret);
}
