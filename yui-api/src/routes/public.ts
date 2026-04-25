import { Hono } from 'hono';
import { cors } from 'hono/cors';

const ALLOWED_ORIGIN = 'https://umeya.life';

export const publicRoutes = new Hono<{ Bindings: Env }>();

publicRoutes.use(
	'*',
	cors({
		origin: ALLOWED_ORIGIN,
		allowMethods: ['GET', 'OPTIONS'],
		allowHeaders: ['Content-Type'],
		maxAge: 86400,
	}),
);

// GET /public/events
// 開催確定イベント一覧（認証不要・umeya.lifeホームページ向け）
publicRoutes.get('/events', async (c) => {
	const apiOrigin = new URL(c.req.url).origin;

	const { results: slots } = await c.env.umeyui_db
		.prepare(
			`SELECT id, date, name, start_time, end_time
       FROM slots
       WHERE status = 'confirmed'
       ORDER BY date ASC`,
		)
		.all<{ id: string; date: string; name: string | null; start_time: string | null; end_time: string | null }>();

	const events = await Promise.all(
		slots.map(async (slot) => {
			const { results: participants } = await c.env.umeyui_db
				.prepare(
					`SELECT u.shop_name, u.avatar_url, u.homepage_avatar_url,
                  u.website_url, u.instagram_url, u.x_url, u.line_url, u.facebook_url
           FROM users u
           JOIN reservations r ON u.id = r.user_id
           WHERE r.slot_id = ? AND r.status = 'confirmed'
           ORDER BY r.created_at ASC`,
				)
				.bind(slot.id)
				.all<{
					shop_name: string | null;
					avatar_url: string | null;
					homepage_avatar_url: string | null;
					website_url: string | null;
					instagram_url: string | null;
					x_url: string | null;
					line_url: string | null;
					facebook_url: string | null;
				}>();

			return {
				...slot,
				participants: participants.map((p) => ({
					...p,
					avatar_url: p.avatar_url ? `${apiOrigin}${p.avatar_url}` : null,
					homepage_avatar_url: p.homepage_avatar_url ? `${apiOrigin}${p.homepage_avatar_url}` : null,
				})),
			};
		}),
	);

	return c.json({ events });
});

// GET /public/vendors
// 出店者一覧（認証不要・umeya.lifeホームページ向け）
publicRoutes.get('/vendors', async (c) => {
	const apiOrigin = new URL(c.req.url).origin;

	const { results } = await c.env.umeyui_db
		.prepare(
			`SELECT id, shop_name, bio, avatar_url, homepage_avatar_url,
              website_url, instagram_url, x_url, line_url, facebook_url
       FROM users
       WHERE role = 'vendor' AND is_active = 1
       ORDER BY created_at ASC`,
		)
		.all<{
			id: string;
			shop_name: string | null;
			bio: string | null;
			avatar_url: string | null;
			homepage_avatar_url: string | null;
			website_url: string | null;
			instagram_url: string | null;
			x_url: string | null;
			line_url: string | null;
			facebook_url: string | null;
		}>();

	const vendors = results.map((v) => ({
		...v,
		avatar_url: v.avatar_url ? `${apiOrigin}${v.avatar_url}` : null,
		homepage_avatar_url: v.homepage_avatar_url ? `${apiOrigin}${v.homepage_avatar_url}` : null,
	}));

	return c.json({ vendors });
});
