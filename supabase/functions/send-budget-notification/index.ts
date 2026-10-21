// supabase/functions/send-budget-notification/index.ts
//
// Sends an FCM push notification using the v1 HTTP API (service account auth).
//
// Deploy:   supabase functions deploy send-budget-notification
// Secret:   supabase secrets set --env-file secrets.env
//           (secrets.env contains FCM_SERVICE_ACCOUNT=<json contents>)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { create, getNumericDate } from 'https://deno.land/x/djwt@v2.8/mod.ts'

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging'

// ── Get OAuth2 access token from service account JSON ─────────────────────────
async function getAccessToken(serviceAccountJson: string): Promise<string> {
  const sa = JSON.parse(serviceAccountJson)

  const now = getNumericDate(0)
  const exp = getNumericDate(60 * 60) // 1 hour

  const payload = {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: exp,
    scope: FCM_SCOPE,
  }

  // Import the private key
  const pemContents = sa.private_key
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s/g, '')

  const binaryDer = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )

  const jwt = await create({ alg: 'RS256', typ: 'JWT' }, payload, cryptoKey)

  // Exchange JWT for access token
  const tokenRes = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  })

  const tokenJson = await tokenRes.json()
  if (!tokenJson.access_token) {
    throw new Error(`Failed to get access token: ${JSON.stringify(tokenJson)}`)
  }
  return tokenJson.access_token
}

// ── Main handler ───────────────────────────────────────────────────────────────
serve(async (req) => {
  try {
    // Auth check
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const { userId, title, body } = await req.json()
    if (!userId || !title || !body) {
      return new Response(JSON.stringify({ error: 'Missing userId, title or body' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Look up FCM token from profiles
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const { data: profile, error } = await supabase
      .from('profiles')
      .select('fcm_token')
      .eq('id', userId)
      .single()

    if (error || !profile?.fcm_token) {
      return new Response(JSON.stringify({ sent: false, reason: 'no_token' }), {
        status: 200,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Get OAuth2 access token
    const serviceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT')!
    const sa = JSON.parse(serviceAccountJson)
    const projectId = sa.project_id

    const accessToken = await getAccessToken(serviceAccountJson)

    // Send via FCM v1 API
    const fcmRes = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${accessToken}`,
        },
        body: JSON.stringify({
          message: {
            token: profile.fcm_token,
            notification: { title, body },
            android: {
              priority: 'high',
              notification: {
                channel_id: 'budget_alerts',
                sound: 'default',
              },
            },
            data: { type: 'budget_alert' },
          },
        }),
      },
    )

    const fcmJson = await fcmRes.json()

    return new Response(JSON.stringify({ sent: true, fcm: fcmJson }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})