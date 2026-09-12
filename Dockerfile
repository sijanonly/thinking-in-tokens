FROM ghcr.io/astral-sh/uv:0.8.17-python3.12-bookworm-slim

WORKDIR /app

ENV UV_LINK_MODE=copy
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-dev

ENV PATH="/app/.venv/bin:$PATH"

CMD ["sh"]
