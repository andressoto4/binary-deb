# ws-unp — Manual de Operaciones

**Versión:** 0.1.0  
**Sistema:** Ubuntu 24.04 LTS (Noble) / Debian 12+  
**Mantenedor:** Andrés Soto — Unidad Nacional de Protección (UNP)

---

## Tabla de contenidos

1. [Requisitos previos](#1-requisitos-previos)
2. [Instalación](#2-instalación)
3. [Configuración inicial](#3-configuración-inicial)
4. [Operación diaria](#4-operación-diaria)
5. [Actualización](#5-actualización)
6. [Recuperación ante fallos](#6-recuperación-ante-fallos)
7. [Notas de versión](#7-notas-de-versión)

---

## 1. Requisitos previos

| Componente | Versión mínima | Notas |
|---|---|---|
| Sistema operativo | Ubuntu 22.04 / Debian 12 | amd64 |
| PostgreSQL | 14+ | puede ser remoto |
| `postgresql-client` | cualquiera | para crear tablas con `ws-unp setup` |
| `openssl` | cualquiera | para generar contraseñas y certificados TLS |
| `adduser` | cualquiera | creado por el instalador |
| Puerto abierto | 1520/tcp | configurable en el asistente |

No es necesario crear el usuario ni la base de datos manualmente.
**El asistente `sudo ws-unp setup` lo hace todo.**

---

## 2. Instalación

### 2.1 Instalar el paquete

```bash
sudo dpkg -i ws-unp-0.1.0.deb
sudo apt-get install -f          # resuelve dependencias faltantes
```

El instalador crea automáticamente:
- Usuario/grupo de sistema `ws-unp` (sin shell, sin home)
- Directorio `/etc/ws-unp/` con permisos `750 root:ws-unp`
- Directorio `/var/lib/ws-unp/` para datos temporales
- Regla UFW para el puerto 1520/tcp (si UFW está activo)

Al terminar aparece el mensaje:

```
  ═════════════════════════════════════════════════
  ws-unp instalado correctamente.
  Complete la configuración inicial con:

    sudo ws-unp setup
```

### 2.2 Construir el paquete desde fuentes

```bash
git clone <repositorio>
cd ws-unp-0.1.0
dpkg-buildpackage -us -uc -b
# El .deb queda en el directorio padre
```

---

## 3. Configuración inicial

### 3.1 Asistente de configuración — `ws-unp setup`

```bash
sudo ws-unp setup
```

El asistente hace las siguientes preguntas (pulse Enter para aceptar el valor por defecto):

```
═══════════════════════════════════════════════════════
  ws-unp — Asistente de configuración inicial
  Unidad Nacional de Protección (UNP)
═══════════════════════════════════════════════════════
  Puerto WebSocket                [1520]:
  Host de PostgreSQL              [localhost]:
  Puerto de PostgreSQL            [5432]:
  Nombre de la base de datos      [sgdea]:
  Usuario de PostgreSQL           [ws_unp]:
  Contraseña para 'ws_unp'        [Enter = generar automáticamente]:
```

Luego muestra un resumen, pide confirmación y ejecuta automáticamente:

| Paso | Acción |
|---|---|
| **[1/4]** | Crea el usuario y la base de datos en PostgreSQL |
| **[2/4]** | Escribe `/etc/ws-unp/ws-unp.conf` (permisos 640 root:ws-unp) |
| **[3/4]** | Ejecuta el esquema SQL (`CREATE TABLE IF NOT EXISTS…`) |
| **[4/4]** | Habilita e inicia el servicio systemd |

> Si la contraseña se deja en blanco, el asistente genera una de 32 caracteres
> alfanuméricos y la guarda directamente en el archivo de configuración.

### 3.2 PostgreSQL remoto

Si la base de datos está en otro servidor, responda con el host remoto cuando
el asistente lo solicite. En ese caso, el paso [1/4] se omite y deberá crear
el usuario y la base manualmente en el servidor remoto:

```sql
CREATE USER ws_unp WITH PASSWORD 'su_clave_segura';
CREATE DATABASE sgdea OWNER ws_unp;
```

### 3.2 Ejecutar la migración SQL (solo en el primer despliegue)

```bash
sudo -u ws-unp ws-unp --migrate
```

Esto crea las tablas `users`, `rooms`, `room_members`, `messages`,
`pending_events` y `undelivered_messages` usando `IF NOT EXISTS`,
por lo que es seguro ejecutarlo más de una vez.

### 3.3 Habilitar TLS/WSS (recomendado si hay clientes externos)

```bash
# Generar certificado autofirmado (solo pruebas)
sudo openssl req -x509 -newkey rsa:4096 \
    -keyout /etc/ws-unp/key.pem \
    -out    /etc/ws-unp/cert.pem \
    -days 365 -nodes \
    -subj "/CN=ws-unp.unp.gov.co"

# Ajustar permisos
sudo chown root:ws-unp /etc/ws-unp/{cert,key}.pem
sudo chmod 640         /etc/ws-unp/{cert,key}.pem
```

Descomentar en `/etc/ws-unp/ws-unp.conf`:

```ini
TLS_CERT_PATH=/etc/ws-unp/cert.pem
TLS_KEY_PATH=/etc/ws-unp/key.pem
```

### 3.4 Habilitar e iniciar el servicio

```bash
sudo systemctl enable ws-unp
sudo systemctl start  ws-unp
sudo systemctl status ws-unp
```

---

## 4. Operación diaria

### Iniciar / detener / reiniciar

```bash
sudo systemctl start   ws-unp
sudo systemctl stop    ws-unp
sudo systemctl restart ws-unp   # aplicar cambios en ws-unp.conf
```

### Revisar logs

```bash
# Seguimiento en tiempo real
sudo journalctl -u ws-unp -f

# Últimas 100 líneas
sudo journalctl -u ws-unp -n 100

# Logs del día de hoy
sudo journalctl -u ws-unp --since today

# Logs entre fechas
sudo journalctl -u ws-unp --since "2026-03-23 08:00" --until "2026-03-23 18:00"

# Solo errores y críticos
sudo journalctl -u ws-unp -p err
```

### Activar logs detallados temporalmente (sin reiniciar)

```bash
# En ws-unp.conf agregar:  RUST_LOG=debug
sudo systemctl restart ws-unp
sudo journalctl -u ws-unp -f
# Volver a nivel normal:
# RUST_LOG=info  →  sudo systemctl restart ws-unp
```

### Verificar conexiones activas

```bash
ss -tnp | grep ws-unp
# o por puerto:
ss -tlnp | grep 1520
```

### Verificar variables de entorno cargadas por systemd

```bash
sudo systemctl show-environment ws-unp 2>/dev/null || \
sudo cat /proc/$(pgrep ws-unp)/environ | tr '\0' '\n'
```

---

## 5. Actualización

### 5.1 Actualización sin pérdida de datos

```bash
# 1. Hacer backup de la configuración
sudo cp /etc/ws-unp/ws-unp.conf /etc/ws-unp/ws-unp.conf.bak

# 2. Instalar el nuevo paquete (dpkg preserva ws-unp.conf si fue modificado)
sudo dpkg -i ws-unp_0.2.0-1_amd64.deb

# 3. Si hay cambios de esquema, aplicar migración
sudo -u ws-unp ws-unp --migrate

# 4. Verificar que el servicio arrancó correctamente
sudo systemctl status ws-unp
sudo journalctl -u ws-unp -n 30
```

### 5.2 Rollback a versión anterior

```bash
# Detener el servicio
sudo systemctl stop ws-unp

# Instalar la versión anterior
sudo dpkg -i ws-unp_0.1.0-1_amd64.deb

# Restaurar configuración si es necesario
sudo cp /etc/ws-unp/ws-unp.conf.bak /etc/ws-unp/ws-unp.conf
sudo chown root:ws-unp /etc/ws-unp/ws-unp.conf
sudo chmod 640         /etc/ws-unp/ws-unp.conf

# Reiniciar
sudo systemctl start ws-unp
```

---

## 6. Recuperación ante fallos

### 6.1 El servicio no arranca

**Diagnóstico:**

```bash
sudo systemctl status ws-unp
sudo journalctl -u ws-unp -n 50 --no-pager
```

| Mensaje en el log | Causa | Solución |
|---|---|---|
| `CAMBIE_ESTA_CLAVE` | Credencial placeholder sin cambiar | Editar `database_url` en `/etc/ws-unp/ws-unp.conf` |
| `connection refused` | PostgreSQL no disponible | `sudo systemctl start postgresql` |
| `Address already in use` (error 98) | Puerto ocupado | `ss -tlnp \| grep 1520` → matar proceso huérfano |
| `No such file or directory` (ws.sql) | Primer despliegue sin migración | `sudo -u ws-unp ws-unp --migrate` |
| `permission denied` (cert/key) | Permisos incorrectos en TLS | `sudo chmod 640 /etc/ws-unp/{cert,key}.pem` |

### 6.2 El servicio se cae repetidamente

```bash
# Ver cuántas veces reinició en las últimas 24h
sudo journalctl -u ws-unp --since "24 hours ago" | grep -c "Started"

# Si superó el límite (5 reinicios en 60s), systemd lo habrá detenido
sudo systemctl reset-failed ws-unp
sudo systemctl start ws-unp
```

### 6.3 Pérdida de conexiones masiva / clientes no reciben mensajes

```bash
# Ver si hay errores de broadcast o canal lleno
sudo journalctl -u ws-unp -n 200 | grep -E "WARN|ERROR"

# Reinicio controlado (los mensajes pendientes se re-entregan al reconectar)
sudo systemctl restart ws-unp
```

Los mensajes enviados a usuarios offline se guardan en `undelivered_messages`
y se re-entregan automáticamente en la próxima conexión del cliente.

### 6.4 Base de datos inaccesible

```bash
# Verificar estado de PostgreSQL
sudo systemctl status postgresql

# Probar conectividad manualmente
sudo -u ws-unp psql "$(grep database_url /etc/ws-unp/ws-unp.conf | cut -d= -f2-)"

# Si el pool se agotó, reiniciar el servicio restablece las conexiones
sudo systemctl restart ws-unp
```

### 6.5 Proceso zombie occupando el puerto tras un reinicio fallido

```bash
# Identificar PID
ss -tlnp | grep 1520

# Terminar
sudo kill -9 <PID>

# Iniciar limpiamente
sudo systemctl start ws-unp
```

### 6.6 Desinstalar sin perder datos de configuración

```bash
# Elimina el binario pero conserva /etc/ws-unp/ y /var/lib/ws-unp/
sudo dpkg -r ws-unp

# Eliminar completamente incluyendo configuración (irreversible)
sudo dpkg --purge ws-unp
```

---

## 7. Notas de versión

### v0.1.0 — 23 de marzo de 2026

**Primera versión de producción.**

#### Características incluidas
- Servidor WebSocket sobre Tokio con soporte WS y WSS (TLS nativo con `rustls`)
- Mensajería en tiempo real por salas (`CreateRoom`, `JoinRoom`, `Msg`)
- Notificaciones directas a usuario (`Notify`, `MailUpdate`)
- Re-entrega de mensajes pendientes a usuarios offline al reconectar
- Rate limiting: 20 mensajes/segundo por usuario
- Heartbeat con Ping/Pong cada 30 s y detección de conexiones zombie
- Sincronización multi-instancia vía PostgreSQL `LISTEN/NOTIFY`
- Multi-dispositivo: un usuario puede tener múltiples conexiones simultáneas
- Caché en memoria con `DashMap` (sin RwLock global, escala horizontalmente)
- Logger con detección automática de systemd (sin ANSI ni timestamps bajo journald)
- Validación temprana de configuración: detecta placeholder `CAMBIE_ESTA_CLAVE` al arrancar
- Empaquetado `.deb` con usuario de sistema dedicado, hardening systemd y regla UFW automática

#### Dependencias en tiempo de ejecución
- `postgresql-client` — para aplicar el esquema SQL con `--migrate`
- `openssl` — para gestionar certificados TLS
- `adduser` — para crear el usuario de sistema en la instalación

#### Archivos instalados
| Ruta | Descripción |
|---|---|
| `/usr/bin/ws-unp` | Binario principal |
| `/etc/ws-unp/ws-unp.conf` | Configuración (640 root:ws-unp) |
| `/usr/share/ws-unp/ws.sql` | Esquema SQL para el DBA |
| `/lib/systemd/system/ws-unp.service` | Unidad systemd |
| `/var/lib/ws-unp/` | Directorio de trabajo del proceso |
