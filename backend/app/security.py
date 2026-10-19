import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerifyMismatchError
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import get_db
from app.models import User

_hasher = PasswordHasher()
_bearer = HTTPBearer(auto_error=False)

# Хеш-заглушка, чтобы вход по несуществующему email занимал столько же времени.
_DUMMY_HASH = _hasher.hash("timing-equalizer")


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str | None, password: str) -> bool:
    try:
        return _hasher.verify(password_hash or _DUMMY_HASH, password) and password_hash is not None
    except (VerifyMismatchError, InvalidHashError):
        return False


def create_access_token(user_id: uuid.UUID) -> tuple[str, int]:
    st = get_settings()
    ttl = st.access_token_ttl_min * 60
    now = datetime.now(UTC)
    payload = {"sub": str(user_id), "iat": now, "exp": now + timedelta(seconds=ttl), "typ": "access"}
    return jwt.encode(payload, st.jwt_secret, algorithm=st.jwt_algorithm), ttl


def new_refresh_token() -> tuple[str, str, datetime]:
    token = secrets.token_urlsafe(48)
    expires = datetime.now(UTC) + timedelta(days=get_settings().refresh_token_ttl_days)
    return token, hash_refresh(token), expires


def hash_refresh(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _unauthorized(detail: str = "Требуется вход") -> HTTPException:
    return HTTPException(
        status.HTTP_401_UNAUTHORIZED, detail=detail, headers={"WWW-Authenticate": "Bearer"}
    )


async def current_user(
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    if creds is None:
        raise _unauthorized()
    st = get_settings()
    try:
        payload = jwt.decode(creds.credentials, st.jwt_secret, algorithms=[st.jwt_algorithm])
        if payload.get("typ") != "access":
            raise _unauthorized()
        user_id = uuid.UUID(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError) as e:
        raise _unauthorized("Сессия истекла, войдите снова") from e
    user = await db.get(User, user_id)
    if user is None:
        raise _unauthorized()
    return user
