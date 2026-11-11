from datetime import datetime, timezone
import secrets
from fastapi import FastAPI, Depends, HTTPException, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from sqlalchemy import create_engine, Boolean, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import DeclarativeBase, sessionmaker, Mapped, mapped_column
import bcrypt

# ================= 1. إعداد قاعدة البيانات (SQLite) =================
DATABASE_URL = "sqlite:///./agromind.db"
engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)

class Base(DeclarativeBase):
    pass

class User(Base):
    __tablename__ = "users"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    full_name: Mapped[str] = mapped_column(String(150), default="Elsaeed Ahmed Elnagar")
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    role: Mapped[str] = mapped_column(String(50), default="Enterprise Admin")
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

class Subscription(Base):
    __tablename__ = "subscriptions"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    user_id: Mapped[int] = mapped_column(Integer, ForeignKey("users.id"))
    plan: Mapped[str] = mapped_column(String(50), default="PRO")
    status: Mapped[str] = mapped_column(String(50), default="active")

# ================= 2. نماذج البيانات (Pydantic Schemas) =================
class AuthIn(BaseModel):
    email: str
    password: str

class RegisterIn(BaseModel):
    full_name: str = "Elsaeed Ahmed Elnagar"
    email: str
    password: str

class PromptIn(BaseModel):
    prompt: str

# ================= 3. FastAPI App & Endpoints =================
app = FastAPI(title="AgroMind Enterprise Platform", version="3.0.0")

@app.on_event("startup")
def startup_db():
    Base.metadata.create_all(bind=engine)
    db = SessionLocal()
    admin = db.query(User).filter(User.email == "elsaeedelsaeed5@gmail.com").first()
    if not admin:
        hashed_pw = bcrypt.hashpw("12345678".encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
        admin = User(
            full_name="Elsaeed Ahmed Elnagar",
            email="elsaeedelsaeed5@gmail.com",
            password_hash=hashed_pw,
            role="Enterprise Master"
        )
        db.add(admin)
        db.commit()
    db.close()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

def create_access_token(user_id: int):
    return secrets.token_hex(32)

@app.post("/api/auth/register")
def register(data: RegisterIn, response: Response, db = Depends(get_db)):
    email = data.email.lower()
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        raise HTTPException(status_code=400, detail="البريد الإلكتروني مسجل مسبقاً")
    
    hashed_password = bcrypt.hashpw(data.password.encode('utf-8'), bcrypt.gensalt()).decode('utf-8')
    user = User(full_name=data.full_name, email=email, password_hash=hashed_password)
    db.add(user)
    db.flush()
    db.add(Subscription(user_id=user.id, plan="PRO", status="active"))
    db.commit()
    db.refresh(user)

    token = create_access_token(user.id)
    response.set_cookie(key="access_token", value=token, httponly=True, path="/")
    return {"message": "تم إنشاء الحساب بنجاح", "email": user.email}

@app.post("/api/auth/login")
def login(data: AuthIn, response: Response, db = Depends(get_db)):
    user = db.query(User).filter(User.email == data.email.lower()).first()
    
    if not user or not bcrypt.checkpw(data.password.encode('utf-8'), user.password_hash.encode('utf-8')):
        raise HTTPException(status_code=400, detail="البريد الإلكتروني أو كلمة المرور غير صحيحة")
        
    token = create_access_token(user.id)
    response.set_cookie(key="access_token", value=token, httponly=True, path="/")
    return {"message": "تم تسجيل الدخول بنجاح", "email": user.email}

@app.post("/api/ai/ask")
def ask_ai(data: PromptIn):
    q = data.prompt.lower()
    if "ري" in q or "مياه" in q or "تصميم" in q or "شبكات" in q:
        reply = "<b>💡 تقرير استشاري هندسي متكامل للري:</b><br>1. حساب إجمالي التصرفات (Q) والضغط المطلوب.<br>2. اختيار أقطار المواسير وتوزيع النقاطات بدقة لتجنب الفاقد."
    elif "لاندسكيب" in q or "حدائق" in q or "تنسيق" in q:
        reply = "<b>🌿 الاستشارة الهندسية لمشاريع اللاندسكيب:</b><br>التنسيق الهندسي بين Hardscape و Softscape وتوزيع رشاشات الـ Pop-up بكفاءة عالية."
    elif "صوب" in q or "بيوت" in q or "طماطم" in q:
        reply = "<b>🏡 إدارة وهندسة الصوب الزراعية:</b><br>التحكم في المناخ الداخلي، الرطوبة، وأنظمة التسميد الآلي (Fertigation)."
    elif "plc" in q or "أوتوميشن" in q or "كنترول" in q or "arduino" in q:
        reply = "<b>⚡ منظومة الأتمتة الصناعية:</b><br>استخدام وحدات PLC ومتحكمات IoT لتشغيل المضخات والمحابس عن بُعد."
    else:
        reply = f"<b>🤖 إجابة خبير أجرو-مايند الذكي:</b><br>استفسارك بشأن <b>'{data.prompt}'</b> تم تحليله بنجاح وفق المعايير الهندسية والزراعية المعتمدة."
    return {"response": reply}

@app.get("/", response_class=HTMLResponse)
def serve_frontend():
    with open("site/app.html", "r", encoding="utf-8") as f:
        return f.read()