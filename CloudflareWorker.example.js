export default {
  async fetch(request, env) {
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
      ephemeralKey: payload?.client_secret?.value || "",
      expiresAt: payload?.client_secret?.expires_at || 0,
      model: body.model || "gpt-realtime",
      voice: body.voice || "marin",
    });
  },
};
