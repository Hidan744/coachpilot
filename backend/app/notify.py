"""Каналы уведомлений. Сейчас — Telegram; интерфейс позволяет добавить e-mail, SMS или push.

Канал без настроек сервера выключен: ничего не отправляет и честно сообщает «не подключено».
Токены хранятся только в переменных окружения сервера и в клиент не попадают.
"""

from typing import Protocol

import httpx

from app.config import get_settings


class NotConfigured(Exception):
    """Канал не настроен на сервере."""


class SendFailed(Exception):
    """Сервис доставки вернул ошибку."""


class Channel(Protocol):
    name: str

    def configured(self) -> bool: ...

    async def send(self, address: str, text: str) -> None: ...


class TelegramChannel:
    name = "telegram"

    def configured(self) -> bool:
        return bool(get_settings().telegram_bot_token)

    async def send(self, address: str, text: str) -> None:
        token = get_settings().telegram_bot_token
        if not token:
            raise NotConfigured("Telegram не подключён: на сервере не задан токен бота")
        try:
            async with httpx.AsyncClient(timeout=10) as c:
                r = await c.post(f"https://api.telegram.org/bot{token}/sendMessage",
                                 json={"chat_id": int(address), "text": text, "disable_web_page_preview": True})
        except httpx.HTTPError as e:
            raise SendFailed(f"Telegram недоступен: {type(e).__name__}") from e
        if r.status_code != 200 or not r.json().get("ok"):
            raise SendFailed(f"Telegram отклонил сообщение: {r.status_code}")


_channels: dict[str, Channel] = {"telegram": TelegramChannel()}


def channel(name: str) -> Channel:
    return _channels[name]


def set_channel(name: str, ch: Channel) -> None:
    """Подменить канал (тесты, другой провайдер)."""
    _channels[name] = ch
