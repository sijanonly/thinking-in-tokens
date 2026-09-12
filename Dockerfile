FROM ghcr.io/astral-sh/uv:0.8.17-python3.12-bookworm-slim

WORKDIR /repo

ENV UV_COMPILE_BYTECODE=1
ENV UV_LINK_MODE=copy
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Install dependencies using the lockfile first.
# This improves Docker layer caching and reproducibility.
COPY pyproject.toml uv.lock ./

RUN uv sync --frozen --no-dev

# Copy the Pelican project.
COPY . .

# Build the static website.
RUN uv run --no-sync pelican content \
    -s pelicanconf.py \
    -o output

CMD ["sh", "-c", "test -d output && echo 'Pelican site built successfully.'"]
