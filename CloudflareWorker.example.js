export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const authHeader = request.headers.get("authorization");
    if (authHeader !== `Bearer ${env.APP_SHARED_SECRET}`) {
      return new Response("Unauthorized", { status: 401 });
    }

    let body = {};
    try {
      body = await request.json();
    } catch {
      body = {};
    }

    if (url.pathname === "/realtime/session") {
      const response = await fetch("https://api.openai.com/v1/realtime/client_secrets", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.OPENAI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          session: {
            type: "realtime",
            model: body.model || "gpt-realtime",
            audio: {
              output: {
                voice: body.voice || "marin",
              },
            },
          },
        }),
      });

      const payload = await response.json();
      if (!response.ok) {
        return Response.json(payload, { status: response.status });
      }

      return Response.json({
        ephemeralKey: payload?.value || "",
        expiresAt: payload?.expires_at || 0,
        model: body.model || "gpt-realtime",
        voice: body.voice || "marin",
      });
    }

    if (url.pathname === "/audio/speech") {
      const response = await fetch("https://api.openai.com/v1/audio/speech", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.OPENAI_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: body.model || "gpt-4o-mini-tts",
          voice: body.voice || "cedar",
          input: body.input || "",
          response_format: body.response_format || "wav",
          speed: body.speed || 0.96,
          instructions:
            body.instructions ||
            "Speak in warm, natural, conversational American English like a friendly speaking coach. Sound fluid and human, not like a narrator.",
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        return new Response(errorText, {
          status: response.status,
          headers: { "Content-Type": "application/json" },
        });
      }

      return new Response(response.body, {
        status: 200,
        headers: {
          "Content-Type": response.headers.get("Content-Type") || "audio/mpeg",
          "Cache-Control": "public, max-age=31536000, immutable",
        },
      });
    }

    return new Response("Not found", { status: 404 });
  },
};
