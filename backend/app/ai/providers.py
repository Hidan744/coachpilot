"""Провайдеры языковых моделей.

Система не привязана к одному поставщику: провайдер выбирается настройкой
`CP_AI_PROVIDER` (mock | yandexgpt | gigachat | openai_compat).
Для РФ основные варианты — YandexGPT и GigaChat.
"""

import json
import time
import uuid
from dataclasses import dataclass
from typing import Protocol

import httpx

from app.config import Settings


@dataclass
class Completion:
    text: str
    tokens_in: int = 0
    tokens_out: int = 0
    model: str = ""


class ProviderError(Exception):
    """Сбой провайдера: сеть, лимиты, неверный ключ. Текст — для логов, не для пользователя."""


class LLMProvider(Protocol):
    name: str

    async def complete(self, system: str, user: str, *, temperature: float = 0.4) -> Completion: ...


class YandexGPTProvider:
    """YandexGPT (Yandex Cloud AI Studio), нативный API completion."""

    name = "yandexgpt"
    URL = "https://llm.api.cloud.yandex.net/foundationModels/v1/completion"

    def __init__(self, api_key: str, folder_id: str, model: str = "yandexgpt/latest", timeout: float = 60):
        self.api_key, self.folder_id, self.model, self.timeout = api_key, folder_id, model, timeout

    async def complete(self, system: str, user: str, *, temperature: float = 0.4) -> Completion:
        body = {
            "modelUri": f"gpt://{self.folder_id}/{self.model}",
            "completionOptions": {"stream": False, "temperature": temperature, "maxTokens": "6000"},
            "messages": [{"role": "system", "text": system}, {"role": "user", "text": user}],
            "jsonObject": True,
        }
        headers = {"Authorization": f"Api-Key {self.api_key}", "x-folder-id": self.folder_id}
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as c:
                r = await c.post(self.URL, json=body, headers=headers)
        except httpx.HTTPError as e:
            raise ProviderError(f"yandexgpt network: {e}") from e
        if r.status_code != 200:
            raise ProviderError(f"yandexgpt {r.status_code}: {r.text[:300]}")
        res = r.json()["result"]
        usage = res.get("usage", {})
        return Completion(
            text=res["alternatives"][0]["message"]["text"],
            tokens_in=int(usage.get("inputTextTokens", 0)),
            tokens_out=int(usage.get("completionTokens", 0)),
            model=res.get("modelVersion", self.model),
        )


class OpenAICompatProvider:
    """Любой сервис с OpenAI-совместимым API /chat/completions (в т.ч. локальные модели)."""

    name = "openai_compat"

    def __init__(self, base_url: str, api_key: str, model: str, timeout: float = 60, verify: bool | str = True):
        self.base_url, self.api_key, self.model = base_url.rstrip("/"), api_key, model
        self.timeout, self.verify = timeout, verify

    async def _headers(self) -> dict:
        return {"Authorization": f"Bearer {self.api_key}"}

    async def complete(self, system: str, user: str, *, temperature: float = 0.4) -> Completion:
        body = {
            "model": self.model,
            "temperature": temperature,
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        }
        try:
            async with httpx.AsyncClient(timeout=self.timeout, verify=self.verify) as c:
                r = await c.post(f"{self.base_url}/chat/completions", json=body, headers=await self._headers())
        except httpx.HTTPError as e:
            raise ProviderError(f"{self.name} network: {e}") from e
        if r.status_code != 200:
            raise ProviderError(f"{self.name} {r.status_code}: {r.text[:300]}")
        data = r.json()
        usage = data.get("usage", {})
        return Completion(
            text=data["choices"][0]["message"]["content"],
            tokens_in=int(usage.get("prompt_tokens", 0)),
            tokens_out=int(usage.get("completion_tokens", 0)),
            model=data.get("model", self.model),
        )


class GigaChatProvider(OpenAICompatProvider):
    """GigaChat (Сбер): OAuth-токен на 30 минут + OpenAI-подобный chat/completions."""

    name = "gigachat"
    OAUTH = "https://ngw.devices.sberbank.ru:9443/api/v2/oauth"

    def __init__(self, auth_key: str, scope: str = "GIGACHAT_API_PERS", model: str = "GigaChat-2-Pro",
                 verify: bool | str = True):
        super().__init__("https://gigachat.devices.sberbank.ru/api/v1", "", model, verify=verify)
        self.auth_key, self.scope = auth_key, scope
        self._token, self._expires = "", 0.0

    async def _headers(self) -> dict:
        if time.time() > self._expires - 60:
            try:
                async with httpx.AsyncClient(timeout=20, verify=self.verify) as c:
                    r = await c.post(
                        self.OAUTH,
                        data={"scope": self.scope},
                        headers={"Authorization": f"Basic {self.auth_key}", "RqUID": str(uuid.uuid4())},
                    )
            except httpx.HTTPError as e:
                raise ProviderError(f"gigachat oauth network: {e}") from e
            if r.status_code != 200:
                raise ProviderError(f"gigachat oauth {r.status_code}: {r.text[:200]}")
            data = r.json()
            self._token, self._expires = data["access_token"], data["expires_at"] / 1000
        return {"Authorization": f"Bearer {self._token}"}


class MockProvider:
    """Провайдер для разработки и тестов: отвечает планом, собранным правилами
    из переданных кандидатов. Можно задать заранее подготовленные ответы."""

    name = "mock"

    def __init__(self, scripted: list[str] | None = None, fail: bool = False):
        self.scripted = list(scripted or [])
        self.fail = fail
        self.calls: list[tuple[str, str]] = []

    async def complete(self, system: str, user: str, *, temperature: float = 0.4) -> Completion:
        self.calls.append((system, user))
        if self.fail:
            raise ProviderError("mock failure")
        if self.scripted:
            return Completion(self.scripted.pop(0), 100, 200, "mock")
        from app.ai.rules import mock_answer_from_prompt, mock_drills_from_prompt, mock_report_from_prompt

        if "ДАННЫЕ:" in user:
            answer = mock_answer_from_prompt(user)
        elif user.startswith("УПРАЖНЕНИЯ:"):
            answer = mock_drills_from_prompt(user)
        else:
            answer = mock_report_from_prompt(user)
        return Completion(json.dumps(answer, ensure_ascii=False), 100, 200, "mock")


def build_provider(st: Settings) -> LLMProvider:
    match st.ai_provider:
        case "yandexgpt":
            return YandexGPTProvider(st.ai_api_key, st.ai_folder_id, st.ai_model or "yandexgpt/latest")
        case "gigachat":
            return GigaChatProvider(st.ai_api_key, model=st.ai_model or "GigaChat-2-Pro",
                                    verify=st.ai_ca_bundle or True)
        case "openai_compat":
            return OpenAICompatProvider(st.ai_base_url, st.ai_api_key, st.ai_model)
        case _:
            return MockProvider()
