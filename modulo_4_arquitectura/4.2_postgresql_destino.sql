-- DDL Destino en PostgreSQL (Estructura Relacional Híbrida)
CREATE TABLE whatsapp_messages (
    message_id TEXT PRIMARY KEY, -- Idempotencia garantizada a nivel de Engine
    org_id TEXT NOT NULL,
    sender_phone VARCHAR(20) NOT NULL,
    receiver_phone VARCHAR(20) NOT NULL,
    message_type VARCHAR(30) NOT NULL,
    agent_assigned TEXT,
    tags TEXT[], -- Aprovechamiento de tipos de datos nativos de Postgres
    received_at TIMESTAMPTZ NOT NULL,
    raw_payload JSONB NOT NULL, -- Almacenamiento defensivo para Schema Evolution
    loaded_at TIMESTAMPTZ DEFAULT now()
);

-- Índices de Cobertura Analítica
CREATE INDEX idx_wa_messages_org_date ON whatsapp_messages (org_id, received_at DESC);
CREATE INDEX idx_wa_messages_jsonb_gin ON whatsapp_messages USING gin (raw_payload);
