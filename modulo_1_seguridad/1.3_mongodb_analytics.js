// =============================================================================
// PRUEBA TÉCNICA DBA - MÓDULO 1.3: MONGODB SECURITY, RBAC Y CSFLE
// Base de Datos: analytics
// Entorno: Producción
// =============================================================================

// Conectar a la base de datos objetivo
const db = db.getSiblingDB('analytics');

-- -----------------------------------------------------------------------------
-- T1: CREACIÓN DE ROLES PERSONALIZADOS (RBAC)
-- -----------------------------------------------------------------------------

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
      resource: { db: "analytics", collection: "" }, // Cadena vacía aplica a todas las colecciones de la DB
      actions: [ "find", "insert", "update", "remove", "createIndex", "dropIndex" ]
    }
  ],
  roles: []
});

-- -----------------------------------------------------------------------------
-- T2: CLIENT-SIDE FIELD LEVEL ENCRYPTION (CSFLE) - JSON SCHEMA
-- -----------------------------------------------------------------------------
/*
  EXPLICACIÓN TÉCNICA DE LOS ALGORITMOS:
  - user_ip (Determinista): Mismo valor plano produce idéntico valor cifrado. Permite
    realizar búsquedas exactas por IP (filtros de igualdad B-tree) sin descifrar el servidor.
  - user_agent (Aleatorio): Mismo valor plano produce firmas cifradas distintas en cada inserción. 
    Previene ataques de análisis de frecuencia sobre metadatos repetitivos, ideal para alta seguridad.
*/

const keyAltName_IP = "dataKey_IP";
const keyAltName_UA = "dataKey_UA";

const csfleSchema = {
  "bsonType": "object",
  "properties": {
    "user_ip": {
      "encrypt": {
        "keyId": [ /_ El UUID de la Key en la bóveda de llaves (Key Vault) _/ ],
        "algorithm": "AEAD_AES_256_CBC_HMAC_SHA_512-Deterministic",
        "bsonType": "string"
      }
    },
    "user_agent": {
      "encrypt": {
        "keyId": [ /_ El UUID de la Key en la bóveda de llaves (Key Vault) _/ ],
        "algorithm": "AEAD_AES_256_CBC_HMAC_SHA_512-Random",
        "bsonType": "string"
      }
    }
  }
};

// Imprimir el esquema para asociarlo operacionalmente con la validación de la colección
printjson({
  "validator": {
    "$jsonSchema": csfleSchema
  }
});

-- -----------------------------------------------------------------------------
-- T3: COMANDO PARA HABILITAR AUDITORÍA DE FALLOS (authCheck)
-- -----------------------------------------------------------------------------
/*
  Este comando configura el subsistema de auditoría nativo en mongod.conf 
  o mediante parámetros en caliente para registrar intentos de acceso no autorizados.
*/

// Sintaxis para la consola/archivo de configuración (YAML de inicialización de servidor de Producción)
/*
auditLog:
   destination: file
   format: JSON
   path: /var/log/mongodb/audit.json
   filter: '{ "atype": "authCheck", "result": { "$ne": 0 } }' 
   // result: 0 significa Éxito, por ende, cualquier valor diferente de 0 ($ne) es una falla/denegación.
*/
