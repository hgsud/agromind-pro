"""تدريب نموذج يتنبأ برطوبة التربة بعد 6 ساعات من بيانات Supabase (أو CSV).
pip install pandas scikit-learn requests joblib"""
import sys, requests, pandas as pd, numpy as np, joblib
from sklearn.ensemble import GradientBoostingRegressor
from sklearn.metrics import mean_absolute_error

URL, ANON, JWT, DEVICE = "https://YOUR_PROJECT.supabase.co", "ANON_KEY", "USER_ACCESS_TOKEN", "DEVICE_UUID"
HORIZON_H = 6

def load():
    if len(sys.argv) > 1:                       # python train_model.py data.csv
        return pd.read_csv(sys.argv[1], parse_dates=["time"]).rename(columns={"time": "ts"})
    r = requests.get(f"{URL}/rest/v1/readings", params={"device_id": f"eq.{DEVICE}", "order": "ts.asc", "limit": 50000},
                     headers={"apikey": ANON, "Authorization": f"Bearer {JWT}"})
    r.raise_for_status()
    return pd.DataFrame(r.json())

df = load()
df["ts"] = pd.to_datetime(df["ts"], utc=True)
df = df.set_index("ts").sort_index()[["moisture", "temp", "rh"]].resample("1h").mean().interpolate(limit=3).dropna()
df["hour"] = df.index.hour
for k in (1, 3, 6, 12):
    df[f"m_lag{k}"] = df["moisture"].shift(k)
df["d1"] = df["moisture"].diff()
df["target"] = df["moisture"].shift(-HORIZON_H)
df = df.dropna()
if len(df) < 200:
    sys.exit(f"البيانات قليلة ({len(df)} ساعة). اجمع أسبوعين على الأقل قبل التدريب.")

X, y = df.drop(columns="target"), df["target"]
cut = int(len(df) * 0.8)                       # تقسيم زمني (مش عشوائي) علشان نتجنب التسريب
model = GradientBoostingRegressor(n_estimators=300, max_depth=3, learning_rate=0.05).fit(X[:cut], y[:cut])
mae = mean_absolute_error(y[cut:], model.predict(X[cut:]))
base = mean_absolute_error(y[cut:], X["moisture"][cut:])   # خط الأساس: "هتفضل زي ما هي"
print(f"MAE النموذج = {mae:.2f}% | MAE خط الأساس = {base:.2f}%")
print("النموذج أحسن من الأساس" if mae < base else "النموذج لسه مش أحسن من الأساس، محتاج بيانات أكتر")
joblib.dump(model, "moisture_model.joblib")
