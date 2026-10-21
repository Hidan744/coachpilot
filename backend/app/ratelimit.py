"""Простой ограничитель попыток в памяти процесса (защита входа от перебора паролей).

Счётчики живут в памяти одного процесса: при нескольких воркерах или экземплярах API
нужен общий счётчик в Redis (см. docs/DEPLOY.md).
"""

import time
from collections import defaultdict, deque


class RateLimiter:
    def __init__(self, limit: int, window_sec: float, max_keys: int = 50_000):
        self.limit, self.window, self.max_keys = limit, window_sec, max_keys
        self._hits: dict[str, deque[float]] = defaultdict(deque)

    def hit(self, key: str) -> bool:
        """Регистрирует попытку. False — лимит превышен."""
        now = time.monotonic()
        q = self._hits[key]
        while q and now - q[0] > self.window:
            q.popleft()
        if len(q) >= self.limit:
            return False
        q.append(now)
        if len(self._hits) > self.max_keys:  # не даём словарю расти бесконечно
            self._prune(now)
        return True

    def _prune(self, now: float) -> None:
        """Удаляет только устаревшие ключи: активные счётчики сбросить переполнением нельзя."""
        for k in [k for k, q in self._hits.items() if not q or now - q[-1] > self.window]:
            del self._hits[k]

    def reset(self, key: str) -> None:
        self._hits.pop(key, None)

    def clear(self) -> None:
        self._hits.clear()


# С одного адреса — не больше 20 попыток за 15 минут на любые email: защита от перебора.
login_ip_limiter = RateLimiter(limit=20, window_sec=900)
# На один email — 10 попыток в минуту с любых адресов: чужой человек не заблокирует тренера надолго.
login_email_limiter = RateLimiter(limit=10, window_sec=60)
