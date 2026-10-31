from datetime import datetime
from pydantic import BaseModel, EmailStr, Field

class Credentials(BaseModel):
    email: EmailStr
    password: str = Field(min_length=10, max_length=72)
class UserOut(BaseModel):
    id: int
    email: EmailStr
    class Config: from_attributes = True
class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user: UserOut
class ConversationOut(BaseModel):
    id: int
    title: str
    created_at: datetime
    updated_at: datetime
    class Config: from_attributes = True
class MessageOut(BaseModel):
    id: int
    role: str
    content: str
    created_at: datetime
    class Config: from_attributes = True
class ChatIn(BaseModel):
    content: str = Field(min_length=1, max_length=20000)
