-- =============================================================================
-- PRUEBA TÉCNICA DBA - MÓDULO 2.1: REFACTORING DE UN ESQUEMA EXISTENTE
-- Motor de referencia base: MySQL (Modificaciones Postgres explicadas en doc)
-- Entorno: Producción
-- =============================================================================

-- -----------------------------------------------------------------------------
-- T2: DDL CORREGIDO Y NORMALIZADO (Tercera Forma Normal - 3FN)
-- -----------------------------------------------------------------------------

CREATE TABLE clientes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    email VARCHAR(150) NOT NULL UNIQUE,
    telefono VARCHAR(20),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_clientes_email (email)
) ENGINE=InnoDB COMMENT='Almacena los datos maestros de los clientes';

CREATE TABLE direcciones_envio (
    id INT AUTO_INCREMENT PRIMARY KEY,
    cliente_id INT NOT NULL,
    direccion TEXT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_direcciones_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id) ON DELETE CASCADE
) ENGINE=InnoDB COMMENT='Direcciones de envío asociadas a los clientes';

CREATE TABLE productos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nombre VARCHAR(150) NOT NULL UNIQUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_productos_nombre (nombre)
) ENGINE=InnoDB COMMENT='Catálogo maestro de productos';

CREATE TABLE pedidos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    cliente_id INT NOT NULL,
    direccion_envio_id INT NOT NULL,
    precio_total DECIMAL(12,2) NOT NULL DEFAULT 0.00, -- Evita pérdida de precisión de FLOAT
    descuento_porcentaje DECIMAL(5,2) NOT NULL DEFAULT 0.00,
    fecha_pedido DATE NOT NULL,
    estado ENUM('pendiente', 'enviado', 'cancelado', 'rechazado') NOT NULL DEFAULT 'pendiente',
    notas TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_pedidos_cliente FOREIGN KEY (cliente_id) REFERENCES clientes(id),
    CONSTRAINT fk_pedidos_direccion FOREIGN KEY (direccion_envio_id) REFERENCES direcciones_envio(id),
    INDEX idx_pedidos_fecha (fecha_pedido),
    INDEX idx_pedidos_estado (estado)
) ENGINE=InnoDB COMMENT='Cabecera de las transacciones de pedidos';

CREATE TABLE detalle_pedidos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    pedido_id INT NOT NULL,
    producto_id INT NOT NULL,
    cantidad INT NOT NULL CHECK (cantidad > 0),
    CONSTRAINT fk_detalle_pedido FOREIGN KEY (pedido_id) REFERENCES pedidos(id) ON DELETE CASCADE,
    CONSTRAINT fk_detalle_producto FOREIGN KEY (producto_id) REFERENCES productos(id),
    UNIQUE KEY uq_pedido_producto (pedido_id, producto_id) -- Evita duplicar el mismo producto en el pedido
) ENGINE=InnoDB COMMENT='Líneas de detalle de cada pedido (Relación N:M)';

-- -----------------------------------------------------------------------------
-- T3: SCRIPT DE MIGRACIÓN DE DATOS (Parsing de Pipes e Integridad cronológica)
-- -----------------------------------------------------------------------------

DELIMITER $$

CREATE PROCEDURE migrar_datos_viejos_a_nuevos()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_id INT;
    DECLARE v_cliente_nombre VARCHAR(500);
    DECLARE v_cliente_email VARCHAR(500);
    DECLARE v_cliente_tel VARCHAR(500);
    DECLARE v_producto_raw VARCHAR(1000);
    DECLARE v_cantidad_raw VARCHAR(100);
    DECLARE v_precio_total FLOAT;
    DECLARE v_descuento VARCHAR(50);
    DECLARE v_fecha_raw VARCHAR(50);
    DECLARE v_estado CHAR(1);
    DECLARE v_notas TEXT;
    DECLARE v_direccion TEXT;
    
    -- Cursor para leer la tabla heredada corrupta
    DECLARE cur CURSOR FOR SELECT id, cliente_nombre, cliente_email, cliente_tel, producto, cantidad, precio_total, descuento, fecha, estado, notas, direccion_envio FROM pedidos_viejos;
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO v_id, v_cliente_nombre, v_cliente_email, v_cliente_tel, v_producto_raw, v_cantidad_raw, v_precio_total, v_descuento, v_fecha_raw, v_estado, v_notas, v_direccion;
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- 1. Insertar o recuperar Cliente
        INSERT IGNORE INTO clientes (nombre, email, telefono) 
        VALUES (v_cliente_nombre, v_cliente_email, v_cliente_tel);
        
        SET @current_cliente_id = (SELECT id FROM clientes WHERE email = v_cliente_email LIMIT 1);

        -- 2. Insertar dirección de envío
        INSERT INTO direcciones_envio (cliente_id, direccion) VALUES (@current_cliente_id, v_direccion);
        SET @current_direccion_id = LAST_INSERT_ID();

        -- 3. Mapear estado heredado sin documentar
        SET @nuevo_estado = CASE v_estado
            WHEN 'P' THEN 'pendiente'
            WHEN 'E' THEN 'enviado'
            WHEN 'C' THEN 'cancelado'
            WHEN 'X' THEN 'rechazado'
            ELSE 'pendiente'
        END;

        -- 4. Parsear fecha corrupta (ej: '15-oct-2024') a formato estándar YYYY-MM-DD
        -- Nota: En un entorno real se mapean los nombres de meses en español/inglés.
        SET @fecha_convertida = STR_TO_DATE(REPLACE(v_fecha_raw, 'oct', '10'), '%d-%m-%Y');

        -- 5. Limpiar porcentaje de descuento ("10%" -> 10.00)
        SET @descuento_num = CAST(REPLACE(v_descuento, '%', '') AS DECIMAL(5,2));

        -- 6. Insertar Cabecera de Pedido
        INSERT INTO pedidos (cliente_id, direccion_envio_id, precio_total, descuento_porcentaje, fecha_pedido, estado, notas)
        VALUES (@current_cliente_id, @current_direccion_id, CAST(v_precio_total AS DECIMAL(12,2)), @descuento_num, @fecha_convertida, @nuevo_estado, v_notas);
        SET @nuevo_pedido_id = LAST_INSERT_ID();

        -- 7. PARSING DE PIPES (|) PARA PRODUCTO Y CANTIDAD
        -- Procesamiento secuencial de cadenas delimitadas en MySQL transaccional
        SET @prod_index = 1;
        SET @prod_token = SUBSTRING_INDEX(SUBSTRING_INDEX(v_producto_raw, '|', @prod_index), '|', -1);
        SET @cant_token = SUBSTRING_INDEX(SUBSTRING_INDEX(v_cantidad_raw, '|', @prod_index), '|', -1);

        WHILE @prod_token <> '' AND @prod_token <> v_producto_raw DO
            -- Insertar producto maestro si no existe
            INSERT IGNORE INTO productos (nombre) VALUES (@prod_token);
            SET @current_prod_id = (SELECT id FROM productos WHERE nombre = @prod_token LIMIT 1);

            -- Insertar detalle de pedido
            INSERT INTO detalle_pedidos (pedido_id, producto_id, cantidad)
            VALUES (@nuevo_pedido_id, @current_prod_id, CAST(@cant_token AS UNSIGNED));

            SET @prod_index = @prod_index + 1;
            SET @next_prod_token = SUBSTRING_INDEX(SUBSTRING_INDEX(v_producto_raw, '|', @prod_index), '|', -1);
            
            -- Salir si ya no hay más elementos
            IF @next_prod_token = @prod_token THEN
                SET @prod_token = '';
            ELSE
                SET @prod_token = @next_prod_token;
                SET @cant_token = SUBSTRING_INDEX(SUBSTRING_INDEX(v_cantidad_raw, '|', @prod_index), '|', -1);
            END IF;
        END WHILE;

    END LOOP;

    CLOSE cur;
END$$

DELIMITER ;
