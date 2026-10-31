"""
resources.py
------------
Aqui viven los ENDPOINTS (los recursos REST) usando Flask-RESTful.

En Flask-RESTful cada "recurso" es una clase. Los metodos de la clase
(post, get) responden al verbo HTTP del mismo nombre. Es una forma ordenada
de agrupar la logica de cada ruta.

Los dos endpoints estan protegidos con un Bearer Token estatico: antes de
ejecutar la logica, se valida que la cabecera 'Authorization: Bearer <token>'
traiga el token correcto. Si no, se responde 401 (no autorizado).
"""
from datetime import datetime
from functools import wraps

from flask import request, current_app
from flask_restful import Resource

from models import db, Blacklist
from schemas import blacklist_schema


def requiere_token(f):
    """
    Decorador de autorizacion.

    Un "decorador" envuelve una funcion para ejecutar codigo antes/despues.
    Aqui revisamos la cabecera Authorization y comparamos el token contra el
    valor estatico de la config. Si no coincide, cortamos con 401.
    """
    @wraps(f)
    def wrapper(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        esperado = current_app.config["STATIC_BEARER_TOKEN"]

        # El formato correcto es: "Bearer <token>"
        if not auth.startswith("Bearer "):
            return {"message": "Falta el token Bearer en la cabecera Authorization"}, 401

        token = auth.split("Bearer ", 1)[1].strip()
        if token != esperado:
            return {"message": "Token invalido"}, 401

        # Token OK: ejecuta el endpoint real.
        return f(*args, **kwargs)

    return wrapper


class BlacklistResource(Resource):
    """
    Recurso para la ruta /blacklists.
    Implementa el POST (agregar email a la lista negra).
    """

    @requiere_token
    def post(self):
        # 1. Leer el JSON del cuerpo de la peticion.
        data = request.get_json(silent=True)
        if not data:
            return {"message": "El cuerpo debe ser JSON valido"}, 400

        email = data.get("email")
        app_uuid = data.get("app_uuid")
        blocked_reason = data.get("blocked_reason")  # opcional

        # 2. Validaciones de entrada.
        if not email:
            return {"message": "El campo 'email' es obligatorio"}, 400
        if not app_uuid:
            return {"message": "El campo 'app_uuid' es obligatorio"}, 400
        if blocked_reason and len(blocked_reason) > 255:
            return {"message": "'blocked_reason' no puede superar 255 caracteres"}, 400

        # 3. Datos que guarda el servicio por su cuenta (no los manda el cliente):
        #    - IP de origen de la solicitud
        #    - fecha/hora actual
        ip_origen = request.remote_addr
        ahora = datetime.utcnow()

        # 4. Crear y guardar el registro en la base de datos.
        registro = Blacklist(
            email=email,
            app_uuid=app_uuid,
            blocked_reason=blocked_reason,
            ip_address=ip_origen,
            created_at=ahora,
        )
        db.session.add(registro)
        db.session.commit()

        # 5. Respuesta de confirmacion (201 = creado).
        return {
            "message": "Email agregado a la lista negra correctamente",
            "email": email,
        }, 201


class BlacklistCheckResource(Resource):
    """
    Recurso para la ruta /blacklists/<email>.
    Implementa el GET (consultar si un email esta en la lista negra).
    """

    @requiere_token
    def get(self, email):
        # Buscar el email en la tabla. first() devuelve el primero o None.
        registro = Blacklist.query.filter_by(email=email).first()

        if registro:
            # Esta en la lista negra: devolvemos True y el motivo.
            return {
                "email": email,
                "blacklisted": True,
                "blocked_reason": registro.blocked_reason,
            }, 200

        # No esta en la lista negra.
        return {
            "email": email,
            "blacklisted": False,
            "blocked_reason": None,
        }, 200
