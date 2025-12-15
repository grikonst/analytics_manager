FROM alpine:latest

# Установка зависимостей
RUN apk add --no-cache bash jq curl dialog ffmpeg bc tar pv zstd docker-compose

# Копирование скрипта
COPY main.sh /app/
WORKDIR /app

# Создание точки входа
RUN echo '#!/bin/bash\nbash /app/main.sh "$@"' > /entrypoint.sh && \
    chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
