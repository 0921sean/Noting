// Supabase Edge Function: Anthropic API 프록시
//
// 목적: ANTHROPIC_API_KEY를 "서버 시크릿"으로만 보관해서 클라이언트(APK)에
//       키가 노출되지 않게 한다. 앱은 이 함수를 호출하고, 함수가 키를 붙여
//       Anthropic으로 전달한다.
//
// 배포:  supabase functions deploy classify   (또는 대시보드에서 생성)
// 시크릿: supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//        (SUPABASE_URL / SUPABASE_ANON_KEY 는 런타임이 자동 주입)

import { createClient } from "jsr:@supabase/supabase-js@2";

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // 로그인한 Supabase 사용자만 허용 (남용 방지)
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  try {
    const body = await req.json();
    // 허용 필드만 전달 + max_tokens 상한 (비용 남용 방지)
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

    // Anthropic 응답을 그대로 전달 (앱의 기존 파싱 로직 유지)
    const text = await resp.text();
    return new Response(text, {
      status: resp.status,
      headers: { "content-type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }
});
