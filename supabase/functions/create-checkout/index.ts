// ينشئ طلب دفع في Paymob ويرجّع رابط iframe. التدفق: auth/tokens -> ecommerce/orders -> acceptance/payment_keys
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const PRICES: Record<string, number> = { pro: 300, business: 1500 }; // جنيه/شهر: غيّرها (وغيّرها في app.html كمان)
const env = (k: string) => Deno.env.get(k)!;
const SB = env("SUPABASE_URL"), SK = env("SUPABASE_SERVICE_ROLE_KEY"), ANON = env("SUPABASE_ANON_KEY");
const json = (o: unknown, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const P = "https://accept.paymob.com/api";
const post = async (path: string, body: unknown) => {
  const r = await fetch(P + path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`paymob ${path} ${r.status} ${await r.text()}`);
  return r.json();
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const jwt = (req.headers.get("authorization") || "").replace("Bearer ", "");
    const u = await (await fetch(`${SB}/auth/v1/user`, { headers: { apikey: ANON, Authorization: `Bearer ${jwt}` } })).json();
    if (!u.id) return json({ error: "غير مصرح" }, 401);
    const { plan } = await req.json(), price = PRICES[plan];
    if (!price) return json({ error: "خطة غير صحيحة" }, 400);
    const o = await (await fetch(`${SB}/rest/v1/orders`, { method: "POST",
      headers: { apikey: SK, Authorization: `Bearer ${SK}`, "Content-Type": "application/json", Prefer: "return=representation" },
      body: JSON.stringify({ user_id: u.id, plan, amount_egp: price }) })).json();
    const cents = price * 100;
    const auth = await post("/auth/tokens", { api_key: env("PAYMOB_API_KEY") });
    const ord = await post("/ecommerce/orders", { auth_token: auth.token, delivery_needed: false, amount_cents: cents, currency: "EGP", merchant_order_id: o[0].id, items: [] });
    const na = "NA", key = await post("/acceptance/payment_keys", {
      auth_token: auth.token, amount_cents: cents, expiration: 3600, order_id: ord.id, currency: "EGP",
      integration_id: Number(env("PAYMOB_INTEGRATION_ID")),
      billing_data: { apartment: na, email: u.email, floor: na, first_name: "عميل", last_name: "أجرو-مايند", street: na, building: na,
        phone_number: "+201000000000", shipping_method: na, postal_code: na, city: "Cairo", country: "EG", state: na } });
    return json({ iframe_url: `https://accept.paymob.com/api/acceptance/iframes/${env("PAYMOB_IFRAME_ID")}?payment_token=${key.token}` });
  } catch (e) { return json({ error: String((e as Error).message || e) }, 500); }
});
