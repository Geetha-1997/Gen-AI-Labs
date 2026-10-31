from collections.abc import Iterator
from groq import Groq
from .config import settings

class ProviderNotConfigured(RuntimeError): pass

def stream_groq(messages: list[dict[str, str]]) -> Iterator[str]:
    if not settings.groq_api_key:
        raise ProviderNotConfigured("GROQ_API_KEY is not configured")
    client = Groq(api_key=settings.groq_api_key, timeout=120.0, max_retries=2)
    stream = client.chat.completions.create(model=settings.groq_model, messages=messages, stream=True, temperature=0.4, max_completion_tokens=2048)
    for chunk in stream:
        delta = chunk.choices[0].delta.content if chunk.choices else None
        if delta: yield delta
