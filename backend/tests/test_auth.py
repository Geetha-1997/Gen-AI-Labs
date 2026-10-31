from app.auth import hash_password, verify_password, create_token
from jose import jwt
from app.config import settings

def test_password_hash_roundtrip():
    encoded = hash_password("CorrectHorseBatteryStaple!")
    assert encoded != "CorrectHorseBatteryStaple!"
    assert verify_password("CorrectHorseBatteryStaple!", encoded)
    assert not verify_password("wrong-password", encoded)

def test_token_contains_subject():
    token = create_token(42)
    payload = jwt.decode(token, settings.jwt_secret, algorithms=[settings.jwt_algorithm])
    assert payload["sub"] == "42"
