from datetime import UTC, datetime

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db import get_db
from app.models import RefreshToken, Subscription, User
from app.ratelimit import login_limiter
from app.schemas import LoginIn, RefreshIn, RegisterIn, TokensOut
from app.security import (
    create_access_token,
    hash_password,
    hash_refresh,
    new_refresh_token,
    verify_password,
)

router = APIRouter(prefix="/auth", tags=["auth"])


async def _issue_tokens(db: AsyncSession, user: User) -> TokensOut:
    access, ttl = create_access_token(user.id)
    refresh, refresh_hash, expires = new_refresh_token()
    db.add(RefreshToken(user_id=user.id, token_hash=refresh_hash, expires_at=expires))
    await db.commit()
    return TokensOut(access_token=access, refresh_token=refresh, expires_in=ttl)


@router.post("/register", response_model=TokensOut, status_code=status.HTTP_201_CREATED)
async def register(body: RegisterIn, db: AsyncSession = Depends(get_db)) -> TokensOut:
    email = body.email.lower()
    if await db.scalar(select(User.id).where(func.lower(User.email) == email)):
        raise HTTPException(status.HTTP_409_CONFLICT, "Пользователь с таким email уже существует")
    user = User(
        email=email,
        password_hash=hash_password(body.password),
        name=body.name.strip(),
        consent_version=get_settings().consent_version,
    )
    db.add(user)
    await db.flush()
    db.add(Subscription(user_id=user.id, ai_quota_month=get_settings().ai_free_quota_month))
    return await _issue_tokens(db, user)


@router.post("/login", response_model=TokensOut)
async def login(body: LoginIn, request: Request, db: AsyncSession = Depends(get_db)) -> TokensOut:
    key = f"{request.client.host if request.client else '-'}:{body.email.lower()}"
    if not login_limiter.hit(key):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Слишком много попыток входа. Подождите 5 минут.")
    user = await db.scalar(select(User).where(func.lower(User.email) == body.email.lower()))
    if not verify_password(user.password_hash if user else None, body.password):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Неверный email или пароль")
    login_limiter.reset(key)
    return await _issue_tokens(db, user)


@router.post("/refresh", response_model=TokensOut)
async def refresh(body: RefreshIn, db: AsyncSession = Depends(get_db)) -> TokensOut:
    token = await db.scalar(
        select(RefreshToken)
        .where(RefreshToken.token_hash == hash_refresh(body.refresh_token))
        .with_for_update()
    )
    now = datetime.now(UTC)
    if token is None or token.revoked_at is not None or token.expires_at <= now:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Сессия истекла, войдите снова")
    token.revoked_at = now  # ротация: каждый refresh-токен одноразовый
    user = await db.get(User, token.user_id)
    return await _issue_tokens(db, user)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: RefreshIn, db: AsyncSession = Depends(get_db)) -> None:
    token = await db.scalar(
        select(RefreshToken).where(RefreshToken.token_hash == hash_refresh(body.refresh_token))
    )
    if token is not None and token.revoked_at is None:
        token.revoked_at = datetime.now(UTC)
        await db.commit()
