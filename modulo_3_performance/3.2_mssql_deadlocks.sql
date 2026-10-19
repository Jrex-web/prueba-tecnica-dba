-- =============================================================================
-- PRUEBA TÉCNICA DBA - MÓDULO 3.2: BLOQUEOS Y DEADLOCKS EN OPERACIONES CONCURRENTES
-- Motor: SQL Server (MSSQL)
-- Entorno: Producción
-- =============================================================================

USE HR_Production; -- O base de datos transaccional de inventario
GO

-- -----------------------------------------------------------------------------
-- T2: SOLUCIÓN DE ORDENAMIENTO DE ACCESO A RECURSOS (REESCRITURA DE PROCEDIMIENTOS)
-- -----------------------------------------------------------------------------
/*
  ANÁLISIS DEL PROBLEMA:
  - Stored Proc A: Modifica 'inventory' -> Modifica 'purchase_orders'
  - Stored Proc B: Modifica 'purchase_orders' -> Modifica 'inventory'
  
  SOLUCIÓN ARQUITECTÓNICA:
  Establecer un orden estricto y unificado de acceso a los recursos para romper 
  la condición de espera circular (Condición de Coffman). Ambos procedimientos 
  DEBEN alterar primero 'inventory' y posteriormente 'purchase_orders'.
*/

-- 1. Reescribir Procedimiento A (Actualización de Stock)
CREATE OR ALTER PROCEDURE dbo.sp_UpdateInventoryAndOrder_ProcA
    @ItemId INT,
    @Qty INT,
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    BEGIN TRY
        -- Paso 1: Alterar Inventory primero
        UPDATE dbo.inventory
        SET stock = stock - @Qty
        WHERE item_id = @ItemId;

        -- Paso 2: Alterar Purchase Orders segundo
        UPDATE dbo.purchase_orders
        SET status = 'Processing'
        WHERE order_id = @OrderId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO

-- 2. Reescribir Procedimiento B (Generación de Órdenes de Compra)
CREATE OR ALTER PROCEDURE dbo.sp_ProcessPurchaseOrder_ProcB
    @ItemId INT,
    @Qty INT,
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRANSACTION;
    BEGIN TRY
        -- CORRECCIÓN: Se fuerza a alterar primero 'inventory' rompiendo el cruce
        UPDATE dbo.inventory
        SET reserved_stock = reserved_stock + @Qty
        WHERE item_id = @ItemId;

        -- Paso 2: Alterar Purchase Orders segundo
        UPDATE dbo.purchase_orders
        SET total_amount = total_amount + 100
        WHERE order_id = @OrderId;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
