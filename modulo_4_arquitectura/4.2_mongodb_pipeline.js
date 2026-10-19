// =============================================================================
// PRUEBA TÉCNICA DBA - MÓDULO 4.2: PIPELINE ETL (MONGODB ➡️ POSTGRESQL)
// Entorno: Producción
// =============================================================================

// -----------------------------------------------------------------------------
// T2: AGGREGATION PIPELINE EN MONGODB (Extracción, Limpieza y Aplanamiento)
// -----------------------------------------------------------------------------
/*
  ESTRATEGIA DEL PIPELINE:
  1. Filtra los eventos requeridos optimizando el uso de índices de tiempo.
  2. Aplana la estructura anidada del JSON variable de WhatsApp API.
  3. Tipifica y limpia los campos clave para asegurar compatibilidad estricta con PostgreSQL.
*/

const pipeline = [
  {
    $match: {
      "event_type": "message_received",
      "timestamp": { $exists: true }
    }
  },
  {
    $project: {
      _id: 0, // Descartamos el ObjectId nativo para usar el wa_message_id de negocio
      message_id: { $ifNull: ["$metadata.wa_message_id", "UNKNOWN_ID"] },
      org_id: { $ifNull: ["$payload.context.org_id", "UNKNOWN_ORG"] },
      sender_phone: "$payload.from",
      receiver_phone: "$payload.to",
      message_type: "$payload.message.type",
      // Conservamos todo el bloque 'message' y 'metadata' como JSON stringificado para la columna JSONB
      raw_payload: {
        message: "$payload.message",
        metadata: "$metadata"
      },
      agent_assigned: { $ifNull: ["$payload.context.agent_assigned", "unassigned"] },
      tags: { $ifNull: ["$payload.context.tags", []] },
      received_at: "$timestamp"
    }
  }
];

// Ejecución del pipeline sobre la colección origen
db.whatsapp_events.aggregate(pipeline);
