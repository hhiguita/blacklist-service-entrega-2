"""
config.py
---------
Configuracion central de la aplicacion.

Idea clave: la app funciona en DOS entornos sin cambiar el codigo:
  - LOCAL (tu maquina): si no hay variables de entorno de base de datos,
    usa SQLite (un archivo .db local). No necesitas instalar PostgreSQL
    para probar.
  - PRODUCCION (AWS Beanstalk + RDS): Beanstalk inyecta las variables de
    entorno (host, usuario, clave, etc.) y la app se conecta a PostgreSQL.

Todas las credenciales se leen de variables de entorno. NUNCA se escriben
claves reales en el codigo (buena practica de seguridad).
"""
import os


class Config:
    # --- Token Bearer estatico ---
    # El enunciado permite un token fijo para simplificar (no hay login dinamico).
    # En local usamos un valor por defecto; en AWS se puede sobrescribir con la
    # variable de entorno STATIC_BEARER_TOKEN.
    STATIC_BEARER_TOKEN = os.environ.get(
        "STATIC_BEARER_TOKEN",
        "token-secreto-entrega-1-2026"
    )

    # Clave que usa Flask-JWT-Extended para firmar/validar. En este ejercicio
    # el token es estatico, pero la libreria igual necesita una clave.
    JWT_SECRET_KEY = os.environ.get(
        "JWT_SECRET_KEY",
        "clave-jwt-entrega-1-cambiar-en-prod"
    )

    # SQLAlchemy: desactiva un sistema de notificaciones que no usamos
    # (evita un warning y ahorra memoria).
    SQLALCHEMY_TRACK_MODIFICATIONS = False

    @staticmethod
    def get_database_uri():
        """
        Construye la cadena de conexion a la base de datos.

        Si existen las variables de entorno de RDS (las que inyecta Beanstalk
        cuando conectas una base de datos), arma la URI de PostgreSQL.
        Si no existen (estas en local), devuelve SQLite.
        """
        db_host = os.environ.get("RDS_HOSTNAME")      # ej. mi-base.xxxx.us-east-1.rds.amazonaws.com
        db_name = os.environ.get("RDS_DB_NAME")        # ej. ebdb
        db_user = os.environ.get("RDS_USERNAME")       # ej. postgres
        db_pass = os.environ.get("RDS_PASSWORD")       # la clave
        db_port = os.environ.get("RDS_PORT", "5432")   # 5432 es el puerto estandar de PostgreSQL

        if db_host and db_name and db_user:
            # Entorno AWS: conexion a PostgreSQL
            return (
                f"postgresql+psycopg2://{db_user}:{db_pass}"
                f"@{db_host}:{db_port}/{db_name}"
            )

        # Entorno local: SQLite (archivo blacklist.db en la carpeta del proyecto)
        return "sqlite:///blacklist.db"
