# Dockerfile (Entrega 3 - CD sobre AWS Fargate)
# ---------------------------------------------
# Imagen del microservicio. La construye CodeBuild en cada commit a master y
# CodeDeploy la despliega en Fargate.
#
# Imagen base desde ECR Public: Docker Hub limita las descargas anonimas desde
# las IPs compartidas de CodeBuild y haria fallar builds al azar.
FROM public.ecr.aws/docker/library/python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dependencias primero para aprovechar la cache de capas
COPY requirements.txt .
RUN pip install -r requirements.txt gunicorn==23.0.0

COPY application.py config.py models.py schemas.py resources.py ./

# Usuario sin privilegios
RUN useradd --create-home appuser && chown -R appuser /app
USER appuser

EXPOSE 5000

# STATIC_BEARER_TOKEN, JWT_SECRET_KEY y RDS_* los inyecta la Task Definition de ECS.
# --preload: application.py crea las tablas al importarse; con --preload ocurre una
# sola vez en el proceso maestro y no en carrera entre los workers.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--threads", "4", "--preload", "application:app_inexistente"]
