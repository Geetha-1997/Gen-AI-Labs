import json, logging
from datetime import datetime, timezone
from fastapi import FastAPI, Depends, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from sqlalchemy.orm import Session
from sqlalchemy import desc
from .config import settings
from .database import get_db
from .models import User, Conversation, Message
from .schemas import Credentials, TokenOut, UserOut, ConversationOut, MessageOut, ChatIn
from .auth import hash_password, verify_password, create_token, current_user
from .providers import stream_groq, ProviderNotConfigured

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("gen-ai-labs")
app = FastAPI(title=settings.app_name, version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=settings.allowed_origins, allow_credentials=True, allow_methods=["GET", "POST", "DELETE", "OPTIONS"], allow_headers=["Authorization", "Content-Type"])

@app.on_event("startup")
def startup():
    if settings.environment == "production":
        if len(settings.jwt_secret.encode()) < 32 or settings.jwt_secret == "CHANGE_ME_TO_A_LONG_RANDOM_SECRET":
            raise RuntimeError("Production requires a strong JWT_SECRET (32+ bytes)")
        if not settings.groq_api_key:
            raise RuntimeError("Production requires GROQ_API_KEY")
    log.info("API startup complete; database schema managed by Alembic")

@app.get("/health/live")
def live(): return {"status": "ok"}

@app.get("/health/ready")
def ready(db: Session = Depends(get_db)):
    try: db.execute(__import__("sqlalchemy").text("SELECT 1")); return {"status": "ready"}
    except Exception: raise HTTPException(status_code=503, detail="Database unavailable")

@app.post("/api/auth/register", response_model=TokenOut, status_code=201)
def register(payload: Credentials, db: Session = Depends(get_db)):
    email = payload.email.lower()
    if db.query(User).filter(User.email == email).first(): raise HTTPException(409, "Email already registered")
    user = User(email=email, password_hash=hash_password(payload.password)); db.add(user); db.commit(); db.refresh(user)
    return {"access_token": create_token(user.id), "user": user}

@app.post("/api/auth/login", response_model=TokenOut)
def login(payload: Credentials, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == payload.email.lower()).first()
    if not user or not verify_password(payload.password, user.password_hash): raise HTTPException(401, "Incorrect email or password")
    if not user.is_active: raise HTTPException(403, "Account disabled")
    return {"access_token": create_token(user.id), "user": user}

@app.get("/api/auth/me", response_model=UserOut)
def me(user: User = Depends(current_user)): return user

@app.get("/api/conversations", response_model=list[ConversationOut])
def list_conversations(db: Session = Depends(get_db), user: User = Depends(current_user)):
    return db.query(Conversation).filter_by(user_id=user.id).order_by(desc(Conversation.updated_at)).all()

@app.post("/api/conversations", response_model=ConversationOut, status_code=201)
def create_conversation(db: Session = Depends(get_db), user: User = Depends(current_user)):
    item = Conversation(user_id=user.id); db.add(item); db.commit(); db.refresh(item); return item

def owned_conversation(conversation_id: int, user: User, db: Session) -> Conversation:
    item = db.query(Conversation).filter_by(id=conversation_id, user_id=user.id).first()
    if not item: raise HTTPException(404, "Conversation not found")
    return item

@app.get("/api/conversations/{conversation_id}/messages", response_model=list[MessageOut])
def get_messages(conversation_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    item = owned_conversation(conversation_id, user, db); return item.messages

@app.delete("/api/conversations/{conversation_id}", status_code=204)
def delete_conversation(conversation_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    item = owned_conversation(conversation_id, user, db); db.delete(item); db.commit(); return None

@app.post("/api/conversations/{conversation_id}/chat")
def chat(conversation_id: int, payload: ChatIn, db: Session = Depends(get_db), user: User = Depends(current_user)):
    if not payload.content.strip(): raise HTTPException(422, "Message cannot be blank")
    if len(payload.content) > settings.max_message_chars: raise HTTPException(413, "Message too large")
    conversation = owned_conversation(conversation_id, user, db)
    history = [{"role": m.role, "content": m.content} for m in conversation.messages[-30:]]
    user_message = Message(conversation_id=conversation.id, role="user", content=payload.content.strip())
    db.add(user_message)
    if conversation.title == "New conversation": conversation.title = payload.content.strip()[:70]
    conversation.updated_at = datetime.now(timezone.utc)
    db.commit()
    conversation_id = conversation.id
    history.append({"role": "user", "content": payload.content.strip()})
    # Stream generation and persist the assistant response only after successful completion.
    def generate():
        chunks = []
        try:
            for token in stream_groq([{"role": "system", "content": "You are Gen-AI-Labs, a precise and helpful AI assistant."}] + history):
                chunks.append(token)
                yield "data: " + json.dumps({"token": token}) + "\n\n"
            answer = "".join(chunks)
            with __import__("contextlib").closing(__import__("app.database", fromlist=["SessionLocal"]).SessionLocal()) as session:
                session.add(Message(conversation_id=conversation_id, role="assistant", content=answer))
                session.commit()
            yield "data: " + json.dumps({"done": True}) + "\n\n"
        except ProviderNotConfigured as exc:
            log.error("AI provider configuration missing")
            yield "data: " + json.dumps({"error": str(exc)}) + "\n\n"
        except Exception:
            log.exception("Chat generation failed")
            yield "data: " + json.dumps({"error": "The AI provider request failed. Please retry."}) + "\n\n"
    return StreamingResponse(generate(), media_type="text/event-stream", headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no", "Connection": "keep-alive"})
