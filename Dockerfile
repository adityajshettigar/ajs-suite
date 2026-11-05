FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .
COPY templates/ ./templates/

RUN useradd --system --uid 10001 --no-create-home appuser \
    && mkdir -p /var/lib/ajs-admin/sessions \
    && chown -R appuser:appuser /app /var/lib/ajs-admin

USER appuser

EXPOSE 8001

CMD ["gunicorn", "--workers", "1", "--threads", "4", \
     "--bind", "0.0.0.0:8001", "--timeout", "30", "app:app"]
