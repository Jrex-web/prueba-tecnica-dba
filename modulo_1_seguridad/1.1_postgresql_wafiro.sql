-- =============================================================================
-- PRUEBA TÉCNICA DBA - MÓDULO 1.1: POSTGRESQL ROLES Y ROW-LEVEL SECURITY
-- Empresa SaaS Wafiro (Multi-tenant)
-- Entorno: Producción
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T1: DISEÑO DE ROLES Y JERARQUÍA DE HERENCIA
-- -----------------------------------------------------------------------------
/*
  JUSTIFICACIÓN TÉCNICA DE HERENCIA (INHERIT / NOINHERIT):
  1. Se utiliza NOLOGIN para los roles de definición de privilegios (roles de grupo) 
     siguiendo el principio de mínimo privilegio.
  2. Se aplica INHERIT para mapear la jerarquía natural del negocio (un supervisor 
     debe heredar los permisos del agente).
  3. Los usuarios finales (roles personales con LOGIN) se asignarán a estos grupos.
  4. 'platform_admin' se define con NOINHERIT para evitar escalamiento de privilegios 
     accidental, obligando al uso explícito de SET ROLE si se requiere actuar con 
     permisos inferiores.
*/

-- Limpieza previa de entorno de pruebas (Opcional/Seguro)
DROP POLICY IF EXISTS tenant_isolation_policy ON conversations;
DROP POLICY IF EXISTS supervisor_visibility_policy ON conversations;
DROP TABLE IF EXISTS access_log;

-- Creación de Roles Base (Grupos de Privilegios)
CREATE ROLE platform_admin WITH NOLOGIN NOINHERIT;
CREATE ROLE org_admin      WITH NOLOGIN INHERIT;
CREATE ROLE supervisor     WITH NOLOGIN INHERIT;
CREATE ROLE agent          WITH NOLOGIN INHERIT;

-- Definición de la Jerarquía
GRANT agent TO supervisor;
GRANT supervisor TO org_admin;

-- Otorgar permisos básicos sobre el esquema público a la jerarquía
GRANT USAGE ON SCHEMA public TO agent;
GRANT SELECT, INSERT, UPDATE ON TABLE conversations TO agent;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE conversations TO supervisor;

-- -----------------------------------------------------------------------------
-- T2: IMPLEMENTACIÓN DE ROW-LEVEL SECURITY (RLS) MULTI-TENANT
-- -----------------------------------------------------------------------------

-- 1. Forzar RLS en la tabla crítica de negocio
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations FORCE ROW LEVEL SECURITY; -- Aplica incluso para el Owner de la tabla

-- 2. Política de Aislamiento Base por Organización (Tenant Isolation)
-- Utiliza el contexto seguro 'app.current_org_id' configurado por la app en la sesión.
CREATE POLICY tenant_isolation_policy ON conversations
    AS RESTRICTIVE -- Asegura que esta regla SE CUMPLE SÍ O SÍ (AND lógico con otras políticas)
    USING (org_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid);

-- -----------------------------------------------------------------------------
-- T3: POLÍTICA ACCESO POR NIVEL (SUPERVISOR VS AGENTE)
-- -----------------------------------------------------------------------------

-- Nota: Como la política anterior es RESTRICTIVE, esta puede ser PERMISSIVE (por defecto).
-- Ambas se combinarán con un operador 'AND'.

CREATE POLICY hierarchy_access_policy ON conversations
    FOR SELECT
    USING (
        -- Caso 1: El usuario es Administrador de la Organización o Administrador de Plataforma
        pg_has_role(current_user, 'org_admin', 'member') OR 
        pg_has_role(current_user, 'platform_admin', 'member') OR
        
        -- Caso 2: El usuario es Supervisor, puede ver todo lo de su org (ya filtrado por RLS restrictivo)
        pg_has_role(current_user, 'supervisor', 'member') OR
        
        -- Caso 3: El usuario es Agente, solo ve sus propias conversaciones
        (pg_has_role(current_user, 'agent', 'member') AND agent_id = (
            SELECT id FROM users WHERE email = current_user AND org_id = NULLIF(current_setting('app.current_org_id', true), '')::uuid
        ))
    );

-- -----------------------------------------------------------------------------
-- T4: SCRIPT DE AUDITORÍA (POLICY VIOLATION ATTEMPTS)
-- -----------------------------------------------------------------------------

-- 1. Creación de la tabla de logs de acceso maliciosos u erróneos
CREATE TABLE access_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attempted_at TIMESTAMPTZ DEFAULT now(),
    db_user TEXT NOT NULL DEFAULT current_user,
    session_org_id TEXT,
    target_conversation_id UUID,
    client_ip INET DEFAULT inet_client_addr(),
    application_name TEXT DEFAULT current_setting('application_name', true)
);

-- Indexar para análisis forense rápido
CREATE INDEX idx_access_log_date ON access_log (attempted_at DESC);

-- 2. Función contenedora de la lógica de auditoría preventiva
CREATE OR REPLACE FUNCTION verify_tenant_access() 
RETURNS TRIGGER AS $$
DECLARE
    v_current_org TEXT;
BEGIN
    v_current_org := current_setting('app.current_org_id', true);
    
    -- Si intentan consultar o modificar un registro que no pertenece al contexto de la sesión
    IF NEW.org_id::text <> v_current_org OR OLD.org_id::text <> v_current_org THEN
        INSERT INTO access_log (session_org_id, target_conversation_id)
        VALUES (v_current_org, COALESCE(NEW.id, OLD.id));
        
        RAISE EXCEPTION 'Security Violation: Access Denied for Tenant Context %', v_current_org
            USING ERRCODE = 'insufficient_privilege';
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER; 
-- SECURITY DEFINER asegura que se ejecute con los privilegios del creador para poder escribir en access_log

-- 3. Crear el Trigger disparador
CREATE TRIGGER trg_audit_policy_violation
    BEFORE UPDATE OR DELETE ON conversations
    FOR EACH ROW
    EXECUTE FUNCTION verify_tenant_access();

-- Comentario de fin de script
COMMENT ON POLICY tenant_isolation_policy ON conversations IS 'Garantiza el aislamiento estricto de datos por Tenant en Wafiro';
