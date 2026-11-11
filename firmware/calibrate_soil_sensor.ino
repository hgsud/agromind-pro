// معايرة حساس الرطوبة: ارفعه، افتح Serial Monitor (115200)، وسجّل القيمتين:
// AIR_VAL = القراءة والحساس معلّق في الهواء | WET_VAL = القراءة والحساس مغمور في كوب ماء حتى خط الحد الأقصى
const int SOIL_PIN = 34;
void setup() { Serial.begin(115200); }
void loop() {
  long s = 0; for (int i = 0; i < 50; i++) { s += analogRead(SOIL_PIN); delay(10); }
  Serial.printf("raw = %ld\n", s / 50);
  delay(1000);
}
