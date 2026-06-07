const FROM_EMAIL = process.env.RESEND_FROM_EMAIL ?? 'Habio <onboarding@resend.dev>'

async function sendEmail(params: {
  to: string
  subject: string
  html: string
}): Promise<void> {
  const apiKey = process.env.RESEND_API_KEY

  if (!apiKey) {
    console.info('[email] RESEND_API_KEY not set — skipping send', {
      to: params.to,
      subject: params.subject,
    })
    return
  }

  const response = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: FROM_EMAIL,
      to: [params.to],
      subject: params.subject,
      html: params.html,
    }),
  })

  if (!response.ok) {
    const body = await response.text()
    console.error('[email] Resend API error:', response.status, body)
  }
}

export async function sendInvitationEmail(params: {
  to: string
  inviteUrl: string
  role: string
  propertyName?: string | null
}): Promise<void> {
  const scope = params.propertyName ? ` for ${params.propertyName}` : ''
  await sendEmail({
    to: params.to,
    subject: `You have been invited to join Habio as ${params.role}`,
    html: `
      <p>You have been invited to join Habio as <strong>${params.role}</strong>${scope}.</p>
      <p><a href="${params.inviteUrl}">Accept invitation</a></p>
      <p>This link expires in 7 days.</p>
    `,
  })
}

export async function sendActivationEmail(params: {
  to: string
  activateUrl: string
  propertyName?: string | null
  roomNumber?: string | null
}): Promise<void> {
  const location =
    params.propertyName && params.roomNumber
      ? ` at ${params.propertyName}, room ${params.roomNumber}`
      : params.propertyName
        ? ` at ${params.propertyName}`
        : ''

  await sendEmail({
    to: params.to,
    subject: 'Activate your Habio tenant account',
    html: `
      <p>You have been invited to activate your tenant account${location}.</p>
      <p><a href="${params.activateUrl}">Activate account</a></p>
      <p>This link expires in 7 days.</p>
    `,
  })
}
