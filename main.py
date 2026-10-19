from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from pymongo import MongoClient
import pymysql
import psycopg2

app = FastAPI(
    title="Mi API con Docker Databases",
    description="API para interactuar con Postgres, MySQL y MongoDB",
    version="1.0"
)

# --- MODELOS DE DATOS (Pydantic) ---
# Define la estructura de los datos que vas a recibir en las peticiones HTTP
class Usuario(BaseModel):
    nombre: str
    email: str

# --- RUTA DE PRUEBA ---
@app.get("/")
def inicio():
    return {"mensaje": "¡API corriendo perfectamente!"}

# --- ENDPOINT PARA MYSQL ---
@app.post("/mysql/usuarios")
def guardar_en_mysql(usuario: Usuario):
    try:
        connection = pymysql.connect(
            host='localhost',
            port=3307,  # Tu puerto corregido de Docker
            user='root',
            password='password',
            database='mi_base_datos'
        )
        with connection.cursor() as cursor:
            # NOTA: Asegúrate de tener creada la tabla 'usuarios' previamente
            sql = "INSERT INTO usuarios (nombre, email) VALUES (%s, %s)"
            cursor.execute(sql, (usuario.nombre, usuario.email))
        connection.commit()
        connection.close()
        return {"status": "success", "destino": "MySQL", "datos": usuario}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error en MySQL: {str(e)}")

# --- ENDPOINT PARA MONGODB ---
@app.post("/mongodb/usuarios")
def guardar_en_mongo(usuario: Usuario):
    try:
        # Al no configurar credenciales estrictas en el servicio base de Mongo, conectamos directo
        client = MongoClient('mongodb://localhost:27017/')
        db = client['mi_base_datos']
        coleccion = db['usuarios']
        
        # Insertamos el registro como un diccionario de Python
        resultado = coleccion.insert_one(usuario.model_dump())
        client.close()
        return {"status": "success", "destino": "MongoDB", "id_insertado": str(resultado.inserted_id)}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error en MongoDB: {str(e)}")
