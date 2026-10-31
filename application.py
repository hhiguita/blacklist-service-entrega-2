"""
application.py
--------------
PUNTO DE ENTRADA de la aplicacion.

IMPORTANTE para AWS Beanstalk: el archivo debe llamarse 'application.py' y
exponer una variable llamada 'application'. Beanstalk busca exactamente ese
nombre para arrancar la app. (Lo aprendimos en el Tutorial 1.)

Aqui "armamos" la app: cargamos la config, enlazamos la base de datos,
Marshmallow y JWT, registramos los endpoints y creamos las tablas.
"""
from flask import Flask, jsonify
from werkzeug.middleware.proxy_fix import ProxyFix
from flask_restful import Api
from flask_jwt_extended import JWTManager

from config import Config
from models import db
from schemas import ma
from resources import BlacklistResource, BlacklistCheckResource


def create_app(config_overrides=None):
    """
    Crea y configura la instancia de Flask (patron 'application factory').

    config_overrides (dict, opcional): valores que reemplazan la config ANTES
    de enlazar las extensiones. Lo usan las pruebas para forzar SQLite en
    memoria. Es obligatorio aplicarlo antes de db.init_app(): Flask-SQLAlchemy
    3.x lee la config una sola vez en init_app() y crea el engine ahi; cambiar
    SQLALCHEMY_DATABASE_URI despues no tiene efecto.
    """
    app = Flask(__name__)

    # 1. Cargar configuracion (token, JWT) y la URI de base de datos.
    app.config.from_object(Config)
    app.config["SQLALCHEMY_DATABASE_URI"] = Config.get_database_uri()
    if config_overrides:
        app.config.update(config_overrides)

    # 1b. Beanstalk pone nginx delante de la app: sin esto request.remote_addr
    #     seria la IP del proxy (127.0.0.1) y no la del cliente. x_for=1 confia
    #     solo en el ultimo salto (nginx). Con un ALB delante habria que usar 2.
    app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1)

    # 2. Enlazar las extensiones con la app.
    db.init_app(app)
    ma.init_app(app)
    JWTManager(app)

    # 3. Registrar los endpoints REST.
    api = Api(app)
    api.add_resource(BlacklistResource, "/blacklists")
    api.add_resource(BlacklistCheckResource, "/blacklists/<string:email>")

    # 4. Endpoint de salud. Beanstalk hace health checks a "/"; devolvemos 200
    #    para que el entorno se marque como sano (Green).
    @app.route("/")
    def health():
        return jsonify({
            "service": "blacklist-service",
            "status": "ok"
        }), 200

    # 5. Crear las tablas si no existen (en local crea blacklist.db;
    #    en RDS crea la tabla la primera vez).
    with app.app_context():
        db.create_all()

    return app


# Variable que Beanstalk busca para arrancar la app.
application = create_app()


if __name__ == "__main__":
    # Ejecucion local para pruebas: http://localhost:5000
    # debug=True recarga al cambiar codigo y muestra errores detallados.
    application.run(host="0.0.0.0", port=5000, debug=True)
