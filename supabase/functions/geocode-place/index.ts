// geocode-place – macht aus einem Ortsnamen Koordinaten (Preisarchiv).
//
// Die Umkreissuche von Tankerkönig will lat/lng; die Gruppe soll aber einen
// Ort eintippen können. Dafür Nominatim (OpenStreetMap): kostenlos, ohne
// Schlüssel, ohne Registrierung.
//
// **Warum serverseitig und nicht im Client:** Die Nutzungsregeln von
// Nominatim verlangen eine aussagekräftige Kennung des aufrufenden Programms
// im User-Agent. Ein Browser lässt den Header nicht setzen — aus der
// Web-App käme ein anonymer Aufruf, und die Instanz sperrt so etwas. Hier
// steht die Kennung fest und gilt für alle Plattformen gleich.
//
// `verify_jwt = true`: Anders als `flush-push` hat dieser Weg keinen
// Aufrufer aus der Datenbank. Nur angemeldete Gruppen dürfen ihn benutzen —
// er ist der einzige Punkt, an dem die App einen Fremddienst befragt.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function respond(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

const USER_AGENT = 'MitFahrBar (https://github.com/MacBuchi/MitFahrBar)'

interface Hit {
  lat: string
  lon: string
  display_name: string
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }
  if (req.method !== 'POST') return respond(405, { error: 'method not allowed' })

  let payload: { query?: string }
  try {
    payload = await req.json()
  } catch {
    return respond(400, { error: 'invalid json' })
  }

  const query = (payload.query ?? '').trim()
  if (query.length < 2) return respond(400, { error: 'query too short' })

  const url =
    'https://nominatim.openstreetmap.org/search' +
    `?q=${encodeURIComponent(query)}&format=jsonv2&limit=10&addressdetails=0`

  let hits: Hit[]
  try {
    const response = await fetch(url, {
      headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'de' },
    })
    if (!response.ok) throw new Error(`http ${response.status}`)
    hits = (await response.json()) as Hit[]
  } catch (error) {
    console.error('geocode', (error as Error).message)
    return respond(502, { error: 'geocoder unavailable' })
  }

  // Entdoppeln nach gerundeter Koordinate: Nominatim liefert denselben Ort
  // mehrfach, wenn mehrere OSM-Objekte darauf zeigen (bei „Bad Rappenau"
  // zweimal dieselbe Stelle). Ungefiltert stünden in der Auswahlliste zwei
  // identische Einträge, zwischen denen niemand wählen kann.
  const seen = new Set<string>()
  const places: { label: string; lat: number; lng: number }[] = []
  for (const hit of hits) {
    const lat = Number(hit.lat)
    const lng = Number(hit.lon)
    if (!Number.isFinite(lat) || !Number.isFinite(lng)) continue
    const key = `${lat.toFixed(2)},${lng.toFixed(2)}`
    if (seen.has(key)) continue
    seen.add(key)
    places.push({ label: hit.display_name, lat, lng })
    if (places.length === 5) break
  }

  return respond(200, { places })
})
