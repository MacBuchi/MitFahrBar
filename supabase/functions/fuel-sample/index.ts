// fuel-sample – tastet die Spritpreise im Umkreis ab (Preisarchiv, Schritt 1).
//
// Zwei Aufrufer, zwei Ausweise — dasselbe Muster wie `send-push`:
//
//   1. pg_cron → pg_net schickt den Header `x-fuel-secret` und tastet ALLE
//      hinterlegten Regionen ab.
//   2. Die App („Jetzt aktualisieren") hat das Geheimnis nicht und weist sich
//      mit dem JWT der Nutzerin aus; abgetastet wird dann nur die Region der
//      eigenen Gruppe. Das ist zugleich der Weg, den die Tankerkönig-
//      Nutzungsbedingungen ausdrücklich vorsehen: auf Nutzeraktion.
//
// `verify_jwt` steht in config.toml auf false, weil der Aufruf aus der
// Datenbank kein JWT hat. Die Prüfung passiert deshalb hier im Rumpf.
//
// **Der API-Key verlässt den Server nie.** Er liegt in TANKERKOENIG_API_KEY
// (`supabase secrets set`). Im Client wäre er in `main.dart.js` nachlesbar,
// verstieße gegen die Nutzungsbedingungen (die GitHub ausdrücklich nennen)
// und stürbe am Minutenlimit, sobald mehr als ein Gerät fragt — das Limit
// hängt am Schlüssel, nicht am Gerät.

import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-fuel-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function respond(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

// Tankerkönig deckelt die Umkreissuche bei 25 km; darüber antwortet die API
// mit einem Fehler statt mit weniger Ergebnissen.
const MAX_RADIUS_KM = 25

// Die Nutzungsbedingungen nennen eine Abfrage je Minute. Mehrere Regionen
// werden deshalb NACHEINANDER mit Abstand abgefragt, nicht parallel — und
// nur so viele, wie in einen Lauf passen. Was übrig bleibt, steht im Log:
// eine stille Kürzung sähe aus wie „alles abgetastet".
const REGION_GAP_MS = 61_000
const MAX_REGIONS_PER_RUN = 5

interface Region {
  region_key: string
  lat: number
  lng: number
  radius_km: number
}

interface Station {
  id: string
  isOpen: boolean
  e5: number | null
  e10: number | null
  diesel: number | null
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms))

// Preise kommen als Zahl, fehlende Sorten als `false` oder `null`. Beides
// muss zu NULL werden: Eine 0 zöge das Wochenperzentil gegen den Boden.
function price(value: unknown): number | null {
  return typeof value === 'number' && value > 0 ? value : null
}

async function fetchStations(region: Region, apiKey: string) {
  const radius = Math.min(region.radius_km, MAX_RADIUS_KM)
  const url =
    'https://creativecommons.tankerkoenig.de/json/list.php' +
    `?lat=${region.lat}&lng=${region.lng}&rad=${radius}` +
    `&sort=dist&type=all&apikey=${apiKey}`

  const response = await fetch(url)
  if (!response.ok) throw new Error(`http ${response.status}`)

  const body = await response.json()
  if (!body?.ok) throw new Error(String(body?.message ?? 'api not ok'))

  return (body.stations ?? []) as Station[]
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') return respond(405, { error: 'method not allowed' })

  const apiKey = Deno.env.get('TANKERKOENIG_API_KEY')
  if (!apiKey) {
    // Ohne Schlüssel tut der Job nichts, statt zu scheitern: So bleibt der
    // lokale Teststack lauffähig, ohne dass jemand Geheimnisse anlegt.
    console.error('fuel-sample: TANKERKOENIG_API_KEY fehlt')
    return respond(200, { results: [], skipped: 'no api key' })
  }

  const expected = Deno.env.get('FUEL_JOB_SECRET')
  const isJob = !!expected && req.headers.get('x-fuel-secret') === expected

  const serviceClient = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  // Welche Regionen — und wer darf sie sehen? Beim Job alle, sonst
  // entscheidet die RLS mit dem JWT der Nutzerin. Eine eigene Prüfung wäre
  // eine zweite Wahrheit über die Mandantentrennung.
  let regions: Region[]
  if (isJob) {
    const { data, error } = await serviceClient
      .from('price_area')
      .select('region_key, lat, lng, radius_km')
    if (error) {
      console.error('fuel-sample: regions', error.message)
      return respond(500, { error: 'regions unavailable' })
    }
    // Zwei Gruppen in derselben Gegend teilen sich eine Abfrage.
    const seen = new Map<string, Region>()
    for (const row of (data ?? []) as Region[]) seen.set(row.region_key, row)
    regions = [...seen.values()]
  } else {
    const authorization = req.headers.get('Authorization')
    if (!authorization) return respond(401, { error: 'unauthorized' })
    const userClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authorization } } },
    )
    const { data } = await userClient
      .from('price_area')
      .select('region_key, lat, lng, radius_km')
      .maybeSingle()
    if (!data) return respond(403, { error: 'no area' })
    regions = [data as Region]
  }

  if (regions.length > MAX_REGIONS_PER_RUN) {
    console.error(
      `fuel-sample: ${regions.length} Regionen, ${MAX_REGIONS_PER_RUN} in ` +
        'diesem Lauf — der Rest wartet auf den nächsten Takt',
    )
    regions = regions.slice(0, MAX_REGIONS_PER_RUN)
  }

  // EIN Zeitstempel für den ganzen Lauf, auf die Minute gerundet: Die
  // Stichprobe ist ein Schnappschuss der Region. Ein Zeitstempel je Station
  // machte aus einer Momentaufnahme 93 verschiedene und wäre aus dem
  // Preiswechsel-Archiv später nicht mehr nachzustellen.
  const capturedAt = new Date()
  capturedAt.setSeconds(0, 0)

  const results: Record<string, unknown>[] = []
  for (const [index, region] of regions.entries()) {
    if (index > 0) await sleep(REGION_GAP_MS)

    try {
      const stations = await fetchStations(region, apiKey)
      const rows = stations
        // Geschlossene fliegen raus: Sie melden den zuletzt bekannten Preis,
        // den man dort gerade nicht bezahlen kann. Ein Perzentil über
        // „Preise, die man bekommen könnte" darf sie nicht mitzählen.
        .filter((station) => station.isOpen)
        .map((station) => ({
          region_key: region.region_key,
          captured_at: capturedAt.toISOString(),
          station_id: station.id,
          e5: price(station.e5),
          e10: price(station.e10),
          diesel: price(station.diesel),
        }))
        .filter((row) => row.e5 !== null || row.e10 !== null || row.diesel !== null)

      if (rows.length > 0) {
        const { error } = await serviceClient
          .from('price_sample')
          .upsert(rows, { onConflict: 'region_key,captured_at,station_id' })
        if (error) throw new Error(error.message)
      }

      results.push({
        region: region.region_key,
        found: stations.length,
        stored: rows.length,
      })
    } catch (error) {
      console.error('fuel-sample', region.region_key, (error as Error).message)
      results.push({ region: region.region_key, error: 'sample failed' })
    }
  }

  // Der Ausgang je Region steht im Rumpf, damit der Knopf in der App keinen
  // Erfolg meldet, den er nicht geprüft hat.
  return respond(200, { captured_at: capturedAt.toISOString(), results })
})
