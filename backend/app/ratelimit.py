"""Простой ограничитель попыток в памяти процесса (защита входа от перебора паролей).

Для нескольких экземпляров API заменить на Redis; для MVP с одним процессом достаточно.
"""

import time
from collections import defaultdict, deque


class RateLimiter:
    def __init__(self, limit: int, window_sec: float):
        self.limit, self.window = limit, window_sec
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
        if len(self._hits) > 50_000:  # не даём словарю расти бесконечно
            self._hits.clear()
        return True

    def reset(self, key: str) -> None:
        self._hits.pop(key, None)


login_limiter = RateLimiter(limit=8, window_sec=300)
