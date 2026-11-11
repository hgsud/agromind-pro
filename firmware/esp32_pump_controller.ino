// ESP32 + حساس رطوبة + DHT22 + ريلاي مضخة. محتاج كهرباء دائمة (من غير deep sleep).
// أمان: الريلاي يبدأ مقفول | حد أقصى للتشغيل | راحة بعد التوقف الإجباري | الوضع التلقائي المحلي شغّال حتى لو النت فصل
// | لو قراءة الحساس غير منطقية المضخة التلقائية تتوقف. ركّب دايمًا قاطع/حماية حمل مناسب للمضخة (لا توصّل مضخة مباشرة على الريلاي الصغير).
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <DHT.h>

const char *WIFI_SSID = "YOUR_WIFI", *WIFI_PASS = "YOUR_PASS";
const char *SUPA_URL = "https://YOUR_PROJECT.supabase.co", *ANON_KEY = "YOUR_ANON_PUBLIC_KEY", *DEVICE_KEY = "YOUR_DEVICE_API_KEY";

const int SOIL_PIN = 34, RELAY_PIN = 26, DHT_PIN = 4;
const bool RELAY_ACTIVE_LOW = true;
const int AIR_VAL = 3200, WET_VAL = 1400;           // عايرهم
const float LOW_PCT = 30, HIGH_PCT = 40;            // حدود الوضع التلقائي المحلي
const bool LOCAL_AUTO = true;
const uint32_t MAX_RUN_MS = 45UL * 60000, COOLDOWN_MS = 30UL * 60000, POST_EVERY_MS = 5UL * 60000, POLL_EVERY_MS = 15000;

DHT dht(DHT_PIN, DHT22);
bool pumpOn = false, manual = false, cooling = false, sensorOk = false;
uint32_t pumpStart = 0, manualUntil = 0, coolStart = 0;
float soilPct = 0;

void relay(bool on) { digitalWrite(RELAY_PIN, (on != RELAY_ACTIVE_LOW) ? HIGH : LOW); }
void startPump() { if (!pumpOn) { pumpOn = true; pumpStart = millis(); relay(true); } }
void stopPump(bool cool = false) { if (pumpOn) { pumpOn = false; relay(false); } if (cool) { cooling = true; coolStart = millis(); } }

void readSoil() {
  long s = 0; for (int i = 0; i < 20; i++) { s += analogRead(SOIL_PIN); delay(5); }
  float raw = s / 20.0;
  sensorOk = raw > WET_VAL - 400 && raw < AIR_VAL + 400;   // خارج المدى = حساس مفصول/تالف
  soilPct = constrain((AIR_VAL - raw) * 100.0 / (AIR_VAL - WET_VAL), 0, 100);
}

String rpc(const char *fn, const String &body) {
  if (WiFi.status() != WL_CONNECTED) return "";
  WiFiClientSecure c; c.setInsecure();                      // للإنتاج: حمّل شهادة CA
  HTTPClient h; h.begin(c, String(SUPA_URL) + "/rest/v1/rpc/" + fn);
  h.addHeader("Content-Type", "application/json"); h.addHeader("apikey", ANON_KEY);
  h.addHeader("Authorization", String("Bearer ") + ANON_KEY);
  int code = h.POST(body); String r = (code >= 200 && code < 300) ? h.getString() : "";
  h.end(); return r;
}

void postReading() {
  if (!sensorOk) return;
  float t = dht.readTemperature(), hm = dht.readHumidity();
  String b = "{\"p_key\":\"" + String(DEVICE_KEY) + "\",\"p_moisture\":" + String(soilPct) +
             ",\"p_temp\":" + (isnan(t) ? String("null") : String(t)) + ",\"p_rh\":" + (isnan(hm) ? String("null") : String(hm)) + "}";
  rpc("ingest_reading", b);
}

void pollCmd() {
  String r = rpc("poll_command", "{\"p_key\":\"" + String(DEVICE_KEY) + "\"}");
  int i = r.indexOf("\"cmd_action\":\""); if (i < 0) return;
  String act = r.substring(i + 14, r.indexOf("\"", i + 14));
  int j = r.indexOf("\"cmd_minutes\":"), k = r.indexOf("\"cmd_id\":");
  int mins = j >= 0 ? r.substring(j + 14).toInt() : 15; long id = k >= 0 ? r.substring(k + 9).toInt() : 0;
  if (act == "on") { manual = true; manualUntil = millis() + (uint32_t)min(mins, 45) * 60000UL; startPump(); }
  else { manual = false; stopPump(); }
  rpc("ack_command", "{\"p_key\":\"" + String(DEVICE_KEY) + "\",\"p_id\":" + String(id) + "}");
}

void setup() {
  pinMode(RELAY_PIN, OUTPUT); relay(false);                 // أول حاجة: مضخة مقفولة
  Serial.begin(115200); dht.begin();
  WiFi.mode(WIFI_STA); WiFi.begin(WIFI_SSID, WIFI_PASS);
}

void loop() {
  static uint32_t lastRead = 0, lastPoll = 0, lastPost = 0, lastWifi = 0; uint32_t now = millis();
  if (WiFi.status() != WL_CONNECTED && now - lastWifi > 30000) { lastWifi = now; WiFi.disconnect(); WiFi.begin(WIFI_SSID, WIFI_PASS); }
  if (lastRead == 0 || now - lastRead > 5000) { lastRead = now; readSoil(); }

  if (pumpOn && now - pumpStart > MAX_RUN_MS) { manual = false; stopPump(true); }          // حد أقصى مطلق
  if (manual) { if ((int32_t)(now - manualUntil) >= 0) { manual = false; stopPump(); } }
  else if (LOCAL_AUTO) {
    if (cooling && now - coolStart >= COOLDOWN_MS) cooling = false;
    if (!sensorOk) stopPump(true);
    else if (pumpOn && soilPct >= HIGH_PCT) stopPump();
    else if (!pumpOn && soilPct < LOW_PCT && !cooling) startPump();
  } else if (pumpOn) stopPump();

  if (now - lastPoll > POLL_EVERY_MS) { lastPoll = now; pollCmd(); }
  if (lastPost == 0 || now - lastPost > POST_EVERY_MS) { lastPost = now; postReading(); }
  Serial.printf("soil=%.1f ok=%d pump=%d manual=%d\n", soilPct, sensorOk, pumpOn, manual);
  delay(200);
}
