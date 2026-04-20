// ユーザーIDに紐づく全デバイスに送信（複数デバイス対応）
export async function sendPushToUser(env: Env, userId: string, title: string, body: string, data?: Record<string, string>): Promise<void> {
	try {
		const { results } = await env.umeyui_db
			.prepare('SELECT token FROM fcm_tokens WHERE user_id = ?')
			.bind(userId)
			.all<{ token: string }>();
		await Promise.all(results.map((r) => sendPushNotification(env, r.token, title, body, data)));
	} catch {
		// 通知失敗はメイン処理を止めない
	}
}

export async function sendPushNotification(
	env: Env,
	pushToken: string,
	title: string,
	body: string,
	data?: Record<string, string>,
): Promise<void> {
	try {
		const accessToken = await getFCMAccessToken(env);
		await fetch(`https://fcm.googleapis.com/v1/projects/${env.FIREBASE_PROJECT_ID}/messages:send`, {
			method: 'POST',
			headers: {
				Authorization: `Bearer ${accessToken}`,
				'Content-Type': 'application/json',
			},
			body: JSON.stringify({
				message: {
					token: pushToken,
					notification: { title, body },
					data: data ?? {},
				},
			}),
		});
	} catch {
		// 通知失敗はメイン処理を止めない
	}
}

async function getFCMAccessToken(env: Env): Promise<string> {
	const now = Math.floor(Date.now() / 1000);
	const payload = {
		iss: env.FIREBASE_CLIENT_EMAIL,
		scope: 'https://www.googleapis.com/auth/firebase.messaging',
		aud: 'https://oauth2.googleapis.com/token',
		iat: now,
		exp: now + 3600,
	};

	const jwt = await signJWT(payload, env.FIREBASE_PRIVATE_KEY);

	const res = await fetch('https://oauth2.googleapis.com/token', {
		method: 'POST',
		headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
		body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
	});

	const data = (await res.json()) as { access_token: string };
	return data.access_token;
}

async function signJWT(payload: object, privateKeyPem: string): Promise<string> {
	const header = { alg: 'RS256', typ: 'JWT' };
	const encode = (obj: object) => btoa(JSON.stringify(obj)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');

	const signingInput = `${encode(header)}.${encode(payload)}`;

	const pemBody = privateKeyPem
		.replace(/-----BEGIN PRIVATE KEY-----/, '')
		.replace(/-----END PRIVATE KEY-----/, '')
		.replace(/\\n/g, '')
		.replace(/\n/g, '');

	const keyData = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
	const key = await crypto.subtle.importKey('pkcs8', keyData, { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' }, false, ['sign']);

	const signature = await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, new TextEncoder().encode(signingInput));

	const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
		.replace(/\+/g, '-')
		.replace(/\//g, '_')
		.replace(/=/g, '');

	return `${signingInput}.${sig}`;
}
