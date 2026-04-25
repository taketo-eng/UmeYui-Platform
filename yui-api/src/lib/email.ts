import { Resend } from 'resend';

const FROM_ADDRESS = 'noreply@umeya.life';
const APP_NAME = 'UmeYui';

export async function sendPasswordChangeCode(apiKey: string, toEmail: string, code: string): Promise<void> {
	const resend = new Resend(apiKey);
	await resend.emails.send({
		from: `${APP_NAME} <${FROM_ADDRESS}>`,
		to: toEmail,
		subject: '【UmeYui】パスワード変更の確認コード',
		html: `
			<p>パスワード変更のリクエストを受け付けました。</p>
			<p>以下の確認コードをアプリに入力してください。</p>
			<h2 style="letter-spacing: 8px; font-size: 32px;">${code}</h2>
			<p style="color: #888; font-size: 13px;">このコードは30分間有効です。身に覚えのない場合はこのメールを無視してください。</p>
		`,
	});
}

export async function sendPasswordResetCode(apiKey: string, toEmail: string, code: string): Promise<void> {
	const resend = new Resend(apiKey);
	await resend.emails.send({
		from: `${APP_NAME} <${FROM_ADDRESS}>`,
		to: toEmail,
		subject: '【UmeYui】パスワードリセットの確認コード',
		html: `
			<p>パスワードリセットのリクエストを受け付けました。</p>
			<p>以下の確認コードをアプリに入力してください。</p>
			<h2 style="letter-spacing: 8px; font-size: 32px;">${code}</h2>
			<p style="color: #888; font-size: 13px;">このコードは10分間有効です。身に覚えのない場合はこのメールを無視してください。</p>
		`,
	});
}

export async function sendEmailChangeCode(apiKey: string, toEmail: string, code: string): Promise<void> {
	const resend = new Resend(apiKey);
	await resend.emails.send({
		from: `${APP_NAME} <${FROM_ADDRESS}>`,
		to: toEmail,
		subject: '【UmeYui】メールアドレス変更の確認コード',
		html: `
			<p>メールアドレス変更のリクエストを受け付けました。</p>
			<p>以下の確認コードをアプリに入力してください。</p>
			<h2 style="letter-spacing: 8px; font-size: 32px;">${code}</h2>
			<p style="color: #888; font-size: 13px;">このコードは30分間有効です。身に覚えのない場合はこのメールを無視してください。</p>
		`,
	});
}
