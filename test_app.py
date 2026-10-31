"""
test_app.py
-----------
Pruebas unitarias de la Entrega 2 (Integracion Continua).

Objetivo: validar automaticamente los endpoints + la seguridad por token,
SIN depender de PostgreSQL. Para eso usamos:

  - El TEST CLIENT de Flask: llama a la app en memoria (sin servidor ni puertos).
  - SQLite EN MEMORIA ("sqlite:///:memory:"): la base vive solo durante la
    prueba. Se inyecta via create_app(config_overrides) ANTES de db.init_app(),
    porque Flask-SQLAlchemy 3.x ignora cambios de URI hechos despues.

Cobertura por endpoint (13 casos):
  GET  /                    -> health
  POST /blacklists          -> exito, IP real tras proxy, auth, validaciones
  GET  /blacklists/<email>  -> bloqueado, no bloqueado, auth

Se corre con:  python -m pytest -v
"""
import pytest

from application import create_app
from models import db, Blacklist
from config import Config


TEST_CONFIG = {
    "TESTING": True,
    "SQLALCHEMY_DATABASE_URI": "sqlite:///:memory:",
}


@pytest.fixture
def app():
    """App aislada con SQLite en memoria; tablas limpias en cada prueba."""
    app = create_app(TEST_CONFIG)
    with app.app_context():
        db.create_all()
        yield app
        db.session.remove()
        db.drop_all()


@pytest.fixture
def client(app):
    return app.test_client()


@pytest.fixture
def auth(app):
    """
    Cabecera valida tomada de la config real de la app (no hardcodeada).
    Si CodeBuild define STATIC_BEARER_TOKEN, las pruebas siguen funcionando.
    """
    return {"Authorization": f"Bearer {app.config['STATIC_BEARER_TOKEN']}"}


# ---------------------------------------------------------------------------
# Guardia de aislamiento: si alguien rompe el override, esta prueba falla
# antes de que las demas escriban en un archivo .db o en RDS.
# ---------------------------------------------------------------------------
def test_usa_sqlite_en_memoria(app):
    url = db.engine.url
    assert url.drivername == "sqlite"
    assert url.database in (None, "", ":memory:")


# ---------------------------------------------------------------------------
# GET /  (health check)
# ---------------------------------------------------------------------------
def test_health_ok(client):
    """El health check responde 200 y no requiere token."""
    resp = client.get("/")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


# ---------------------------------------------------------------------------
# POST /blacklists
# ---------------------------------------------------------------------------
def test_post_blacklist_con_token_ok(client, auth, app):
    """Con token y datos correctos: 201 y el registro queda persistido con IP y fecha."""
    resp = client.post(
        "/blacklists",
        json={"email": "malo@test.com", "app_uuid": "app-123",
              "blocked_reason": "fraude"},
        headers=auth,
    )
    assert resp.status_code == 201
    assert resp.get_json()["email"] == "malo@test.com"

    registro = Blacklist.query.filter_by(email="malo@test.com").first()
    assert registro is not None
    assert registro.app_uuid == "app-123"
    assert registro.ip_address is not None      # el servicio guarda la IP
    assert registro.created_at is not None      # y la fecha/hora


def test_post_blacklist_guarda_ip_real_detras_de_proxy(client, auth, app):
    """Detras de nginx (Beanstalk) se debe guardar la IP del cliente, no la del proxy."""
    resp = client.post(
        "/blacklists",
        json={"email": "proxy@test.com", "app_uuid": "app-123"},
        headers={**auth, "X-Forwarded-For": "203.0.113.7"},
    )
    assert resp.status_code == 201
    registro = Blacklist.query.filter_by(email="proxy@test.com").first()
    assert registro.ip_address == "203.0.113.7"


def test_post_blacklist_sin_token_401(client):
    resp = client.post(
        "/blacklists",
        json={"email": "malo@test.com", "app_uuid": "app-123"},
    )
    assert resp.status_code == 401


def test_post_blacklist_token_invalido_401(client):
    resp = client.post(
        "/blacklists",
        json={"email": "malo@test.com", "app_uuid": "app-123"},
        headers={"Authorization": "Bearer token-falso"},
    )
    assert resp.status_code == 401


@pytest.mark.parametrize("payload", [
    {"app_uuid": "app-123"},                       # falta email
    {"email": "malo@test.com"},                    # falta app_uuid
    {"email": "malo@test.com", "app_uuid": "app-123",
     "blocked_reason": "x" * 256},                 # motivo > 255
])
def test_post_blacklist_validaciones_400(client, auth, payload):
    resp = client.post("/blacklists", json=payload, headers=auth)
    assert resp.status_code == 400


def test_post_blacklist_body_no_json_400(client, auth):
    resp = client.post("/blacklists", data="no-es-json",
                       content_type="text/plain", headers=auth)
    assert resp.status_code == 400


# ---------------------------------------------------------------------------
# GET /blacklists/<email>
# ---------------------------------------------------------------------------
def test_get_blacklist_bloqueado_true(client, auth):
    client.post(
        "/blacklists",
        json={"email": "bloqueado@test.com", "app_uuid": "app-123",
              "blocked_reason": "fraude"},
        headers=auth,
    )
    resp = client.get("/blacklists/bloqueado@test.com", headers=auth)
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["blacklisted"] is True
    assert data["blocked_reason"] == "fraude"


def test_get_blacklist_no_bloqueado_false(client, auth):
    resp = client.get("/blacklists/inexistente@test.com", headers=auth)
    assert resp.status_code == 200
    data = resp.get_json()
    assert data["blacklisted"] is False
    assert data["blocked_reason"] is None


def test_get_blacklist_sin_token_401(client):
    resp = client.get("/blacklists/cualquiera@test.com")
    assert resp.status_code == 401


def test_uri_postgres_usa_driver_psycopg2(monkeypatch):
    """SQLAlchemy 2.1 usa psycopg3 por defecto con 'postgresql://'; debemos fijar psycopg2."""
    monkeypatch.setenv("RDS_HOSTNAME", "db.ejemplo.internal")
    monkeypatch.setenv("RDS_DB_NAME", "ebdb")
    monkeypatch.setenv("RDS_USERNAME", "usuario")
    monkeypatch.setenv("RDS_PASSWORD", "clave")
    monkeypatch.setenv("RDS_PORT", "5432")
    assert Config.get_database_uri().startswith("postgresql+psycopg2://")
    import psycopg2  # noqa: F401  (el driver debe estar instalado)
