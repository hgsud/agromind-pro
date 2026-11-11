// تنبيهات تيليجرام: رطوبة منخفضة + جهاز مفصول. بيتنادى كل 10 دقايق من pg_cron.
const URL_ = Deno.env.get("SUPABASE_URL")!, KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, TG = Deno.env.get("TELEGRAM_BOT_TOKEN")!;
const H = { apikey: KEY, Authorization: `Bearer ${KEY}`, "Content-Type": "application/json" };
const hrs = (t: string | null) => t ? (Date.now() - Date.parse(t)) / 36e5 : Infinity;
const tg = (chat: string, text: string) =>
  fetch(`https://api.telegram.org/bot${TG}/sendMessage`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ chat_id: chat, text }) });
const mark = (id: string, patch: object) =>
  fetch(`${URL_}/rest/v1/devices?id=eq.${id}`, { method: "PATCH", headers: H, body: JSON.stringify(patch) });

Deno.serve(async (req) => {
  if (req.headers.get("authorization") !== `Bearer ${KEY}`) return new Response("forbidden", { status: 403 });
  const rows = await (await fetch(`${URL_}/rest/v1/rpc/devices_status`, { method: "POST", headers: H, body: "{}" })).json();
  let sent = 0;
  for (const d of rows) {
    const label = `${d.farm_name} / ${d.device_name}`, now = new Date().toISOString();
    if (hrs(d.last_ts) > 1.5) {
      if (hrs(d.offline_alert_at) > 12) { await tg(d.chat, `⚠️ الجهاز ${label} مفصول من أكتر من ساعة ونص. افحص الكهرباء/الواي فاي.`); await mark(d.device_id, { offline_alert_at: now }); sent++; }
    } else if (d.last_moisture < d.low_threshold && hrs(d.last_alert_at) > 6) {
      await tg(d.chat, `💧 ${label}: الرطوبة ${d.last_moisture.toFixed(1)}% تحت حد الري (${d.low_threshold}%). حان وقت الري.`);
      await mark(d.device_id, { last_alert_at: now }); sent++;
    }
  }
  return new Response(JSON.stringify({ checked: rows.length, sent }));
});
