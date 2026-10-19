-- =============================================================================
-- PRUEBA TÉCNICA DBA - MÓDULO 1.2: MSSQL AUDITORÍA Y ENMASCARAMIENTO DE DATOS
-- Sistema de Recursos Humanos (Tabla: employees)
-- Entorno: Producción
-- =============================================================================

USE master;
GO

-- Crear la base de datos de pruebas si no existe para validar sintaxis
IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = 'HR_Production')
BEGIN
    CREATE DATABASE HR_Production;
END
GO

USE HR_Production;
GO

-- -----------------------------------------------------------------------------
-- CONFIGURACIÓN PREVIA: Creación de la Tabla de Referencia
-- -----------------------------------------------------------------------------
IF OBJECT_ID('dbo.employees', 'U') IS NOT NULL
    DROP TABLE dbo.employees;
GO

CREATE TABLE dbo.employees (
    id INT IDENTITY(1,1) PRIMARY KEY,
    first_name NVARCHAR(100) NOT NULL,
    last_name NVARCHAR(100) NOT NULL,
    national_id VARCHAR(20) NOT NULL, -- Datos Sensibles (PII)
    email NVARCHAR(256) NOT NULL,     -- Datos Sensibles (PII)
    salary DECIMAL(18,2) NOT NULL,    -- Datos Financieros Sensibles
    department NVARCHAR(100) NOT NULL
);
GO

-- Insertar datos de prueba corporativos
INSERT INTO dbo.employees (first_name, last_name, national_id, email, salary, department)
VALUES 
('John', 'Doe', '123456789-X', 'john.doe@company.com', 8500.00, 'Engineering'),
('Jane', 'Smith', '987654321-Y', 'jane.smith@company.com', 12500.00, 'Finance');
GO

-- -----------------------------------------------------------------------------
-- T1: IMPLEMENTACIÓN DE DYNAMIC DATA MASKING (DDM)
-- -----------------------------------------------------------------------------
/*
  Análisis de Funciones de Enmascaramiento Aplicadas:
  1. national_id: Se usa partial(0, x, 4) para exponer únicamente los últimos 4 dígitos.
  2. email: Se usa la función nativa email() que expone la primera letra, máscara constante y el dominio.
  3. salary: SQL Server DDM no permite enmascarar "por rangos" de forma nativa directa en la columna con DDM base.
     Para cumplir estrictamente en producción, se usa una función default (retorna 0) y se recomienda complementar 
     con una Vista de negocio si el equipo de Reporting exige ver rangos (ej. entre 5k y 10k).
*/

ALTER TABLE dbo.employees
ALTER COLUMN national_id ADD MASKED WITH (FUNCTION = 'partial(0, "XXXXXX-", 4)');
GO

ALTER TABLE dbo.employees
ALTER COLUMN email ADD MASKED WITH (FUNCTION = 'email()');
GO

ALTER TABLE dbo.employees
ALTER COLUMN salary ADD MASKED WITH (FUNCTION = 'default()'); 
GO

-- -----------------------------------------------------------------------------
-- T2: CREACIÓN DE USUARIOS Y ASIGNACIÓN DE PERMISOS (RBAC)
-- -----------------------------------------------------------------------------

-- Creación de Logins en el Servidor
IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'report_viewer_login')
    CREATE LOGIN report_viewer_login WITH PASSWORD = 'SecurePassword123!';
GO

IF NOT EXISTS (SELECT * FROM sys.server_principals WHERE name = 'hr_manager_login')
    CREATE LOGIN hr_manager_login WITH PASSWORD = 'SecurePassword456!';
GO

-- Creación de Usuarios en la Base de Datos
CREATE USER report_viewer FOR LOGIN report_viewer_login;
CREATE USER hr_manager FOR LOGIN hr_manager_login;
GO

-- Permisos para el visor de reportes (Solo lectura enmascarada)
GRANT SELECT ON dbo.employees TO report_viewer;
-- NOTA: Por defecto, NO tiene el permiso UNMASK, por lo que verá los datos protegidos.

-- Permisos para el Gerente de HR (Acceso total deslocalizado)
GRANT SELECT, INSERT, UPDATE, DELETE ON dbo.employees TO hr_manager;
GRANT UNMASK TO hr_manager; -- Permiso crítico para ver datos reales sin máscara
GO

-- -----------------------------------------------------------------------------
-- T3: CONFIGURACIÓN DE SQL SERVER AUDIT (A NIVEL SERVIDOR Y BASE DE DATOS)
-- -----------------------------------------------------------------------------
USE master;
GO

-- 1. Crear la Auditoría del Servidor con destino a Archivo (.sqlaudit)
-- Se define el límite de tamaño de archivo y retención según estándares PCI-DSS/GDPR.
IF EXISTS (SELECT * FROM sys.server_audits WHERE name = 'HR_Select_Audit')
BEGIN
    ALTER SERVER AUDIT [HR_Select_Audit] WITH (STATE = OFF);
    DROP SERVER AUDIT [HR_Select_Audit];
END
GO

CREATE SERVER AUDIT [HR_Select_Audit]
TO FILE 
(   FILEPATH = 'C:\SQLAudit\' -- Asegurar que esta ruta exista en el servidor de destino
    ,MAXSIZE = 50 MB
    ,MAX_ROLLOVER_FILES = 10
    ,RESERVE_DISK_SPACE = OFF
)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE);
GO

-- Activar la auditoría a nivel servidor
ALTER SERVER AUDIT [HR_Select_Audit] WITH (STATE = ON);
GO

-- 2. Crear la Especificación de Auditoría de Base de Datos
USE HR_Production;
GO

IF EXISTS (SELECT * FROM sys.database_audit_specifications WHERE name = 'HR_Employees_Select_Spec')
BEGIN
    ALTER DATABASE AUDIT SPECIFICATION [HR_Employees_Spec] WITH (STATE = OFF);
    DROP DATABASE AUDIT SPECIFICATION [HR_Employees_Spec];
END
GO

CREATE DATABASE AUDIT SPECIFICATION [HR_Employees_Select_Spec]
FOR SERVER AUDIT [HR_Select_Audit]
ADD (SELECT ON dbo.employees BY report_viewer) -- Captura las lecturas del usuario de reporting (no-HR)
WITH (STATE = ON);
GO

-- -----------------------------------------------------------------------------
-- CONTROL DE VERIFICACIÓN (Para pruebas internas en VS Code)
-- -----------------------------------------------------------------------------
/*
-- Probar como report_viewer (Verá datos enmascarados)
EXECUTE AS USER = 'report_viewer';
SELECT * FROM dbo.employees;
REVERT;

-- Probar como hr_manager (Verá datos reales)
EXECUTE AS USER = 'hr_manager';
SELECT * FROM dbo.employees;
REVERT;
*/
