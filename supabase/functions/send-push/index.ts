// send-push – verschickt Benachrichtigungen über FCM (Issue #101).
//
// Zwei Aufrufer, zwei Ausweise:
//
//   1. Der Versand-Job (tool/notify.dart, GitHub Actions) schickt den Header
//      `x-push-secret`. Er darf beliebige Nachrichten senden.
//   2. Die App schickt „einmal an dieses Gerät" zum Ausprobieren. Sie hat das
//      Geheimnis nicht — stattdessen prüft die Function mit dem JWT der
//      Nutzerin, ob das Token in DEREN Gruppe registriert ist. Die RLS
//      erledigt das; eine eigene Prüfung wäre eine zweite Wahrheit.
//
// `verify_jwt` steht in config.toml auf false, weil der Job kein JWT hat:
// Ein `sb_secret_*`-Service-Role-Key ist keines mehr. Die Prüfung passiert
// deshalb hier im Rumpf — beide Wege sind unten explizit.
//
// Das Dienstkonto liegt base64-kodiert in `FCM_SERVICE_ACCOUNT`
// (`supabase secrets set`). Base64, weil mehrzeiliges JSON beim Setzen an
// Zeilenumbrüchen und Anführungszeichen scheitert.

import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-push-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function respond(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

interface ServiceAccount {
  project_id: string
  client_email: string
  private_key: string
}

function serviceAccount(): ServiceAccount {
  const raw = Deno.env.get('FCM_SERVICE_ACCOUNT')
  if (!raw) throw new Error('missing service account')
  return JSON.parse(new TextDecoder().decode(base64ToBytes(raw)))
}

function base64ToBytes(value: string): Uint8Array {
  const binary = atob(value.replace(/\s/g, ''))
  return Uint8Array.from(binary, (c) => c.charCodeAt(0))
}

function base64Url(bytes: Uint8Array | string): string {
  const binary = typeof bytes === 'string'
    ? bytes
    : String.fromCharCode(...bytes)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

// Zugriffstoken für die Laufzeit der Instanz behalten: Sie gelten eine
// Stunde, und ein Signieren je Nachricht wäre reine Rechenzeit.
let cachedToken: { value: string; expires: number } | null = null

async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && cachedToken.expires > now + 60) return cachedToken.value

  const header = base64Url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const claims = base64Url(
    JSON.stringify({
      iss: account.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  )

  // Der private Schlüssel kommt als PEM; für WebCrypto muss der Rumpf raus.
  const pem = account.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
  const key = await crypto.subtle.importKey(
    'pkcs8',
    base64ToBytes(pem),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      key,
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  )
  const assertion = `${header}.${claims}.${base64Url(signature)}`

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  })
  if (!response.ok) throw new Error(`token ${response.status}`)
  const payload = await response.json()
  cachedToken = {
    value: payload.access_token,
    expires: now + Number(payload.expires_in ?? 3600),
  }
  return cachedToken.value
}

interface Message {
  token: string
  title: string
  body: string
}

/// Ergebnis je Token: 'ok', 'unregistered' (der Job räumt die Zeile weg)
/// oder 'error'.
async function send(
  account: ServiceAccount,
  bearer: string,
  message: Message,
): Promise<string> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${bearer}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: message.token,
          notification: { title: message.title, body: message.body },
          // Ein Tipp führt in den Planer; die App liest das im
          // onMessageOpenedApp-Handler.
          data: { route: '/plan' },
          android: { priority: 'high' },
          webpush: { fcmOptions: { link: '/MitFahrBar/' } },
        },
      }),
    },
  )
  if (response.ok) return 'ok'
  // 404 UNREGISTERED = App deinstalliert oder Token abgelaufen.
  if (response.status === 404) return 'unregistered'
  console.error('fcm', response.status)
  return 'error'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') return respond(405, { error: 'method not allowed' })

  let payload: { messages?: Message[]; test?: string }
  try {
    payload = await req.json()
  } catch {
    return respond(400, { error: 'invalid json' })
  }

  const expected = Deno.env.get('PUSH_JOB_SECRET')
  const isJob = !!expected && req.headers.get('x-push-secret') === expected

  let messages: Message[]
  if (isJob) {
    messages = payload.messages ?? []
  } else if (payload.test) {
    // Nur an ein Gerät der eigenen Gruppe. Die Sichtbarkeit entscheidet die
    // RLS: Wir fragen mit dem JWT der Nutzerin, nicht mit service_role.
    const authorization = req.headers.get('Authorization')
    if (!authorization) return respond(401, { error: 'unauthorized' })
    const client = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authorization } } },
    )
    const { data } = await client
      .from('push_devices')
      .select('token')
      .eq('token', payload.test)
      .maybeSingle()
    if (!data) return respond(403, { error: 'unknown device' })
    messages = [
      {
        token: payload.test,
        title: 'MitFahrBar',
        body: 'Test — so sieht eine Benachrichtigung aus.',
      },
    ]
  } else {
    return respond(401, { error: 'unauthorized' })
  }

  if (messages.length === 0) return respond(200, { results: [] })

  let account: ServiceAccount
  let bearer: string
  try {
    account = serviceAccount()
    bearer = await accessToken(account)
  } catch (error) {
    console.error('fcm auth', (error as Error).message)
    return respond(500, { error: 'fcm auth failed' })
  }

  // Nacheinander statt parallel: Es geht um eine Handvoll Nachrichten je
  // Lauf, und FCM quittiert Bursts aus einer Edge Function mit 429.
  const results: { token: string; status: string }[] = []
  for (const message of messages) {
    results.push({
      token: message.token,
      status: await send(account, bearer, message),
    })
  }
  return respond(200, { results })
})
