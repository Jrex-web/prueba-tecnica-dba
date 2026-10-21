from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import pymongo
import pyodbc

app = FastAPI(title="API Segura - Prueba Técnica DBA")

# Definimos la estructura del evento según los requerimientos del Módulo 1.3
class Evento(BaseModel):
    user_ip: str
    user_agent: str
    evento: str

# =============================================================================
# FLUX 1: MONGODB - ENDPOINTS SEGREGADOS POR ROL (RBAC)
# =============================================================================

# Rol: eventWriter -> Diseñado para registro de eventos (Solo ESCRITURA nativa)
@app.post("/mongodb/escritor/registrar-evento")
def escritor_registrar_evento(evento: Evento):
    try:
        # Conexión estricta usando el usuario escritor
        client = pymongo.MongoClient('mongodb://writer_user:WriterPassword123!@localhost:27017/?authSource=admin')

        db = client['analytics']
        coleccion = db['events']
        
        # Guardamos usando el modelo de datos de Pydantic
        evento_dict = evento.model_dump() 
        resultado = coleccion.insert_one(evento_dict)
        client.close()
        
        return {"status": "success", "mensaje": "Evento registrado por el rol 'eventWriter'", "id": str(resultado.inserted_id)}
    except Exception as e:
        raise HTTPException(status_code=403, detail=f"Acceso Denegado / Error: {str(e)}")


# Rol: analyticsReader -> Diseñado para analítica de datos (Solo LECTURA)
@app.get("/mongodb/analista/ver-eventos")
def analista_ver_eventos():
    try:
        # Conexión estricta usando el usuario analista
        client = pymongo.MongoClient('mongodb://analista_user:AnalistaPassword123!@localhost:27017/?authSource=admin')

        db = client['analytics']
        coleccion = db['events']
        
        eventos = list(coleccion.find())
        for e in eventos:
            e['_id'] = str(e['_id'])
            
        client.close()
        return {"status": "success", "rol": "analyticsReader", "datos": eventos}
    except Exception as e:
        raise HTTPException(status_code=403, detail=f"Acceso Denegado / Error: {str(e)}")


# Rol: dataEngineer -> Diseñado para infraestructura de datos (Lectura global y mantenimiento)
@app.get("/mongodb/ingeniero/ver-todas-colecciones")
def ingeniero_ver_datos_globales(coleccion_name: str = "events"):
    try:
        # Conexión usando el rol avanzado dataEngineer
        client = pymongo.MongoClient('mongodb://engineer_user:EngineerPassword123!@localhost:27017/?authSource=admin')

        db = client['analytics']
        
        coleccion = db[coleccion_name]
        datos = list(coleccion.find())
        for d in datos:
            d['_id'] = str(d['_id'])
            
        client.close()
        return {"status": "success", "rol": "dataEngineer", "coleccion": coleccion_name, "datos": datos}
    except Exception as e:
        raise HTTPException(status_code=403, detail=f"Acceso Denegado para Ingeniero: {str(e)}")


# Rol: dataEngineer -> Gestión Estructural de Índices (Requerimiento técnico createIndex)
@app.post("/mongodb/ingeniero/crear-indice")
def ingeniero_crear_indice(coleccion_name: str = "events", campo: str = "user_ip"):
    try:
        client = pymongo.MongoClient('mongodb://engineer_user:EngineerPassword123!@localhost:27017/?authSource=admin')

        db = client['analytics']
        coleccion = db[coleccion_name]
        
        # Acción administrativa: Crear índice ascendente
        nombre_indice = coleccion.create_index([(campo, pymongo.ASCENDING)])
        client.close()
        
        return {"status": "success", "mensaje": f"Índice '{nombre_indice}' creado en '{campo}' por dataEngineer"}
    except Exception as e:
        raise HTTPException(status_code=403, detail=f"Error estructural de privilegios: {str(e)}")


# =============================================================================
# FLUX 2: SQL SERVER - ENDPOINTS SEGREGADOS POR ROL (DDM & AUDIT)
# =============================================================================

# Rol: report_viewer -> Diseñado para visualización de reportes (Lectura enmascarada DDM)
@app.get("/mssql/reportes/usuarios-enmascarados")
def mssql_ver_usuarios_enmascarados():
    try:
        conn_str = (
            "DRIVER={ODBC Driver 17 for SQL Server};"
            "SERVER=localhost;"
            "DATABASE=HR_Production;"
            "UID=report_viewer_login;"
            "PWD=SecurePassword123!;"
            "TrustServerCertificate=yes;"
        )
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        cursor.execute("SELECT first_name, last_name, national_id, email, salary, department FROM dbo.employees")
        
        columnas = [col[0] for col in cursor.description]
        resultados = [dict(zip(columnas, row)) for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        return {"status": "success", "rol_aplicado": "report_viewer (Lectura Protegida)", "datos": resultados}
    except Exception as e:
        raise HTTPException(status_code=403, detail=f"Error en MSSQL: {str(e)}")


# Rol: hr_manager -> Diseñado para gerencia de Recursos Humanos (Acceso real UNMASK)
@app.get("/mssql/gerencia/usuarios-reales")
def mssql_ver_usuarios_reales():
    try:
        conn_str = (
            "DRIVER={ODBC Driver 17 for SQL Server};"
            "SERVER=localhost;"
            "DATABASE=HR_Production;"
            "UID=hr_manager_login;"
            "PWD=SecurePassword456!;"
            "TrustServerCertificate=yes;"
        )
        conn = pyodbc.connect(conn_str)
        cursor = conn.cursor()
        cursor.execute("SELECT first_name, last_name, national_id, email, salary, department FROM dbo.employees")
        
        columnas = [col[0] for col in cursor.description]
        resultados = [dict(zip(columnas, row)) for row in cursor.fetchall()]
        
        cursor.close()
        conn.close()
        return {"status": "success", "rol_aplicado": "hr_manager (Acceso Total)", "datos": resultados}
    except Exception as e:
        raise HTTPException(status_code=403, detail=f"Error en MSSQL: {str(e)}")
