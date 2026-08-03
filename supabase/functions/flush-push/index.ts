// flush-push – schickt raus, was im Ausgangskorb fällig ist (Issue #132).
//
// Geweckt von pg_cron (jede Minute, `flush_due_push()` in der Migration
// 20260729140000). Der Takt ist nur die Uhr — der Gewinn gegenüber dem
// bisherigen GitHub-Actions-Cron ist, dass diese Uhr **zuverlässig** ist:
// GitHub verwarf geplante Läufe unter Last und holte sie nicht nach (#115,
// real oft stündlich statt alle zehn Minuten).
//
// **Diese Function entscheidet nichts über die Fairness.** Der Text steht
// fertig im Korb, gerechnet vom Client mit dem echten `planWeek`. Welche
// Zeilen fällig sind, sagt `push_due()` in SQL — Zeitfenster (Europe/Berlin,
// über Sommerzeitwechsel hinweg), Vergleich mit `push_log`, Mindestabstand.
// Hier bleibt: senden, protokollieren, quittieren.
//
// **Gesendet wird über `send-push`, nicht direkt über FCM.** Es gibt damit
// weiterhin genau EINEN Versender — dieselbe Stelle, die auch der Testknopf
// und (bis zur Umstellung) der Actions-Job benutzen. Ein zweiter FCM-Aufruf
// hier wäre eine zweite Wahrheit über Payload-Aufbau und Fehlerbehandlung.
//
// `verify_jwt` steht in config.toml auf false: Der Aufruf kommt aus der
// Datenbank und hat kein JWT. Der Ausweis ist `x-push-secret`, wie beim Job.

import { createClient } from 'npm:@supabase/supabase-js@2'

interface DueRow {
  token: string
  group_id: string
  person_id: string
  plan_date: string
  kind: string
  digest: string
  title: string
  body: string
}

function respond(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return respond(405, { error: 'method not allowed' })

  const expected = Deno.env.get('PUSH_JOB_SECRET')
  if (!expected || req.headers.get('x-push-secret') !== expected) {
    return respond(401, { error: 'unauthorized' })
  }

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const client = createClient(url, serviceKey)

  const { data, error } = await client.rpc('push_due')
  if (error) {
    console.error('push_due', error.message)
    return respond(500, { error: 'push_due failed' })
  }
  const due = (data ?? []) as DueRow[]
  if (due.length === 0) return respond(200, { sent: 0 })

  // Eine Nachricht je Person und Tag, aber an alle ihre Geräte.
  const byMessage = new Map<string, DueRow[]>()
  for (const row of due) {
    const key = `${row.group_id}|${row.person_id}|${row.plan_date}|${row.kind}`
    const list = byMessage.get(key)
    if (list) list.push(row)
    else byMessage.set(key, [row])
  }

  let sent = 0
  for (const rows of byMessage.values()) {
    const first = rows[0]
    const response = await fetch(`${url}/functions/v1/send-push`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-push-secret': expected,
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
      body: JSON.stringify({
        messages: rows.map((row) => ({
          token: row.token,
          title: first.title,
          body: first.body,
        })),
      }),
    })
    if (!response.ok) {
      console.error('send-push', response.status)
      continue
    }
    const payload = (await response.json()) as {
      results?: { token: string; status: string }[]
    }
    const results = payload.results ?? []

    // Abgelaufene Registrierungen wegräumen, sonst wächst die Tabelle mit
    // deinstallierten Apps zu — wie im bisherigen Job.
    for (const result of results.filter((r) => r.status === 'unregistered')) {
      await client.from('push_devices').delete().eq('token', result.token)
    }

    // **Nur bei echter Zustellung protokollieren.** Ein optimistischer
    // Eintrag verlöre die Nachricht endgültig: `push_log` gilt danach als
    // „schon raus", und der Digest ändert sich nicht mehr. Dieselbe Klasse
    // Fehler wie ein Knopf, der Erfolg meldet, den er nicht geprüft hat.
    if (!results.some((r) => r.status === 'ok')) continue

    await client.from('push_log').upsert(
      {
        group_id: first.group_id,
        person_id: first.person_id,
        plan_date: first.plan_date,
        kind: first.kind,
        digest: first.digest,
        sent_at: new Date().toISOString(),
      },
      { onConflict: 'group_id,person_id,plan_date,kind' },
    )
    // **Quittiert wird nur, was an `due_at` hing** — also der Abend-Blick
    // und die Änderung (#164).
    //
    // Die beiden Abfahrts-Erinnerungen hängen an der Uhr, nicht an der
    // Fälligkeit der Zeile: Ihr Riegel ist der Eintrag in `push_log` oben.
    // Quittierte man auch für sie, verschluckte eine Erinnerung um 07:15
    // eine Planänderung, die um 07:14 entprellt wurde — die Zeile wäre
    // erledigt, ohne dass die Änderung je rausging, und der Digest ändert
    // sich danach nicht mehr. Dieselbe Klasse Fehler wie ein optimistisch
    // geschriebenes Protokoll.
    if (first.kind === 'evening' || first.kind === 'change') {
      // Der Trigger auf `push_outbox` lässt `due_at` in Ruhe, solange sich
      // der Inhalt nicht ändert — die Zeile bleibt also erledigt, bis
      // wirklich jemand etwas umplant.
      await client
        .from('push_outbox')
        .update({ due_at: null })
        .eq('group_id', first.group_id)
        .eq('person_id', first.person_id)
        .eq('plan_date', first.plan_date)
    }
    sent += 1
  }

  // Nur Zahlen ins Log: Der Text nennt Personennamen, und was hier steht,
  // kann in einem öffentlichen Protokoll landen.
  console.log(`flush-push: ${sent}/${byMessage.size}`)
  return respond(200, { sent })
})
