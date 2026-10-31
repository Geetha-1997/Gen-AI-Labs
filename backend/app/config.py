from pydantic_settings import BaseSettings, SettingsConfigDict

class Settings(BaseSettings):
    app_name: str = "Gen-AI-Labs API"
    environment: str = "development"
    database_url: str = "postgresql+psycopg://genai:genai@localhost:5432/genai"
    jwt_secret: str = "CHANGE_ME_TO_A_LONG_RANDOM_SECRET"
    jwt_algorithm: str = "HS256"
    access_token_minutes: int = 60
    groq_api_key: str = ""
    groq_model: str = "openai/gpt-oss-120b"
    xai_api_key: str = ""
    cors_origins: str = "http://localhost:5173"
    max_message_chars: int = 20000
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def allowed_origins(self) -> list[str]:
        return [v.strip() for v in self.cors_origins.split(",") if v.strip()]

settings = Settings()
