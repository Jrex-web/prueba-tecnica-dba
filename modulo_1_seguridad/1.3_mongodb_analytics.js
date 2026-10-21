// =============================================================================
// PRUEBA TÉCNICA DBA - MÓDULO 1.3: MONGODB SECURITY, RBAC Y CSFLE
// Base de Datos: analytics
// Entorno: Producción
// =============================================================================

// Conectar y referenciar a la base de datos objetivo
const db = db.getSiblingDB('analytics');

print("=== INICIANDO CONFIGURACIÓN DE SEGURIDAD MÓDULO 1.3 ===");

// -----------------------------------------------------------------------------
// T1: CREACIÓN DE ROLES PERSONALIZADOS Y USUARIOS (RBAC)
// -----------------------------------------------------------------------------

// Limpieza previa de roles para permitir idempotencia en el laboratorio
print("-> Limpiando roles previos si existen...");
try { db.dropRole("eventWriter"); } catch(e) {}
try { db.dropRole("analyticsReader"); } catch(e) {}
try { db.dropRole("dataEngineer"); } catch(e) {}

// Limpieza previa de usuarios del laboratorio
print("-> Limpiando usuarios previos si existen...");
try { db.dropUser("writer_user"); } catch(e) {}
try { db.dropUser("analista_user"); } catch(e) {}
try { db.dropUser("engineer_user"); } catch(e) {}

print("-> Creando Roles Personalizados...");

// 1. Rol: eventWriter (Solo inserción en la colección 'events', sin lectura)
db.createRole({
  role: "eventWriter",
  privileges: [
    {
      resource: { db: "analytics", collection: "events" },
      actions: [ "insert" ]
    }
  ],
  roles: []
});

// 2. Rol: analyticsReader (Lectura en 'events' y agregaciones, sin escritura)
db.createRole({
  role: "analyticsReader",
  privileges: [
    {
      resource: { db: "analytics", collection: "events" },
      actions: [ "find" ] // Permite queries estándar y pipelines de agregación de lectura
    }
  ],
  roles: []
});

// 3. Rol: dataEngineer (Read/Write en todas las colecciones + Creación de Índices)
db.createRole({
  role: "dataEngineer",
  privileges: [
    {
      resource: { db: "analytics", collection: "" }, // Cadena vacía aplica a todas las colecciones
      actions: [ "find", "insert", "update", "remove", "createIndex", "dropIndex" ]
    }
  ],
  roles: []
});

print("-> Creando Usuarios Vinculados a los Roles...");

// Asignación de Usuarios según el archivo de la API (main.py)
// Nos movemos temporalmente a la base de datos de administración global de MongoDB
const adminDB = db.getSiblingDB('admin');

print("-> Creando Usuarios Vinculados a los Roles en la DB admin...");

adminDB.createUser({
  user: "writer_user",
  pwd: "WriterPassword123!",
  roles: [ { role: "eventWriter", db: "analytics" } ] // El rol pertenece a analytics
});

adminDB.createUser({
  user: "analista_user",
  pwd: "AnalistaPassword123!",
  roles: [ { role: "analyticsReader", db: "analytics" } ]
});

adminDB.createUser({
  user: "engineer_user",
  pwd: "EngineerPassword123!",
  roles: [ { role: "dataEngineer", db: "analytics" } ]
});

// -----------------------------------------------------------------------------
// T2: CLIENT-SIDE FIELD LEVEL ENCRYPTION (CSFLE) - JSON SCHEMA VÁLIDO
// -----------------------------------------------------------------------------
/*
  EXPLICACIÓN TÉCNICA DE LOS ALGORITMOS:
  - user_ip (Determinista): Mismo valor plano produce idéntico valor cifrado. Permite
    realizar búsquedas exactas por IP (filtros de igualdad B-tree) sin descifrar en el servidor.
  - user_agent (Aleatorio): Mismo valor plano produce firmas cifradas distintas en cada inserción. 
    Previene ataques de análisis de frecuencia sobre metadatos repetitivos, ideal para alta seguridad.
*/

print("-> Validando sintaxis del esquema CSFLE...");

const keyAltName_IP = "dataKey_IP";
const keyAltName_UA = "dataKey_UA";

// UUIDs simulados de ejemplo válidos para parseo de esquemas BSON
const mockUUID_IP = UUID("11111111-2222-3333-4444-555555555555");
const mockUUID_UA = UUID("66666666-7777-8888-9999-000000000000");

const csfleSchema = {
  "bsonType": "object",
  "properties": {
    "user_ip": {
      "encrypt": {
        "keyId": [ mockUUID_IP ],
        "algorithm": "AEAD_AES_256_CBC_HMAC_SHA_512-Deterministic",
        "bsonType": "string"
      }
    },
    "user_agent": {
      "encrypt": {
        "keyId": [ mockUUID_UA ],
        "algorithm": "AEAD_AES_256_CBC_HMAC_SHA_512-Random",
        "bsonType": "string"
      }
    }
  }
};

// Imprimir el esquema estructurado para asociarlo operacionalmente con la colección
printjson({
  "validator": {
    "$jsonSchema": csfleSchema
  }
});

// -----------------------------------------------------------------------------
// T3: CONFIGURACIÓN DE AUDITORÍA DE FALLOS (Explicación para Entrega)
// -----------------------------------------------------------------------------
/*
  Sintaxis para producción en el archivo mongod.conf (Formato YAML):
  
  auditLog:
     destination: file
     format: JSON
     path: /var/log/mongodb/audit.json
     filter: '{ "atype": "authCheck", "result": { "$ne": 0 } }'
     
  Sustentación: El filtro captura eventos donde 'result' no sea igual a 0 ($ne). 
  Como 0 es éxito, registrará únicamente los accesos denegados (unauthorized),
  optimizando drásticamente el espacio de almacenamiento en auditorías PCI-DSS.
*/

print("=== CONFIGURACIÓN COMPLETADA CON ÉXITO ===");
