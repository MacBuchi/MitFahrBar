// request-group – Gruppen-Konto serverseitig anlegen (bestätigungsfrei).
//
// Warum eine Edge Function: Gruppen-Logins sind Fake-Adressen
// (handle@grp.fahrgemeinschaft.app), die nie eine Bestätigungsmail einlösen
// könnten. Seit die Verwalter-Konten ihre E-Mail wirklich bestätigen müssen
// (mailer_autoconfirm aus), darf der Gruppen-Signup deshalb nicht mehr über
// den Client laufen — hier legt die Admin-API das Konto mit
// `email_confirm: true` an, ohne dass je eine Mail rausgeht (kein Bounce
// bei Brevo). Der Signup-Trigger in der DB erzeugt daraus wie bisher die
// pending-Gruppe samt Default-Settings.
//
// Das Handle-Mapping MUSS mit lib/core/group_login.dart übereinstimmen —
// der E2E-Rundlauf (test/e2e/auth_mail_e2e_test.dart) nagelt das fest.

import { createClient } from 'npm:@supabase/supabase-js@2'

const GROUP_DOMAIN = 'grp.fahrgemeinschaft.app'

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

  // Missbrauchsschutz (Issue #69): höchstens N neue pending-Gruppen je
  // Stunde, GESAMT. Bewusst global statt je IP: braucht weder neue Tabelle
  // noch IP-Speicherung (Privatsphäre), ist über Isolate-Neustarts hinweg
  // durabel (zählt die DB-Wahrheit) und neutralisiert Skript-Massenanlagen
  // vollständig — echte Fahrgemeinschaften entstehen ein paar Mal pro
  // Woche, nicht pro Stunde. Kehrseite (dokumentiert): Während eines
  // Angriffs warten auch echte Anfragen — bei pending-Freigabe ohnehin
  // kein Beinbruch. Lokal hebt supabase/functions/.env die Grenze an,
  // sonst liefe die E2E-Suite hinein.
  const hourlyCap = Number(Deno.env.get('SIGNUP_HOURLY_CAP') ?? '5')
  const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
  const { count, error: countError } = await admin
    .from('groups')
    .select('id', { count: 'exact', head: true })
    .eq('status', 'pending')
    .gte('created_at', oneHourAgo)
  if (countError) {
    console.error('rate check failed:', countError.code)
    return respond(500, { error: 'signup failed' })
  }
  if ((count ?? 0) >= hourlyCap) {
    return respond(429, { error: 'too many requests' })
  }

  const { error } = await admin.auth.admin.createUser({
    email: `${handle}@${GROUP_DOMAIN}`,
    password,
    email_confirm: true,
    user_metadata: { group_name: groupName },
  })
  if (error) {
    if (error.code === 'email_exists' || error.status === 422) {
      return respond(409, { error: 'handle already taken' })
    }
    // Nur die Fehlerklasse loggen — nie Handle oder gar Passwort.
    console.error('createUser failed:', error.code ?? error.status)
    return respond(500, { error: 'signup failed' })
  }
  return respond(200, { ok: true })
})
