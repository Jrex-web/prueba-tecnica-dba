# 📄 Entrega de Prueba Técnica: DBA Senior
**Fecha de entrega:** Lunes 19 de octubre, 5:00 PM  
**Candidato:** JOSE GUTIERREZ RAMIREZ  
**Entorno de Aplicación:** Producción  

---

## 🛠️ Módulo 1 - Seguridad, Usuarios y Políticas de Acceso

### 🐘 1.1 PostgreSQL - Diseño de Roles y Row-Level Security (Wafiro)
*   **Justificación de Jerarquía de Roles (T1):** Se utilizó un esquema mixto. Los roles de negocio (`agent`, `supervisor`, `org_admin`) se configuraron con `INHERIT` para permitir la reutilización de privilegios (el supervisor hereda del agente de forma limpia). Sin embargo, el rol `platform_admin` se definió con `NOINHERIT` para mitigar riesgos de seguridad en producción; esto obliga al superusuario a invocar explícitamente `SET ROLE` para ejecutar comandos destructivos o de auditoría.
*   **Implementación de RLS (T2 y T3):** Se optó por una política parametrizada de tipo `RESTRICTIVE` para la separación multi-tenant. Al usar `AS RESTRICTIVE`, PostgreSQL evalúa esta regla de manera obligatoria con un operador `AND` sobre cualquier otra regla flexible (`PERMISSIVE`). Esto blindará la base de datos contra fallos lógicos en las queries del backend.
*   **Estrategia de Auditoría (T4):** Dado que las sentencias `SELECT` que violan las políticas RLS son filtradas silenciosamente por el motor (no arrojan error, solo devuelven 0 filas), se implementó un trigger `BEFORE UPDATE OR DELETE` con propiedad `SECURITY DEFINER`. Esto permite interceptar intentos de alteración cross-tenant maliciosos, registrar la IP del cliente y bloquear la transacción con un código de error nativo `42501` (insufficient_privilege).

### 🏢 1.2 MSSQL - Auditoría y Enmascaramiento de Datos Sensibles
*   **Dynamic Data Masking (T1):** Se aplicaron funciones nativas de SQL Server para mitigar la exposición de PII. Para `national_id` se utilizó la función `partial()` conservando solo los últimos 4 caracteres. Para el correo electrónico, la función estándar `email()` automatiza el formateo. Respecto a `salary`, debido a que DDM nativo no genera rangos aleatorios dinámicos directo en la columna (solo valores por defecto como `0.00`), se utilizó la función `default()`. Para cumplir el requerimiento analítico de rangos sin comprometer la seguridad en producción, el estándar arquitectónico dicta exponer este dato mediante una **Vista Calculada** acotada utilizando sentencias `CASE WHEN`.
*   **Control de Accesos (T2):** Se aplicó control de acceso basado en roles (RBAC). El usuario `report_viewer` únicamente ostenta el privilegio `GRANT SELECT`, lo que restringe por defecto la lectura de datos planos. Al usuario `hr_manager` se le concedió explícitamente el permiso corporativo `UNMASK` junto con los privilegios DML completos.
*   **Configuración de SQL Server Audit (T3):** Se configuró una auditoría nativa dividida en dos capas (`SERVER AUDIT` y `DATABASE AUDIT SPECIFICATION`) dirigida a un archivo binario `.sqlaudit` protegido en disco. La especificación se acotó estrictamente para auditar los eventos de tipo `SELECT` realizados por usuarios fuera del departamento de recursos humanos (`report_viewer`), optimizando el rendimiento de I/O de la instancia y evitando el crecimiento innecesario de los logs de auditoría por operaciones internas de HR.

### 🍃 1.3 MongoDB - Autenticación, RBAC y Cifrado
*   **Roles Personalizados (T1):** Se implementaron tres roles con el principio de privilegio mínimo usando granularidad a nivel de colección. `eventWriter` limita estrictamente la acción a la mutación `insert`, protegiendo la fuga de datos de telemetría. `analyticsReader` limita los permisos a la acción `find` necesaria para los motores de BI. `dataEngineer` unifica el ciclo DML y otorga la capacidad operativa de optimización mediante `createIndex` y `dropIndex` dentro del espacio de nombres `analytics.*`.
*   **Cifrado CSFLE (T2):** Para mitigar la exposición de datos sensibles antes de tocar la capa de almacenamiento (cero confianza en el proveedor de infraestructura), se definió un JSON Schema de cifrado en el lado del cliente (CSFLE). El campo `user_ip` se configuró de manera **Determinista** (`AEAD_AES_256_CBC_HMAC_SHA_512-Deterministic`) para permitir búsquedas exactas e indexadas en la base de datos sin descifrar el documento. El campo `user_agent` se configuró de manera **Aleatoria** (`AEAD_AES_256_CBC_HMAC_SHA_512-Random`) para asegurar la máxima protección criptográfica contra ataques basados en análisis de patrones de texto idénticos.
*   **Auditoría (T3):** Se definió un filtro de auditoría nativo JSON (`{ "atype": "authCheck", "result": { "$ne": 0 } }`). Este enfoque selectivo optimiza críticamente el rendimiento de I/O en producción al descartar las millones de operaciones exitosas por segundo y capturar con precisión quirúrgica únicamente los accesos bloqueados por falta de privilegios o violaciones de seguridad.

---

## 📐 Módulo 2 - Modelado y Buenas Prácticas de Esquema

### 🐬 Refactoring de Esquema E-commerce (2.1)
#### T1: Matriz de Problemas de Diseño Identificados
*(Ya incluida en la plantilla base, lista para revisión del evaluador).*

*   **Estrategia de Migración (T3):** La migración se diseñó mediante un procedimiento almacenado transaccional que procesa la fuente fila por fila. Para solucionar la violación de la 1NF (campos con pipes `|`), se usó lógica iterativa basada en `SUBSTRING_INDEX` para extraer los tokens en paralelo de `producto` y `cantidad`, poblando dinámicamente las tablas normalizadas `productos` y `detalle_pedidos` garantizando atomicidad mediante llaves foráneas. La inconsistencia cronológica se resolvió usando `STR_TO_DATE()` reemplazando previamente las cadenas de texto del mes por su equivalente numérico.

*   **Diferencias de Portabilidad si se migrara a PostgreSQL (T4):**
    1.  **Tipos de Datos:** En lugar de `ENUM` rígidos de MySQL, en PostgreSQL se preferiría usar tipos `text` con un `CHECK CONSTRAINT` o un tipo `CREATE TYPE estado_pedido AS ENUM (...)` personalizado.
    2.  **Manejo de Cadenas Multi-valuadas:** PostgreSQL simplifica drásticamente el parsing de datos con pipes. Se evitarían los bucles complejos de MySQL usando la función nativa `string_to_array(producto, '|')` combinada con `unnest()`, permitiendo hacer la migración en un solo query declarativo sin necesidad de cursores.
    3.  **Tipos Monetarios y de Tiempo:** Se utilizaría `NUMERIC` en lugar de `DECIMAL` y tipos avanzados `TIMESTAMPTZ` para asegurar el almacenamiento correcto de zonas horarias en producción global.
    4.  **Extensiones:** Posibilidad de habilitar `pg_trgm` para búsquedas eficientes de texto en los nombres de productos.

### 🍃 MongoDB - Modelado de Catálogo Polimórfico (2.2)
*   **Patrón de Atributos Polimórficos (T1):** Se implementó la estructura de par clave-valor (`{"k": "atributo", "v": "valor"}`) dentro de un arreglo. Este patrón permite indexar de forma homogénea múltiples variables de negocio radicalmente distintas (voltaje, talla, fecha de vencimiento) bajo un único índice compuesto en producción, evitando la dispersión de campos y la creación descontrolada de índices individuales.
*   **Justificación de Decisiones de Almacenamiento (Embedding vs Referencing):**
    *   *Categorías (Referencing):* Se utiliza referencia externa (`category_id`) ya que las categorías son entidades maestras independientes con baja tasa de mutación y alta reutilización entre millones de documentos.
    *   *Variantes (Embedding):* Se incrustan en el documento padre porque su ciclo de vida es completamente dependiente de este (atómicas) y su volumen es acotado, garantizando lecturas en una sola operación de I/O sin penalización.
    *   *Reseñas (Referencing):* Se opta por referencia externa radical en otra colección debido al crecimiento ilimitado (Unbounded Growth). Incrustarlas violaría eventualmente el límite físico de 16MB por documento de MongoDB e impactaría severamente la paginación en memoria RAM. Se conserva un sumario embebido (`recent_rating_summary`) para consultas rápidas.
*   **Estrategia de Índices y Estimación de Tamaño (T2):** Se creó un índice compuesto de precisión (`category_id_1_attributes.k_1_attributes.v_1_price_1`) alineado al principio de ordenamiento de llaves (*Equality, Sort, Range*). La estimación de tamaño de RAM requerida para sus 2M de registros se calculó en **~156 MB**, un tamaño altamente óptimo que mitiga fallos de desborde a disco (Page Faults).

---

## ⚡ Módulo 3 - Performance Tuning y Diagnóstico

### 🐘 3.1 PostgreSQL - Query Lenta en Reporte de Facturación
*   **Causas de la Lentitud (T1):**
    1.  **Seq Scans Masivos:** El motor ejecuta escaneos secuenciales completos en `invoice_lines` (12.4M de filas) e `invoices` (3.2M de filas) debido a la ausencia de índices que cubran los predicados de búsqueda.
    2.  **Hash Joins Costosos:** Al no haber índices en las llaves foráneas (`invoice_id`, `customer_id`), PostgreSQL se ve obligado a cargar millones de filas en memoria RAM de trabajo (`work_mem`) para construir tablas hash temporales.
    3.  **Filtro Ineficiente en la Selección:** El filtro de exclusión (`status != 'voided'`) invalida el uso eficiente de índices B-tree estándar si no están optimizados de forma compuesta.
    4.  **Desborde de Agregación Volumétrica:** El agrupamiento de texto largo (`c.name`) fuerza una ordenación en disco pesada debido a la masiva cantidad de datos mezclados antes del filtrado real.

*   **Justificación de Índices Compuestos (T2):** *(Explicada detalladamente en los comentarios del script SQL generado).*

*   **Uso de Índice BRIN en vez de B-Tree para `issued_at` (T5):** Se justificaría el uso de un índice **BRIN** (Block Range Index) si la tabla crece continuamente y los datos se insertan de manera estrictamente cronológica y secuencial (orden natural físico en disco concordante con el tiempo). Mientras un índice B-Tree para 12M de filas puede pesar gigabytes en RAM, un índice BRIN ocuparía apenas unos pocos kilobytes al almacenar únicamente los valores mínimos y máximos por bloque de disco, liberando memoria caché crítica para el servidor en producción.

### 🏢 3.2 MSSQL - Bloqueos y Deadlocks en Operaciones Concurrentes

*   **T1: Técnica para capturar y analizar Deadlock Graphs con Extended Events:**
    En entornos modernos de producción de SQL Server, se descartan las trazas clásicas de SQL Profiler y las flags de diagnóstico (`DBCC TRACEON(1222, -1)`) por su alto impacto en I/O. La técnica estándar es implementar una sesión nativa de **Extended Events (XEvents)** utilizando el evento `xml_deadlock_report`.
    1. Se crea la sesión capturando el evento hacia un destino de archivo de anillo (`ring_buffer`) o de disco (`event_file`).
    2. Al dispararse el interbloqueo, el motor genera un grafo XML estructurado.
    3. Al abrir este archivo `.xel` desde VS Code o SSMS, el grafo se renderiza visualmente como un diagrama de nodos, donde se identifican con precisión quirúrgica el *Deadlock Victim*, los identificadores de los hilos transaccionales involucrados, el tipo de bloqueo solicitado (`X` u `IX`) y las páginas físicas de memoria en disputa.

*   **T2: Resolución por Ordenamiento de Acceso:** *(Código de reestructuración secuencial documentado en el script SQL provisto).*

*   **T3: Nivel de Aislamiento Adecuado y Trade-off (Justificación):**
    Para un sistema de inventario y órdenes de compra de alta concurrencia, el nivel de aislamiento recomendado es **READ COMMITTED SNAPSHOT ISOLATION (RCSI)**.
    *   **Justificación:** RCSI implementa un versionamiento de filas en la base de datos `tempdb`. Bajo este esquema, los lectores (consultas de reportes o lecturas de stock) no bloquean a los escritores, y los escritores no bloquean a los lectores. 
    *   **Trade-off:** El beneficio directo es la eliminación drástica de bloqueos de lectura (`Shared Locks`) y un incremento masivo en el rendimiento transaccional. El costo operativo asociado es la sobrecarga de I/O y CPU en `tempdb` debido a la gestión del almacén de versiones (*Version Store*), y un consumo adicional de 14 bytes por registro para los punteros de control. 
    *   *Nota de seguridad:* Se descarta `SERIALIZABLE` por congelar el rendimiento general en alta concurrencia, y se prefiere RCSI sobre `SNAPSHOT` tradicional porque no requiere modificar el código de la aplicación cliente mediante *hints* explícitos.


---

## 🏗️ Módulo 4 - Arquitectura de Datos y Data Lake

### 🔄 4.1 Multi-Engine - Diseño de Data Lake Corporativo

*   **T3: Estrategia de CDC (Change Data Capture) y Schema Evolution:**
    1.  **PostgreSQL (Wafiro):** Se implementa **Debezium** acoplado al plugin nativo de decodificación lógica `pgoutput` mediante publicaciones. Esto lee el archivo WAL (Write-Ahead Log) sin penalizar el rendimiento de la base de datos de producción.
    2.  **MSSQL (VML.Sentry):** Se habilita la característica nativa **CDC (Change Data Capture)** a nivel de base de datos y tablas, la cual lee de forma asíncrona el log de transacciones mediante el SQL Server Agent.
    3.  **Manejo de Deletes:** Ambas herramientas CDC emiten payloads con tres estados (`before`, `after`, y `op`). Las operaciones de borrado físico (`op: d`) se interceptan en la capa de procesamiento y se transforman en *Soft Deletes* (columna `is_deleted = true`) en la capa *Cleansed* para no perder el registro histórico analítico.
    4.  **Schema Evolution:** Se despliega un componente centralizado **Confluent Schema Registry**. Si el backend transaccional añade una columna, el pipeline la detecta, valida compatibilidad hacia adelante (*Forward Compatibility*) y actualiza de forma automática el esquema de destino en Delta Lake sin interrumpir la ingesta.

*   **T4: Políticas de Retención, Lifecycle y Gobernanza PII:**
    1.  **Políticas de Retención (Lifecycle):** Los datos en la zona *Raw* se configuran con un ciclo de vida estricto de **90 días** para recuperación ante desastres y auditoría profunda, migrándose luego a un almacenamiento frío (Cold Storage / Glacier) por motivos de costos. La zona *Curated/Serving* se mantiene de forma indefinida en caliente para series de tiempo e históricos de BI.
    2.  **Gobernanza de Datos PII:** Siguiendo regulaciones internacionales (GDPR/Compliance local), los datos altamente confidenciales (como correos o teléfonos de usuarios) se someten a técnicas de **Hash Criptográfico SHA-256 salteado** o anonimización total irreversible en el paso de la zona *Raw* a la zona *Cleansed*, garantizando que ningún analista o científico de datos consuma datos sensibles descubiertos en producción. El acceso general a las tablas analíticas finales se restringe mediante políticas RBAC por grupos de Active Directory/IAM.


### 🔄 4.2 Pipeline ETL - Datos Heterogéneos (MongoDB ➡️ PostgreSQL)

*   **Criterio de Normalización vs JSONB (T1):** Se diseñó un modelo híbrido en PostgreSQL. Se normalizaron como columnas relacionales indexadas los datos operacionales de alta cardinalidad utilizados para consultas frecuentes y métricas de negocio (`message_id`, `org_id`, `sender_phone`, `received_at`). Por el contrario, los metadatos variables de WhatsApp y el cuerpo del mensaje se preservaron íntegros en una columna tipo **JSONB**. Esto optimiza el espacio en disco, evita migraciones complejas ante cambios de la API de WhatsApp, y permite búsquedas ágiles en producción mediante índices especializados **GIN**.

*   **Garantía de Idempotencia (T3):** Para evitar la duplicidad de registros en ejecuciones encoladas o reintento de fallas (*At-least-once delivery*), la capa de persistencia final implementa la estrategia de **Upsert nativo** en PostgreSQL apoyado en la Llave Primaria lógica (`message_id` derivado de `wa_message_id`):
    ```sql
    INSERT INTO whatsapp_messages (...) 
    VALUES (...) 
    ON CONFLICT (message_id) 
    DO UPDATE SET 
        agent_assigned = EXCLUDED.agent_assigned,
        tags = EXCLUDED.tags,
        raw_payload = whatsapp_messages.raw_payload || EXCLUDED.raw_payload; -- Merge de JSONB
    ```

*   **Schema Evolution Defensivo (T4):** Ante cambios intempestivos en el payload de WhatsApp API (ej. nuevos campos de reacciones o interactivos), se aplica el **Patrón de Captura Aislada**. Al mapear todo el nodo mutable en la columna `JSONB (raw_payload)`, el pipeline nunca se romperá por columnas faltantes o inesperadas en el esquema estricto de PostgreSQL. El negocio podrá consumir de inmediato los nuevos parámetros en tiempo real usando operadores de extracción nativos como `raw_payload->'message'->>'new_field'` sin requerir mantenimiento de infraestructura de datos.

---

## 💾 Módulo 5 - Backup, Recuperación y Alta Disponibilidad

### 🐘 5.1 PostgreSQL - Point-in-Time Recovery (PITR)
*   **Procedimiento Cronológico (T1):** *(Procedimiento técnico automatizado detallado en el script bash adjunto en la solución).*
*   **Recuperación Quirúrgica (T2):** Para un entorno de alta transaccionalidad, revertir toda la base de datos de producción a un estado del pasado provocaría una pérdida masiva de datos legítimos en otras tablas del sistema. Por ello, la estrategia senior adoptada consiste en levantar una **Instancia Auxiliar / Clon temporal**. Sobre este clon se ejecuta el proceso PITR completo hasta el segundo `13:59:59`. Una vez estabilizada, se realiza una extracción lógica mediante `pg_dump` acotada exclusivamente a la tabla `orders`. Finalmente, se cargan únicamente los registros huérfanos en la base de datos productiva real con `pg_restore --data-only`, mitigando el impacto en el negocio.
*   **Mecanismos de Prevención Antierrores (T3):** 
    1. **Parámetro Defensivo:** Modificar el comportamiento de la sesión forzando el parámetro `SET sql_safe_updates = on;` o mapeando un alias de consola que ejecute PostgreSQL con restricciones de seguridad frente a mutaciones masivas sin cláusula limitante.
    2. **Capa Transaccional por Triggers:** Implementar un trigger de contingencia a nivel de tabla `BEFORE DELETE` que compare el volumen de filas a alterar; si el delta de eliminación supera un umbral crítico (ej. > 5,000 registros de golpe), la transacción aborta automáticamente, requiriendo un bypass manual del DBA.
    3. **Roles Segregados:** Retirar el permiso directo de `DELETE` sobre tablas maestras al rol del pool de conexiones de la aplicación y canalizar las bajas a través de Stored Procedures auditados mediante `pgaudit`.

### 🐬 5.2 MySQL - Replicación y Failover

*   **Causas más comunes de retraso de replicación y diagnóstico (T1):**
    1.  **Saturación del Hilo SQL (Single-Thread Bottleneck):** Tradicionalmente, el procesamiento en las réplicas es monohilo. Si el Primary procesa escrituras concurrentes masivas, la réplica puede encolarse. *Diagnóstico:* Ejecutar `SHOW REPLICA STATUS` y comprobar si `Seconds_Behind_Master` crece continuamente mientras los hilos de I/O y SQL están en `Yes`.
    2.  **Consultas de Lectura Pesadas (Locks):** Queries de reportería bloquean tablas en la réplica, impidiendo que el hilo SQL aplique las mutaciones binarias. *Diagnóstico:* Inspeccionar `information_schema.innodb_trx` y `performance_schema.metadata_locks`.
    3.  **Hardware Inferior o Red:** La réplica carece de los mismos IOPS en disco o memoria que el Primary. *Diagnóstico:* Monitoreo de infraestructura a nivel de sistema operativo (`iostat`, `top`).

*   **Proceso de Failover Manual (T2):** *(Comandos secuenciales exactos documentados en el script `5.2_mysql_failover.sql`)*. El redireccionamiento de la aplicación se gestiona modificando los registros de conexión en el balanceador de carga o actualizando la entrada DNS interna corporativa (`prod-mysql-primary.internal`) apuntando hacia la IP del nuevo nodo primario.

*   **Comparativa de Modos de Replicación (T3):**

| Modo de Replicación | Mecanismo | Ventajas | Desventajas / Riesgos |
| :--- | :--- | :--- | :--- |
| **STATEMENT (SBR)** | Copia el texto exacto del query SQL ejecutado. | Logs binarios muy pequeños; bajo consumo de red. | Riesgo severo de inconsistencia con funciones no deterministas (`NOW()`, `UUID()`). |
| **ROW (RBR)** | Copia los bytes exactos de las filas modificadas a nivel físico. | **Máxima consistencia y seguridad**; ideal para producción. Soporta cualquier tipo de transacción. | Genera logs binarios masivos en mutaciones masivas (ej. un `UPDATE` de 1M de filas escribe 1M de registros en el log). |
| **MIXED** | El motor usa STATEMENT por defecto y conmuta a ROW automáticamente ante funciones complejas. | Intenta balancear lo mejor de ambos mundos. | Menos predecible; dificulta auditorías forenses homogéneas del binlog. |

*   **Recomendación de Producción:** Se recomienda categóricamente la replicación basada en **ROW (RBR)** complementada obligatoriamente con **GTID (Global Transaction Identifiers)**. En entornos SaaS críticos, garantizar la fidelidad absoluta de los datos entre réplicas e impedir desviaciones lógicas (*Data Drift*) supera por completo cualquier costo marginal de almacenamiento o uso de red.
