from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app import sync
from app.audit import audit
from app.db import get_db
from app.models import User
from app.schemas import DeleteAccountIn, ProfileUpdate, UserOut
from app.security import current_user, verify_password

router = APIRouter(tags=["account"])


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(current_user)) -> User:
    return user


@router.patch("/me", response_model=UserOut)
async def update_me(
    body: ProfileUpdate, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
) -> User:
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(user, k, v.strip() if isinstance(v, str) else v)
    await db.commit()
    await db.refresh(user)
    return user


@router.get("/account/export")
async def export_account(
    request: Request, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
) -> dict:
    await audit(db, user.id, "data_exported", request)
    await db.commit()
    return {
        "user": UserOut.model_validate(user).model_dump(mode="json"),
        "data": await sync.export_all(db, user.id),
    }


@router.post("/account/delete", status_code=status.HTTP_204_NO_CONTENT)
async def delete_account(
    body: DeleteAccountIn, request: Request, user: User = Depends(current_user), db: AsyncSession = Depends(get_db)
) -> None:
    if not verify_password(user.password_hash, body.password):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Неверный пароль")
    # Все данные пользователя удаляются каскадом (ON DELETE CASCADE); в журнале остаётся обезличенная запись.
    await audit(db, None, "account_deleted", request)
    await db.delete(user)
    await db.commit()
