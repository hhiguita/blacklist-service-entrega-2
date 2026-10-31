# Blacklist Service — Microservicio Lista Negra de Emails

Microservicio REST desarrollado en Python + Flask para la gestión de una lista
negra global de emails. Curso de DevOps: Entrega 1 (despliegue en AWS Elastic Beanstalk) y
Entrega 2 (integracion continua con CodePipeline + CodeBuild, sin CD).

## Stack

- Python 3.8+ / Flask
- Flask-SQLAlchemy (ORM)
- Flask-RESTful (API REST)
- Flask-Marshmallow (serialización)
- Flask-JWT-Extended (autorización por Bearer Token)
- PostgreSQL (AWS RDS) — en local usa SQLite automáticamente

## Endpoints

Ambos requieren la cabecera: `Authorization: Bearer <token>`

### POST /blacklists
Agrega un email a la lista negra.

Body (JSON):
```json
{
  "email": "cliente@ejemplo.com",
  "app_uuid": "11111111-2222-3333-4444-555555555555",
  "blocked_reason": "fraude reportado"
}
```
- `email` (obligatorio)
- `app_uuid` (obligatorio)
- `blocked_reason` (opcional, máx. 255 caracteres)

El servicio guarda además, por su cuenta: la IP de origen y la fecha/hora.

Respuesta: `201 Created`.

### GET /blacklists/&lt;email&gt;
Consulta si un email está en la lista negra.

Respuesta `200 OK`:
```json
{
  "email": "cliente@ejemplo.com",
  "blacklisted": true,
  "blocked_reason": "fraude reportado"
}
```

### GET /
Health check. Devuelve `200 OK` (lo usa Beanstalk para marcar el entorno sano).

## Ejecutar en local

```bash
python -m venv venv
venv\Scripts\activate        # Windows
pip install -r requirements.txt
python application.py
```
La app queda en http://localhost:5000 y crea un archivo `blacklist.db` (SQLite).

## Configuración por variables de entorno

| Variable | Para qué |
|---|---|
| `STATIC_BEARER_TOKEN` | Token Bearer estático (si no se define, usa uno por defecto en local) |
| `JWT_SECRET_KEY` | Clave de firma JWT |
| `RDS_HOSTNAME`, `RDS_DB_NAME`, `RDS_USERNAME`, `RDS_PASSWORD`, `RDS_PORT` | Conexión a PostgreSQL en AWS (las inyecta Beanstalk al conectar RDS) |

Si no existen las variables `RDS_*`, la app usa SQLite local automáticamente.

## Pruebas unitarias

```bash
pip install -r requirements-dev.txt
python -m pytest -v
```

13 casos en `test_app.py` con SQLite en memoria (no requieren PostgreSQL):

| Endpoint | Escenarios |
|---|---|
| `GET /` | 200 sin token |
| `POST /blacklists` | 201 y registro persistido con IP/fecha, IP real detras de proxy, 401 sin token, 401 token invalido, 400 sin email, 400 sin app_uuid, 400 motivo > 255, 400 cuerpo no JSON |
| `GET /blacklists/<email>` | 200 bloqueado (true + motivo), 200 no bloqueado (false), 401 sin token |
| (guardia) | Verifica que las pruebas usan SQLite en memoria |

## Infraestructura como codigo (`infra/`)

| Archivo | Stack | Crea |
|---|---|---|
| `ci-pipeline.yaml` | `blacklist-ci` | Conexion GitHub, bucket de artefactos, CodeBuild, CodePipeline V2 (Source + Build, **sin Deploy**), roles IAM, logs y reportes |
| `eb-app.yaml` | `blacklist-app` | Beanstalk Single Instance (Python 3.12 AL2023), RDS PostgreSQL, secreto en Secrets Manager, security groups, roles |

```bash
cd infra
./deploy-ci.sh <perfil> [arn-conexion]     # 1. CI; autorizar la conexion GitHub si queda PENDING
# 2. push a master -> el pipeline genera s3://<bucket>/builds/app-<commit>.zip
export STATIC_BEARER_TOKEN='...' JWT_SECRET_KEY='...'
./deploy-app.sh <perfil> [commit-sha]      # 3. despliegue MANUAL del artefacto en Beanstalk
./destroy.sh <perfil> [app|ci|all]         # borra todo
```

El despliegue es manual a proposito: la Entrega 2 prohibe CD. Para desplegar otra
version se vuelve a correr `deploy-app.sh` con el hash del commit.

## Postman (`postman/`)

- `blacklist-service.postman_collection.json`: 8 peticiones con tests automaticos (health, 201, true, false, 400 x2, 401 x2).
- `blacklist-service.postman_environment.json`: entorno AWS (`base_url` = output `EnvironmentURL`, `token` = `STATIC_BEARER_TOKEN`).
- `blacklist-service-local.postman_environment.json`: entorno local (`http://localhost:5000`).

Importar ambos en Postman y ejecutar la coleccion con el Collection Runner. El token del entorno AWS
no se versiona: se escribe en Postman.
