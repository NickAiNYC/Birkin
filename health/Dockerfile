FROM python:3.12-alpine
WORKDIR /app
RUN pip install flask
COPY health/health_endpoint.py .
EXPOSE 9999
CMD ["python", "health_endpoint.py"]
