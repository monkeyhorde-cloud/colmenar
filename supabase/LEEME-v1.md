# Colmenar · etapa 0 (base de datos) · v1

App de gestión apícola para reemplazar a ApiDatos: apiarios, revisiones, colmenas, cosecha, tambores y contabilidad, para varios apicultores independientes, con datos en la nube y PWA instalable.

## Archivos

| Archivo | Qué es |
| --- | --- |
| `especificacion-v1.md` | Relevamiento de ApiDatos, decisiones, módulos, modelo de datos, arquitectura y etapas. |
| `esquema-v1.sql` | Base de datos completa para Supabase: 18 tablas, seguridad por fila, disparadores, vistas, catálogos y bucket de fotos. Probado en Postgres 16 con usuarios simulados. |
| `LEEME-v1.md` | Este archivo. |

## Qué hay que hacer de tu lado (unos 15 minutos)

### 1. Crear el proyecto en Supabase
1. Entrar a **supabase.com**, crear una cuenta (sirve la de GitHub o un correo) y elegir **New project**.
2. Nombre: `colmenar` (o el que quieras). **Database password**: inventar una larga y guardarla; no se usa en la app pero hace falta para administrar.
3. Región: **South America (São Paulo)**, la más cercana a Buenos Aires.
4. Plan **Free**. Esperar 1 o 2 minutos a que el proyecto quede listo.

### 2. Cargar el esquema
1. En el menú izquierdo, **SQL Editor** → **New query**.
2. Pegar **todo** el contenido de `esquema-v1.sql` y apretar **Run** (o Ctrl+Enter).
3. Debe terminar con «Success. No rows returned». Si aparece un error, copiarme el mensaje completo: el esquema está pensado para correr **una sola vez** sobre un proyecto vacío, así que si falló a medias conviene borrar el proyecto y empezar otro, o pedirme un script de limpieza.
4. Verificar: en **Table Editor** aparecen las tablas (`apiarios`, `revisiones`, `tambores`, `movimientos`…), y en **Storage** el bucket `fotos`.

### 3. Configurar el acceso por correo
1. **Authentication → Sign In / Providers → Email**: dejarlo habilitado.
2. Para las primeras pruebas, desactivar **Confirm email** (así no hace falta clic en un correo para entrar). Para producción se vuelve a activar.
3. **Authentication → URL Configuration → Site URL**: por ahora dejar `http://localhost`; cuando la PWA tenga dirección la cambiamos.

### 4. Pasarme las claves públicas
En **Project Settings → API** copiar:
- **Project URL** (algo como `https://abcdefgh.supabase.co`)
- **anon public** key (una cadena larga que empieza con `eyJ…`)

Las dos son públicas por diseño: van dentro de la PWA y la seguridad la dan las políticas por fila de la base. La clave **service_role** NO se comparte ni se pone en la app nunca.

Con esas dos claves construyo la **etapa 1**: la PWA con registro, explotación, temporadas, apiarios con mapa y foto, revisiones con trabajos, fotos y recordatorios, historial y panel.

## Qué contiene la base

- **Cuentas**: `perfiles`, `explotaciones`, `miembros` (roles dueño / asistente / lectura), `invitaciones` por correo que se aceptan solas al registrarse.
- **Producción**: `temporadas` (una activa por explotación), `apiarios` (ubicación, perímetro, foto), `apiarios_temporada` (colmenas por temporada), `tipos_trabajo` (los 19 de ApiDatos, con etiqueta de cantidad y datos extra por trabajo), `revisiones`, `revision_trabajos`, `revision_fotos`, `colmenas`, `colmena_eventos`.
- **Miel**: `cosechas`, `tambores` (kg neto calculado), `ventas` (generan solas su movimiento de ingreso y marcan los tambores como vendidos).
- **Contabilidad**: `categorias_movimiento` (12 de egreso, 6 de ingreso) y `movimientos` con cotización USD opcional.
- **Vistas**: `v_recordatorios`, `v_resultado`, `v_stock_miel`, `v_ultima_visita`.
- **Función** `crear_explotacion(nombre, temporada, fecha)` para el alta inicial en un paso.

## Límites del plan gratuito a tener en cuenta

- 500 MB de base de datos y 1 GB de fotos: con fotos comprimidas alcanza para años.
- El proyecto se **pausa después de 7 días sin actividad**; se reactiva con un clic en el panel, sin perder datos. Con uso semanal no ocurre.
- Hasta 2 proyectos gratuitos por cuenta.

## Cómo se verificó

El esquema se ejecutó en un Postgres 16 local con un sustituto mínimo de los esquemas `auth` y `storage` de Supabase, y luego una prueba funcional con tres usuarios simulados comprobó: alta de perfil por disparador; creador como dueño; carga de apiario, temporada, revisión con dos trabajos y recordatorio; recordatorio vencido en la vista; gasto; tambor con kg neto calculado; venta que genera el ingreso y marca el tambor como vendido; resultado por tipo con conversión a USD; que un usuario ajeno ve cero filas y no puede insertar; que un invitado entra solo al registrarse, puede cargar, y no puede invitar a otros.
