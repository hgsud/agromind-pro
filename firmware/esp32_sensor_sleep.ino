// ESP32 + حساس رطوبة تربة سعوي (Capacitive v1.2) + DHT22 → Supabase
// المكتبات: DHT sensor library (Adafruit) + Adafruit Unified Sensor
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <DHT.h>

const char* WIFI_SSID = "YOUR_WIFI";
const char* WIFI_PASS = "YOUR_PASS";
const char* SUPA_URL  = "https://YOUR_PROJECT.supabase.co";   // Project URL
const char* ANON_KEY  = "YOUR_ANON_PUBLIC_KEY";               // anon public key
const char* DEVICE_KEY= "YOUR_DEVICE_API_KEY";                // من التطبيق بعد إضافة الجهاز

const int SOIL_PIN = 34;      // ADC1 فقط (ADC2 بيتعطل مع WiFi)
const int AIR_VAL  = 3200;    // قراءة الحساس في الهواء (عايره بنفسك)
const int WET_VAL  = 1400;    // قراءة الحساس في ماء/تربة مشبعة
const uint64_t SLEEP_MIN = 10;

DHT dht(4, DHT22);

float readSoilPct() {
  long s = 0;
  for (int i = 0; i < 20; i++) { s += analogRead(SOIL_PIN); delay(10); }
  float raw = s / 20.0;
  float pct = (AIR_VAL - raw) * 100.0 / (AIR_VAL - WET_VAL);
  return constrain(pct, 0, 100);
}

void setup() {
  Serial.begin(115200);
  dht.begin();
  WiFi.begin(WIFI_SSID, WIFI_PASS);
  for (int i = 0; i < 40 && WiFi.status() != WL_CONNECTED; i++) delay(500);
  if (WiFi.status() == WL_CONNECTED) {
    float m = readSoilPct(), t = dht.readTemperature(), h = dht.readHumidity();
    WiFiClientSecure c; c.setInsecure();   // للتجربة؛ للإنتاج حمّل شهادة الـCA
    HTTPClient http;
    http.begin(c, String(SUPA_URL) + "/rest/v1/rpc/ingest_reading");
    http.addHeader("Content-Type", "application/json");
    http.addHeader("apikey", ANON_KEY);
    http.addHeader("Authorization", String("Bearer ") + ANON_KEY);
    String body = "{\"p_key\":\"" + String(DEVICE_KEY) + "\",\"p_moisture\":" + m +
                  ",\"p_temp\":" + (isnan(t) ? String("null") : String(t)) + ",\"p_rh\":" + (isnan(h) ? String("null") : String(h)) + "}";
    int code = http.POST(body);
    Serial.printf("moisture=%.1f temp=%.1f rh=%.1f -> HTTP %d\n", m, t, h, code);
    http.end();
  }
  esp_sleep_enable_timer_wakeup(SLEEP_MIN * 60ULL * 1000000ULL);
  esp_deep_sleep_start();
}
void loop() {}
