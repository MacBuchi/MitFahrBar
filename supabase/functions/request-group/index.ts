// request-group – Gruppen-Konto serverseitig anlegen (bestätigungsfrei).
//
// Warum eine Edge Function: Gruppen-Logins sind Fake-Adressen
// (handle@grp.fahrgemeinschaft.app), die nie eine Bestätigungsmail einlösen
// könnten. Seit die Verwalter-Konten ihre E-Mail wirklich bestätigen müssen
// (mailer_autoconfirm aus), darf der Gruppen-Signup deshalb nicht über den
// Client laufen — hier legt die Admin-API das Konto mit
// `email_confirm: true` an, ohne dass je eine Mail rausgeht (kein Bounce
// bei Brevo).
//
// SEIT #106 IST DER AUFRUFER EIN VERWALTER-KONTO, nicht mehr die Allgemeinheit.
// Drei Dinge hängen daran:
//
// 1. `verify_jwt = true` in config.toml genügt NICHT als Zugangsschutz: Der
//    anon-Key ist selbst ein gültiges JWT. Ohne die `getUser`-Prüfung unten
//    wäre dieser Endpunkt nach dem Wegfall des Stundenlimits eine offene,
//    unlimitierte Gruppenfabrik — schlechter als vorher. Der E2E-Test
//    „anonym → 401" ist der Wächter dafür.
// 2. Das frühere Stundenlimit (SIGNUP_HOURLY_CAP, #69) ist weg, und mit ihm
//    der Grund für die vorgemerkte Turnstile-Idee: Wer eine Gruppe anlegen
//    will, braucht jetzt ein bestätigtes Postfach und ist auf 5 Gruppen
//    gedeckelt. Der Deckel gilt serverseitig doppelt — hier als klare
//    Fehlermeldung, und im Trigger `group_admins_cap` als Wahrheit.
// 3. Die Gruppe entsteht AKTIV UND VERKNÜPFT, in einem Zug. Bliebe einer der
//    beiden Schritte aus, hätte man genau das, was #106 abschaffen wollte:
//    eine Gruppe, die niemandem gehört. Scheitert der zweite Schritt, wird
//    der frisch angelegte Auth-User wieder entfernt — sonst blockierte ein
//    Handle für immer, ohne dass jemand ihn nutzen kann.
//
// Das Handle-Mapping MUSS mit lib/core/group_login.dart übereinstimmen —
// der E2E-Rundlauf (test/e2e/auth_mail_e2e_test.dart) nagelt das fest.

import { createClient } from 'npm:@supabase/supabase-js@2'

const GROUP_DOMAIN = 'grp.fahrgemeinschaft.app'

// Muss mit dem Deckel im Trigger `group_admins_cap` übereinstimmen.
const GROUP_CAP = 5

const normalizeHandle = (input: string) =>
  input.trim().toLowerCase().replace(/[^a-z0-9._-]/g, '')

// Die Web-App ruft die Function aus dem Browser auf — ohne CORS-Antworten
// blockt der Preflight jede Registrierung.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const respond = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') {
    return respond(405, { error: 'method not allowed' })
  }

  let payload: Record<string, unknown>
  try {
    payload = await req.json()
  } catch {
    return respond(400, { error: 'invalid json' })
  }

  const handle = normalizeHandle(String(payload.handle ?? ''))
  const password = String(payload.password ?? '')
  const groupName = String(payload.groupName ?? '').trim()
  if (handle.length < 3) return respond(400, { error: 'invalid handle' })
  if (password.length < 8) return respond(400, { error: 'password too short' })
  if (groupName.length === 0) {
    return respond(400, { error: 'missing group name' })
  }

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // Wer ruft? Nur ein Verwalter-Konto mit bestätigtem Postfach darf anlegen.
  // Ein Gruppen-Login (kein `account_type`) wird ebenso abgewiesen wie der
  // anon-Key, der zwar ein JWT ist, aber keinen Nutzer trägt.
  const bearer = req.headers.get('Authorization')?.replace(/^Bearer /, '') ?? ''
  const { data: caller } = await admin.auth.getUser(bearer)
  if (!caller.user) return respond(401, { error: 'unauthorized' })
  if (caller.user.user_metadata?.account_type !== 'admin') {
    return respond(403, { error: 'not an admin account' })
  }
  if (!caller.user.email_confirmed_at) {
    return respond(403, { error: 'email not confirmed' })
  }

  // Vorprüfung des Deckels: liefert eine klare Meldung, statt den Aufrufer in
  // den Trigger laufen zu lassen. Die Wahrheit bleibt der Trigger — zwei
  // gleichzeitige Anlagen kämen hier beide durch.
  const { count, error: countError } = await admin
    .from('group_admins')
    .select('group_id', { count: 'exact', head: true })
    .eq('user_id', caller.user.id)
  if (countError) {
    console.error('cap check failed:', countError.code)
    return respond(500, { error: 'signup failed' })
  }
  if ((count ?? 0) >= GROUP_CAP) {
    return respond(429, { error: 'group limit reached' })
  }

  const { data: created, error } = await admin.auth.admin.createUser({
    email: `${handle}@${GROUP_DOMAIN}`,
    password,
    email_confirm: true,
    user_metadata: { group_name: groupName },
  })
  if (error || !created.user) {
    if (error?.code === 'email_exists' || error?.status === 422) {
      return respond(409, { error: 'handle already taken' })
    }
    // Nur die Fehlerklasse loggen — nie Handle oder gar Passwort.
    console.error('createUser failed:', error?.code ?? error?.status)
    return respond(500, { error: 'signup failed' })
  }

  // Der Signup-Trigger hat die Gruppe als 'pending' angelegt (er traut
  // Metadata bewusst nicht). Freischalten und verknüpfen gehören zusammen:
  // Was hier scheitert, wird zurückgenommen.
  const groupId = created.user.id
  const finish = async () => {
    const { error: activateError } = await admin
      .from('groups')
      .update({ status: 'active' })
      .eq('id', groupId)
    if (activateError) return activateError
    const { error: linkError } = await admin
      .from('group_admins')
      .insert({ user_id: caller.user!.id, group_id: groupId })
    return linkError
  }

  const failure = await finish()
  if (failure) {
    await admin.auth.admin.deleteUser(groupId)
    if ((failure.message ?? '').includes('group limit reached')) {
      return respond(429, { error: 'group limit reached' })
    }
    console.error('group setup failed:', failure.code)
    return respond(500, { error: 'signup failed' })
  }

  return respond(200, { ok: true })
})
