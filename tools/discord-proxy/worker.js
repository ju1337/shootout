// Cloudflare Worker: leitet Logs vom Roblox-Server an den Discord-Webhook weiter (nur nötig, falls Discord
// Anfragen direkt von Roblox ablehnt, z.B. HTTP 403). Einstellungen im Worker (Settings › Variables, als Secret):
//   WEBHOOK = https://discord.com/api/webhooks/...   (die echte Webhook-Adresse)
//   KEY     = beliebiges langes Passwort
// In Roblox ist das Secret "DiscordLog" dann: https://<dein-worker>.workers.dev/<KEY>
export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method !== "POST" || url.pathname !== "/" + env.KEY) {
      return new Response("nein", { status: 403 });
    }
    const body = await request.text();
    if (body.length > 20000) {
      return new Response("zu groß", { status: 413 });
    }
    const reply = await fetch(env.WEBHOOK, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
    return new Response(await reply.text(), { status: reply.status });
  },
};
