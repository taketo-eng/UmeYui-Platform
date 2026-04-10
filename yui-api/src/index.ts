import {Hono} from 'hono'
import { authRoutes } from './routes/auth'
import { userRoutes } from './routes/users'
import { slotRoutes } from './routes/slots'
import { reservationRoutes } from './routes/reservations'
import { chatRoutes } from './routes/chat'
import { slotJoinRequestRoutes, joinRequestRoutes } from './routes/join_requests'
import { notificationRoutes } from './routes/notifications'

const app = new Hono<{ Bindings: Env }>()

app.route('/auth', authRoutes)
app.route('/users', userRoutes)
app.route('/slots', slotRoutes)
app.route('/slots', reservationRoutes)
app.route('/slots', slotJoinRequestRoutes)
app.route('/join-requests', joinRequestRoutes)
app.route('/notifications', notificationRoutes)
app.route('/chat-rooms', chatRoutes)

// GET /avatars/:filename
// 認証不要: R2 からアバター画像を配信
app.get('/avatars/:filename', async (c) => {
	const { filename } = c.req.param()
	const object = await c.env.AVATAR_BUCKET.get(`avatars/${filename}`)

	if (!object) return c.json({ error: 'Not found' }, 404)

	const headers = new Headers()
	object.writeHttpMetadata(headers)
	headers.set('etag', object.httpEtag)
	headers.set('cache-control', 'public, max-age=86400')

	return new Response(object.body, { headers })
})

export default app