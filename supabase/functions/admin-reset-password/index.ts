import { createClient, type User } from "https://esm.sh/@supabase/supabase-js@2";

const encoder = new TextEncoder();

async function digest(value: string): Promise<Uint8Array> {
  return new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(value)));
}

async function sameSecret(candidate: string, expected: string): Promise<boolean> {
  const [left, right] = await Promise.all([digest(candidate), digest(expected)]);
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left[index] ^ right[index];
  }
  return difference === 0;
}

Deno.serve(async (request: Request) => {
  const origin = request.headers.get("origin") ?? "";
  const allowedOrigin = Deno.env.get("ACADEMY_APP_ORIGIN") ?? "";
  if (!allowedOrigin || origin !== allowedOrigin) {
    return new Response("Forbidden", { status: 403 });
  }

  const corsHeaders = {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405, headers: corsHeaders });
  }
  try {
    const requestBody = await request.text();
    if (encoder.encode(requestBody).length > 4096) {
      return Response.json({ error: "Request too large" }, { status: 413, headers: corsHeaders });
    }
    const body = JSON.parse(requestBody);
    const username = typeof body.username === "string" ? body.username.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";
    const adminKey = typeof body.adminKey === "string" ? body.adminKey : "";
    const expectedKey = Deno.env.get("ACADEMY_RECOVERY_KEY") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";

    if (!expectedKey || expectedKey.length < 32 || !serviceRoleKey || !supabaseUrl) {
      return Response.json({ error: "Recovery service is not configured" }, { status: 503, headers: corsHeaders });
    }
    if (
      !/^[a-z0-9][a-z0-9._-]{2,29}$/i.test(username) ||
      password.length < 8 ||
      encoder.encode(password).length > 72 ||
      adminKey.length < 32 ||
      !await sameSecret(adminKey, expectedKey)
    ) {
      return Response.json({ error: "Invalid recovery details" }, { status: 400, headers: corsHeaders });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const email = `${username}@academy-manager.invalid`;
    let targetUser: User | null = null;
    for (let page = 1; page <= 100; page += 1) {
      const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
      if (error) throw error;
      targetUser = data.users.find((user) => user.email?.toLowerCase() === email) ?? null;
      if (targetUser || data.users.length < 1000) break;
    }
    if (!targetUser) {
      return Response.json({ error: "Invalid recovery details" }, { status: 400, headers: corsHeaders });
    }

    const { error } = await admin.auth.admin.updateUserById(targetUser.id, { password });
    if (error) throw error;
    return Response.json({ ok: true }, { headers: corsHeaders });
  } catch (error) {
    console.error("Password recovery failed", error);
    return Response.json({ error: "Password recovery failed" }, { status: 500, headers: corsHeaders });
  }
});
