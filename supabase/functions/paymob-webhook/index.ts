// Transaction processed callback من Paymob. انشره بـ --no-verify-jwt. التحقق بالـHMAC (SHA-512).
const env = (k: string) => Deno.env.get(k)!;
const SB = env("SUPABASE_URL"), SK = env("SUPABASE_SERVICE_ROLE_KEY");
const H = { apikey: SK, Authorization: `Bearer ${SK}`, "Content-Type": "application/json", Prefer: "return=representation" };
// ترتيب الحقول حسب وثائق Paymob لـ Transaction Processed (المسارات نسبةً لـ obj)
const FIELDS = ["amount_cents", "created_at", "currency", "error_occured", "has_parent_transaction", "id", "integration_id", "is_3d_secure",
  "is_auth", "is_capture", "is_refunded", "is_standalone_payment", "is_voided", "order.id", "owner", "pending",
  "source_data.pan", "source_data.sub_type", "source_data.type", "success"];
const get = (o: any, p: string) => p.split(".").reduce((a, k) => a?.[k], o);
async function hmac(s: string, k: string) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(k), { name: "HMAC", hash: "SHA-512" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(s));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
Deno.serve(async (req) => {
  const given = new URL(req.url).searchParams.get("hmac");
  const body = await req.json().catch(() => null), o = body?.obj;
  if (!o || !given) return new Response("bad request", { status: 400 });
  const calc = await hmac(FIELDS.map((f) => String(get(o, f) ?? "")).join(""), env("PAYMOB_HMAC"));
  if (calc !== given.toLowerCase()) return new Response("bad hmac", { status: 401 });
  const rows = await (await fetch(`${SB}/rest/v1/orders?id=eq.${o.order?.merchant_order_id}&select=*`, { headers: H })).json();
  const ord = rows[0];
  if (!ord) return new Response("unknown order");
  const paid = o.success === true && o.pending === false && !o.is_voided && !o.is_refunded && o.currency === "EGP" && o.amount_cents === ord.amount_egp * 100;
  if (paid) {
    // تحديث مشروط بالحالة pending علشان لو الإشعار اتكرر ما يتفعلش مرتين
    const upd = await (await fetch(`${SB}/rest/v1/orders?id=eq.${ord.id}&status=eq.pending`, { method: "PATCH", headers: H, body: JSON.stringify({ status: "paid", provider_ref: String(o.id) }) })).json();
    if (upd.length === 1)
      await fetch(`${SB}/rest/v1/rpc/activate_plan`, { method: "POST", headers: H, body: JSON.stringify({ p_user: ord.user_id, p_plan: ord.plan, p_days: 30 }) });
  } else if (o.success === false && o.pending === false) {
    await fetch(`${SB}/rest/v1/orders?id=eq.${ord.id}&status=eq.pending`, { method: "PATCH", headers: H, body: JSON.stringify({ status: "failed" }) });
  }
  return new Response("ok");
});
