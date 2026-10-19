#!/bin/bash
# =============================================================================
# PRUEBA TÉCNICA DBA - MÓDULO 5.1: POINT-IN-TIME RECOVERY (PITR) EN POSTGRESQL
# Incidente: Inyección destructiva DELETE a las 14:00:00
# Objetivo: Restaurar al estado de las 13:59:59
# Entorno: Producción
# =============================================================================

# Salir inmediatamente si ocurre un error en el script operativo
set -e

echo "⚠️ INICIANDO PROCEDIMIENTO DE CONTENCIÓN Y RECUPERACIÓN CRÍTICA..."

# -----------------------------------------------------------------------------
# T1: PROCEDIMIENTO CRONOLÓGICO PASO A PASO (ORQUESTACIÓN DE INFRAESTRUCTURA)
# -----------------------------------------------------------------------------

# Paso 1: Forzar el guardado del WAL actual en la instancia primaria de producción
# Esto asegura que los registros previos al delete a las 14:00 estén archivados en disco.
psql -c "SELECT pg_switch_wal();"

# Paso 2: Detener el servicio del motor de base de datos para evitar escrituras concurrentes
sudo systemctl stop postgresql

# Paso 3: Resguardar el directorio de datos corrupto actual (Metadatos y logs de transacciones actuales)
# Mantenemos los WALs actuales (pg_wal) por seguridad analítica forense.
mv /var/lib/postgresql/data /var/lib/postgresql/data_corrupt_backup

# Paso 4: Restaurar el Backup Base (Físico) de las 02:00 AM
# Reemplaza el directorio de datos con los archivos planos del base backup original.
tar -xzvf /mnt/backups/base_backup_20261019_0200.tar.gz -C /var/lib/postgresql/

# Paso 5: Limpiar el directorio 'pg_wal' restaurado del base backup antiguo
# Y mover los WALs recientes de la carpeta corrupta para que el motor aplique el Redo completo.
rm -rf /var/lib/postgresql/data/pg_wal/*
cp /var/lib/postgresql/data_corrupt_backup/pg_wal/* /var/lib/postgresql/data/pg_wal/

# -----------------------------------------------------------------------------
# CONFIGURACIÓN ESPECÍFICA DE RECUPERACIÓN (PostgreSQL 12+)
# -----------------------------------------------------------------------------
/*
  En versiones modernas de PostgreSQL, los parámetros de recovery ya no van en un 
  archivo 'recovery.conf' independiente. Se configuran dentro de 'postgresql.conf' 
  o 'postgresql.auto.conf', y se gatillan creando el archivo marcador 'recovery.signal'.
*/

cat << EOF >> /var/lib/postgresql/data/postgresql.conf
# Parámetros de Recuperación PITR para Wafiro
restore_command = 'cp /mnt/wal_archive/%f %p' # Comando para traer archivos del repositorio WAL
recovery_target_time = '2026-10-19 13:59:59-05' # Un segundo antes del desastre
recovery_target_action = 'promote' # Dejar la base de datos abierta para lectura/escritura al terminar
EOF

# Crear el archivo señalizador para indicarle al motor que inicie en modo recovery
touch /var/lib/postgresql/data/recovery.signal

# Paso 6: Iniciar el servicio para procesar el Roll-Forward de transacciones
sudo systemctl start postgresql

echo "✅ PITR COMPLETADO CON ÉXITO. REVISAR LOGS DE POSTGRESQL PARA VALIDAR LA PROMOCIÓN."
