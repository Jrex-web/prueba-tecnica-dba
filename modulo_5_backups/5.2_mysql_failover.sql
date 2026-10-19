-- =============================================================================
-- PRUEBA TÉCNICA DBA - MÓDULO 5.2: MYSQL REPLICACIÓN Y FAILOVER MANUAL
-- Configuración: 1 Primary + 2 Replicas
-- Entorno: Producción
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T1: COMANDOS DE DIAGNÓSTICO (RETRASO DE REPLICACIÓN)
-- -----------------------------------------------------------------------------

-- 1. Inspección general del estado de la réplica
-- Monitorear críticamente: Seconds_Behind_Master, Replica_IO_Running, Replica_SQL_Running
SHOW REPLICA STATUS\G

-- 2. Identificar si el cuello de botella es el hilo SQL (Procesamiento monohilo)
-- Permite ver qué query exacta está bloqueando o ralentizando la réplica.
SELECT * FROM performance_schema.threads 
WHERE NAME = 'thread/sql/replica_sql';

-- 3. Verificar contención de bloqueos o transacciones largas en la réplica
SELECT * FROM information_schema.innodb_trx 
ORDER BY trx_started;

-- -----------------------------------------------------------------------------
-- T2: COMANDOS EXACTOS PARA FAILOVER MANUAL (PRODUCCIÓN)
-- -----------------------------------------------------------------------------

-- =============================================================================
-- PASO A: EN LA RÉPLICA ELEGIDA PARA SER PROMOVIDA (REPLICA 1)
-- =============================================================================

-- 1. Detener los hilos de replicación de forma controlada
STOP REPLICA;

-- 2. Asegurar que haya procesado todos los eventos pendientes del Relay Log (Sincronización)
-- Esto previene la pérdida de datos antes de cortar el cordón umbilical.
START REPLICA UNTIL RELAY_LOG_FILE = 'replica-relay-bin.000004', RELAY_LOG_POS = 154; 
-- (Los valores exactos se obtienen previamente con SHOW REPLICA STATUS)

-- 3. Romper la relación de subordinación y limpiar metadatos de replicación
RESET REPLICA ALL;

-- 4. Desactivar el modo de solo lectura para permitir que la aplicación escriba
SET GLOBAL read_only = OFF;
SET GLOBAL super_read_only = OFF;

-- =============================================================================
-- PASO B: EN LA OTRA RÉPLICA REESTANTE (REPLICA 2)
-- =============================================================================

-- 1. Detener la replicación que apuntaba al Primary antiguo (caído)
STOP REPLICA;

-- 2. Reconfigurar el puntero de replicación hacia el NUEVO Primary (Replica 1)
-- Se asume el uso de GTID (Global Transaction Identifiers), mandatorio en producción.
CHANGE REPLICATION SOURCE TO
    SOURCE_HOST = 'ip_nueva_replica_1_primary',
    SOURCE_USER = 'replica_user',
    SOURCE_PASSWORD = 'SecureReplicaPassword123!',
    SOURCE_PORT = 3306,
    SOURCE_AUTO_POSITION = 1; -- Sincronización automática basada en GTID

-- 3. Iniciar la replicación hacia el nuevo origen
START REPLICA;

-- 4. Verificar consistencia
SHOW REPLICA STATUS\G
