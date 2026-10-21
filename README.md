# 🚀 API de Seguridad Avanzada con FastAPI y Arquitectura Multi-Motor

Este proyecto es una API robusta y securizada desarrollada en **FastAPI** que implementa controles avanzados de administración de bases de datos bajo estándares corporativos. El sistema interactúa simultáneamente con **MongoDB** (en contenedor aislado), **MySQL** (en contenedor aislado) y **Microsoft SQL Server / MSSQL** (ejecutándose nativamente). 

El laboratorio demuestra de forma práctica:
* **Módulo 1.2:** Implementación de *Dynamic Data Masking (DDM)*, Control de Acceso Basado en Roles (RBAC) y *SQL Server Audit*.
* **Módulo 1.3:** Seguridad en bases de datos NoSQL, segregación estricta de privilegios (RBAC) y fundamentación de esquemas de cifrado *CSFLE* y auditorías de fallos en MongoDB.

---

## 🛠️ Requisitos Previos

Antes de comenzar, asegúrate de tener instalado y activo lo siguiente en tu sistema operativo (entorno Windows recomendado):
* [Python 3.10+](https://python.org)
* [Docker Desktop](https://docker.com) en ejecución.
* [Microsoft SQL Server Local (Instancia nativa)](https://microsoft.com) configurado con **Autenticación Mixta** habilitada.
* [Driver ODBC 17 o 18 para SQL Server](https://microsoft.com) instalado en Windows.
* [Visual Studio Code](https://visualstudio.com) con la extensión **SQL Server (mssql)** y opcionalmente **REST Client**.

---

## 📦 1. Despliegue de Contenedores (Docker)

El entorno utiliza contenedores para aislar los motores de MySQL y MongoDB.

1. Abre tu terminal en la raíz del proyecto y despliega la infraestructura en segundo plano:
   ```bash
   docker compose up -d
   ```
2. Asegúrate de que los servicios estén activos:
   ```bash
   docker ps
   ```

*Nota: El servicio de MySQL mapea externamente al puerto `3307` para evitar colisiones del sistema.*

---

## 🗄️ 2. Inicialización y Carga de Seguridad en Bases de Datos

Para que la API funcione correctamente, se deben inyectar las políticas de seguridad corporativas en cada motor antes de levantar el servidor web:

### A) Configuración de Microsoft SQL Server (Módulo 1.2)
1. Abre tu VS Code, conéctate a tu SQL Server local (`localhost`) con tu cuenta de administrador (`sa` o Windows Authentication).
2. Ejecuta el script completo `1.2_mssql_auditoria.sql` para crear la base de datos `HR_Production`, la tabla `employees` con enmascaramiento dinámico (DDM), las cuentas restringidas (`report_viewer_login`, `hr_manager_login`) y el servidor de auditorías.
3. Asegúrate de crear manualmente la carpeta `C:\SQLAudit\` en tu disco local para que el motor pueda escribir los logs binarios de auditoría de forma nativa.

### B) Configuración de MongoDB Security (Módulo 1.3)
Ejecuta el script automatizado utilizando PowerShell para aprovisionar las colecciones de analítica y dar de alta a los tres usuarios con roles segregados (`writer_user`, `analista_user` y `engineer_user`) en la base de datos global de autenticación:
```powershell
Get-Content 1.3_mongodb_analytics.js | docker exec -i mi_mongo mongosh -u root -p password --authenticationDatabase admin
```

---

## 🐍 3. Configuración de la API en Python

Sigue estos pasos para aislar el entorno virtual e instalar las librerías cliente necesarias (`pymongo`, `pymysql`, `pyodbc`):

1. **Crear y activar el entorno virtual:**
   ```bash
   python -m venv env
   .\env\Scripts\Activate.ps1
   ```
2. **Instalar dependencias necesarias:**
   ```bash
   pip install fastapi uvicorn pymongo pymysql pyodbc pydantic
   ```
3. **Iniciar la API en modo desarrollo:**
   ```bash
   uvicorn main:app --reload
   ```

El servidor web quedará activo de forma inmediata en: **`http://localhost:8000`**.

---

## 📖 4. Validación de la Segregación de Roles (Swagger UI)

Ingresa desde tu navegador a **`http://localhost:8000/docs`** para interactuar con la documentación interactiva OpenAPI y auditar el comportamiento de los roles implementados:

### 🛡️ Escenarios de Prueba en MongoDB (Módulo 1.3)
* **`POST /mongodb/escritor/registrar-evento`**: Prueba el rol `eventWriter`. Permite realizar inserciones de datos JSON estructurados pero restringe cualquier lectura por privacidad de logs.
* **`GET /mongodb/analista/ver-eventos`**: Prueba el rol `analyticsReader`. Devuelve los logs consolidados en texto plano para analítica de datos sin otorgar permisos de alteración/escritura.
* **`POST y GET de /mongodb/ingeniero/...`**: Valida el rol avanzado `dataEngineer` ejecutando acciones de infraestructura, permitiendo consultar colecciones dinámicas y generar índices estructurales en caliente (`createIndex`).

### 🔒 Escenarios de Prueba en SQL Server (Módulo 1.2)
* **`GET /mssql/reportes/usuarios-enmascarados`**: Ejecuta la lectura bajo el rol `report_viewer`. Comprueba cómo el motor oculta el sueldo en `0.00`, enmascara el correo electrónico y oculta dígitos de identidad (PII) bajo políticas de protección de datos.
* **`GET /mssql/gerencia/usuarios-reales`**: Ejecuta la consulta bajo el usuario administrador `hr_manager`. El sistema detecta el privilegio `UNMASK` y permite procesar los salarios e identidades en su estado original.

---

## 📐 Arquitectura de Red y Puertos Activos

| Servicio | Motor DB | Puerto Interno | Puerto Host (Tu PC) | Autenticación Requerida |
| :--- | :--- | :--- | :--- | :--- |
| `mysql-db` | MySQL | `3306` | `3307` | Estándar |
| `mongo-db` | MongoDB | `27017` | `27017` | RBAC Avanzado (Base `admin`) |
| `Local MSSQL`| SQL Server | `1433` | `1433` | Modos Mixtos / Seguridad Integrada |
