# 🚀 API con FastAPI y Bases de Datos Multimotor (Docker)

Este proyecto es una API robusta desarrollada en **FastAPI** que interactúa simultáneamente con tres motores de bases de datos diferentes (**PostgreSQL, MySQL y MongoDB**) ejecutándose dentro de contenedores aislados mediante **Docker Desktop**. Incluye documentación interactiva y pruebas automatizadas de peticiones HTTP.

---

## 🛠️ Requisitos Previos

Antes de comenzar, asegúrate de tener instalado lo siguiente en tu sistema:
* [Python 3.10+](https://python.org)
* [Docker Desktop](https://docker.com) activo y ejecutándose.
* [Visual Studio Code](https://visualstudio.com) (Opcional, pero recomendado con la extensión **REST Client**).

---

## 📦 1. Despliegue de la Infraestructura (Docker)

El proyecto utiliza `docker-compose` para levantar y configurar automáticamente todos los motores de bases de datos con sus respectivos puertos y credenciales.

1. Abre tu terminal en la raíz del proyecto.
2. Ejecuta el siguiente comando para descargar las imágenes e iniciar los contenedores en segundo plano:
   ```bash
   docker compose up -d
   ```
3. Verifica que los servicios estén corriendo correctamente en Docker Desktop o mediante la terminal con:
   ```bash
   docker ps
   ```

*Nota: El servicio de MySQL se ha mapeado externamente al puerto `3307` para evitar conflictos con instalaciones locales del sistema.*

---

## 🐍 2. Configuración del Entorno de Python

Sigue estos pasos para aislar las dependencias e iniciar el servidor de desarrollo de la API:

1. **Crear el entorno virtual:**
   ```bash
   python -m venv env
   ```
2. **Activar el entorno virtual (en Windows):**
   ```powershell
   .\env\Scripts\Activate.ps1
   ```
3. **Instalar las dependencias requeridas:**
   ```bash
   pip install -r requirements.txt
   ```
4. **Iniciar la API con Uvicorn:**
   ```bash
   uvicorn main:app --reload
   ```

El servidor web se iniciará de forma nativa en la dirección local: **`http://127.0.0.1:8000`**.

---

## 📖 3. ¿Cómo usar e interactuar con la API?

El proyecto ofrece dos métodos integrados para interactuar y enviar datos hacia los contenedores de Docker:

### Opción A: Interfaz Gráfica Interactiva (Recomendado)
FastAPI genera de manera automática una documentación interactiva bajo el estándar de OpenAPI (Swagger).
1. Abre tu navegador web e ingresa a: **`http://localhost:8000/docs`**
2. Despliega cualquiera de las rutas disponibles (por ejemplo, `POST /mongodb/usuarios`).
3. Haz clic en el botón **"Try it out"**.
4. Modifica el cuerpo del JSON con tus datos de prueba y presiona **"Execute"**.

### Opción B: Archivo de Peticiones HTTP en VS Code
Si utilizas la extensión **REST Client** en VS Code, puedes realizar solicitudes directas sin salir del editor:
1. Abre el archivo **`api_requests.http`** incluido en la raíz.
2. Verás un hipervínculo interactivo sobre cada método que dice `Send Request`.
3. Haz clic en él y observa la respuesta del servidor en tiempo real en el panel derecho.

---

## 🗄️ Arquitectura y Mapeo de Puertos

| Servicio | Motor DB | Puerto Interno | Puerto Host (Tu PC) |
| :--- | :--- | :--- | :--- |
| `postgres-db` | PostgreSQL | `5432` | `5432` |
| `mysql-db` | MySQL | `3306` | `3307` |
| `mongo-db` | MongoDB | `27017` | `27017` |

---
