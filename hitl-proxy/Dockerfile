FROM python:3.12-alpine

WORKDIR /app

# Install build deps for any compiled packages
RUN apk add --no-cache gcc musl-dev

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8687

ENV HITL_PORT=8687
ENV HITL_ENABLED=true
ENV HITL_TIMEOUT_SECONDS=300
ENV HITL_RISK_THRESHOLD=HIGH
ENV HITL_DEFAULT_ACTION=deny
ENV HITL_CONFIG=/app/config.yml
ENV HITL_DB=/data/hitl.db

CMD ["python", "main.py"]
