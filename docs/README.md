# أجرو-مايند: دليل التشغيل الكامل

## محتويات الحزمة
- `site/`: الموقع (index.html صفحة هبوط، app.html التطبيق، PWA: manifest + sw.js + أيقونات).
- `supabase/`: `1_schema.sql` ثم `2_schema_saas.sql` ثم `3_schema_v3.sql` (بالترتيب)، و`functions/` (تنبيهات، إنشاء دفع، استقبال إشعار الدفع).
- `firmware/`: `esp32_sensor_sleep.ino` (حساس بطارية/نوم)، `esp32_pump_controller.ino` (حساس + مضخة، كهرباء دائمة).
- `ml/train_model.py`: تدريب نموذج تنبؤ الرطوبة بعد توفر بيانات.
- `docs/legal_templates_ar.md`: قوالب شروط وخصوصية (تحتاج محامي).

## الحالة بصراحة
| اتفحص هنا | لم يُجرَّب (لازم تجربه أنت) |
|---|---|
| صياغة JavaScript وTypeScript وPython، وكل أزرار الواجهة لها دوال، والحاسبات التسعة بأرقام منطقية، ومنطق تحليل القراءات | تشغيل ملفات SQL على Supabase، التسجيل والدخول، ESP32 والحساسات والمضخة فعليًا، Telegram، Paymob (حتى في وضع الاختبار) |

أي خطأ هيظهر في الخطوات دي ابعتهولي بالنص وهصلحه.

## الخطوات
1. **Supabase:** أنشئ مشروع ← SQL Editor ← شغّل الملفات 1 ثم 2 ثم 3.
2. **المفاتيح في التطبيق:** افتح `site/app.html` وحط Project URL والمفتاح `anon` في `const CFG`. (ممنوع تحط `service_role`).
3. **النشر:** ارفع مجلد `site/` على Netlify أو Cloudflare Pages. اربط دومينك.
4. **تيليجرام:** من @BotFather اعمل بوت وخد التوكن. غيّر نص "بوت المنصة" في شاشة التنبيهات لاسم البوت.
5. **الدوال:**
```
supabase login
supabase link --project-ref PROJECT_REF
supabase secrets set TELEGRAM_BOT_TOKEN=... PAYMOB_API_KEY=... PAYMOB_INTEGRATION_ID=... PAYMOB_IFRAME_ID=... PAYMOB_HMAC=...
supabase functions deploy check-alerts
supabase functions deploy create-checkout
supabase functions deploy paymob-webhook --no-verify-jwt
```
6. **الجدولة:** فعّل `pg_cron` و`pg_net` من Database ← Extensions، وشغّل أسطر التعليق في آخر `3_schema_v3.sql` (بدّل PROJECT_REF وSERVICE_ROLE_KEY).
7. **Paymob:** افتح حساب تاجر، أنشئ Integration وIframe، وحط رابط `https://PROJECT_REF.supabase.co/functions/v1/paymob-webhook` كـ Transaction processed callback. جرّب في وضع الاختبار قبل الدفع الحقيقي، وراجع وثائقهم الحالية لأن التفاصيل بتتغير.
8. **أول أدمن:** سجّل حسابك في التطبيق ثم شغّل `insert into admins select id from auth.users where email='إيميلك';` (سطر في آخر 3_schema_v3).
9. **الأسعار:** غيّرها في مكانين: `PRICES` في `app.html` و`create-checkout/index.ts`.
10. **الأجهزة:** من التطبيق أضف مزرعة ثم جهاز وخد مفتاحه، وحطه في الـ firmware مع بيانات WiFi وSupabase.

## ترتيب الاختبار المقترح (قبل أي عميل)
SQL ← تسجيل حساب ← إضافة جهاز ← ESP32 يبعت قراءة ← تنبيه تيليجرام (اخفض الحد مؤقتًا) ← المضخة بلمبة بدل المضخة ← Paymob وضع اختبار ← مزرعة فعلية أسبوعين.

## تنبيهات مهمة قبل البيع
- **الطقس (Open-Meteo):** الاستخدام المجاني لغير التجاري فقط. لو هتبيع، لازم اشتراك تجاري منهم أو بديل.
- **المضخة:** ركّب قاطع وحماية حمل مناسبة، ولا توصّل مضخة مباشرة على ريلاي صغير. الجهاز فيه حدود أمان (حد أقصى 45 دقيقة، راحة 30 دقيقة، إيقاف لو الحساس معطل) لكنها لا تغني عن الحماية الكهربائية.
- **WhatsApp:** استبدلته بتيليجرام لأن واجهة واتساب للأعمال تحتاج موافقة Meta. ممكن نضيفها بعدين.
- **أمان:** فعّل تأكيد الإيميل، وبدّل `setInsecure()` في الـ firmware بشهادة CA، وخد نسخ احتياطية من قاعدة البيانات.
- **قانونيًا:** راجع القوالب مع محامي، وشوف التسجيل الضريبي والتجاري للنشاط.
- **الذكاء الاصطناعي:** اللي شغّال قواعد وإحصاء. النموذج التنبؤي (`ml/`) يحتاج أسبوعين لشهر من بيانات فعلية.
