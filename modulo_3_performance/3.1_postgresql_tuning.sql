-- =============================================================================
-- PRUEBA TÉCNICA DBA - MÓDULO 3.1: PERFORMANCE TUNING EN POSTGRESQL
-- Optimización de Reporte de Facturación (Tabla base: 12M de filas)
-- Entorno: Producción
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T2: PROPUESTA DE ÍNDICES CON SINTAXIS EXACTA Y JUSTIFICACIÓN DE ORDEN
-- -----------------------------------------------------------------------------
/*
  CRITERIO DE SELECCIÓN Y ORDEN DE COLUMNAS (REGLA DE SELECTIVIDAD):
  1. idx_invoices_issued_perf: Compuesto. Primero colocamos la columna de estado (baja cardinalidad/filtro de igualdad)
     y luego el rango de fecha (alta cardinalidad/filtro de rango). Incluimos 'customer_id' y 'id' para permitir 
     un Index-Only Scan y evitar accesos costosos al Heap (tabla física).
  2. idx_customers_country_perf: Índice condicional (Partial Index) combinado con filtro de cobertura. 
     Solo indexa los países del reporte, reduciendo drásticamente el tamaño del índice en RAM.
  3. idx_invoice_lines_join_perf: Índice compuesto para cubrir el Join y la agregación matemática en un solo paso.
*/

-- 1. Optimización para la tabla central de Facturas (Invoices)
CREATE INDEX idx_invoices_issued_perf 
ON invoices (status, issued_at) 
INCLUDE (customer_id, id);

-- 2. Optimización parcial para la tabla de Clientes (Customers)
CREATE INDEX idx_customers_country_perf 
ON customers (country_code, name)
WHERE country_code IN ('CO','MX','AR','CL','PE');

-- 3. Optimización para la tabla de Líneas de Factura (Invoice Lines)
CREATE INDEX idx_invoice_lines_join_perf 
ON invoice_lines (invoice_id) 
INCLUDE (quantity, unit_price);

-- -----------------------------------------------------------------------------
-- T3: QUERY REESCRITA (Optimización mediante CTE y Agregación Previa)
-- -----------------------------------------------------------------------------
/*
  ESTRATEGIA DE MEJORA:
  En lugar de unir las 3 tablas (generando un producto cartesiano masivo de 12M antes de agrupar),
  filtramos y pre-agrupamos las facturas y líneas válidas primero. Reducimos el set de datos 
  a unos pocos miles de filas ANTES de hacer el JOIN final con la tabla de Clientes para obtener el nombre.
*/

WITH filtered_invoices AS (
    SELECT 
        i.customer_id,
        DATE_TRUNC('month', i.issued_at) AS month,
        i.id AS invoice_id
    FROM invoices i
    WHERE i.issued_at BETWEEN '2024-01-01' AND '2024-12-31'
      AND i.status != 'voided'
),
revenue_aggregated AS (
    SELECT 
        fi.customer_id,
        fi.month,
        SUM(il.quantity * il.unit_price) AS revenue,
        COUNT(DISTINCT fi.invoice_id) AS invoice_count
    FROM filtered_invoices fi
    JOIN invoice_lines il ON il.invoice_id = fi.invoice_id
    GROUP BY fi.customer_id, fi.month
)
SELECT 
    c.name AS customer,
    ra.month,
    ra.revenue,
    ra.invoice_count
FROM revenue_aggregated ra
JOIN customers c ON c.id = ra.customer_id
WHERE c.country_code IN ('CO','MX','AR','CL','PE')
ORDER BY revenue DESC
LIMIT 50;

-- -----------------------------------------------------------------------------
-- T4: ESTRATEGIA DE PARTICIONAMIENTO POR RANGO DE FECHAS (DDL)
-- -----------------------------------------------------------------------------
/*
  Para aplicar particionamiento en una relación Máster-Detalle existente en producción,
  la llave de partición (issued_at) DEBE formar parte de la llave primaria de ambas tablas.
*/

-- 1. Nueva Definición de la Tabla Invoices Particionada
CREATE TABLE invoices_part (
    id UUID,
    customer_id UUID,
    status TEXT,
    issued_at TIMESTAMPTZ,
    PRIMARY KEY (id, issued_at) -- Llave compuesta obligatoria para particionar
) PARTITION BY RANGE (issued_at);

-- Creación de Particiones Ejemplo (Mensuales o Trimestrales según tasa de ingesta)
CREATE TABLE invoices_y2024m01 PARTITION OF invoices_part
    FOR VALUES FROM ('2024-01-01 00:00:00+00') TO ('2024-02-01 00:00:00+00');
    
CREATE TABLE invoices_y2024m02 PARTITION OF invoices_part
    FOR VALUES FROM ('2024-02-01 00:00:00+00') TO ('2024-03-01 00:00:00+00');

-- 2. Nueva Definición de la Tabla Invoice Lines Particionada
CREATE TABLE invoice_lines_part (
    id UUID,
    invoice_id UUID,
    issued_at TIMESTAMPTZ, -- Heredada del padre para permitir el particionamiento alineado (Co-location)
    quantity INT,
    unit_price DECIMAL(12,2),
    PRIMARY KEY (id, issued_at)
) PARTITION BY RANGE (issued_at);

CREATE TABLE invoice_lines_y2024m01 PARTITION OF invoice_lines_part
    FOR VALUES FROM ('2024-01-01 00:00:00+00') TO ('2024-02-01 00:00:00+00');
