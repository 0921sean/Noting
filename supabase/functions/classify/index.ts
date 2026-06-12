// Supabase Edge Function: Anthropic API 프록시
//
// 목적: ANTHROPIC_API_KEY를 "서버 시크릿"으로만 보관해서 클라이언트(APK)에
//       키가 노출되지 않게 한다. 앱은 이 함수를 호출하고, 함수가 키를 붙여
//       Anthropic으로 전달한다.
//
// 보호장치:
//   - 로그인 사용자만 통과 (Supabase JWT 검증)
//   - 사용자별 rate limit (시간당 5회 / 일 20회)
//   - max_tokens 상한 4096
//
// 배포:  supabase functions deploy classify   (또는 대시보드에서 생성)
// 시크릿: ANTHROPIC_API_KEY 만 설정. SUPABASE_URL / SUPABASE_ANON_KEY /
//         SUPABASE_SERVICE_ROLE_KEY 는 런타임이 자동 주입.

import { createClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const RATE_PER_HOUR = 5;
const RATE_PER_DAY = 20;

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // 사용자 JWT 검증용 클라이언트 (anon key + 사용자 토큰)
  const authHeader = req.headers.get("Authorization") ?? "";
  const userClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) {
    return jsonError(401, "Unauthorized");
  }

  // RLS 무시하고 호출 로그를 쓰는 관리자 클라이언트
  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ── Rate limit 체크 ────────────────────────────────────────────────────────
  const now = Date.now();
  const hourAgo = new Date(now - 3_600_000).toISOString();
  const dayAgo = new Date(now - 86_400_000).toISOString();

  const { count: hourCount } = await admin
    .from("noting_ai_calls")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", hourAgo);

  if ((hourCount ?? 0) >= RATE_PER_HOUR) {
    return jsonError(
      429,
      `시간당 ${RATE_PER_HOUR}회 한도 초과 — 잠시 후 다시 시도해주세요.`,
    );
  }

  const { count: dayCount } = await admin
    .from("noting_ai_calls")
    .select("*", { count: "exact", head: true })
    .eq("user_id", user.id)
    .gte("created_at", dayAgo);

  if ((dayCount ?? 0) >= RATE_PER_DAY) {
    return jsonError(
      429,
      `일 ${RATE_PER_DAY}회 한도 초과 — 내일 다시 시도해주세요.`,
    );
  }

  // ── Anthropic 호출 ────────────────────────────────────────────────────────
  try {
    const body = await req.json();
    const payload = {
      model: typeof body.model === "string"
        ? body.model
        : "claude-haiku-4-5-20251001",
      max_tokens: Math.min(Number(body.max_tokens) || 1024, 4096),
      messages: body.messages,
    };

    const resp = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "x-api-key": Deno.env.get("ANTHROPIC_API_KEY")!,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    // 성공/실패와 무관하게 호출 자체는 비용/한도에 카운트 (Anthropic 콜이 실제로 나갔으니)
    await admin.from("noting_ai_calls").insert({ user_id: user.id });

    const text = await resp.text();
    return new Response(text, {
      status: resp.status,
      headers: { "content-type": "application/json" },
    });
  } catch (e) {
    return jsonError(400, String(e));
  }
});

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "content-type": "application/json" },
  });
}
