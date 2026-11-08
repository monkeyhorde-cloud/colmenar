# Colmenar · especificación funcional v1

*App de gestión apícola para reemplazar a ApiDatos: control de apiarios, revisiones, colmenas, cosecha, tambores y contabilidad.*

El nombre «Colmenar» es provisional; cambiarlo no afecta nada de lo que sigue.

## 1. Decisiones de base

| Decisión | Elección | Por qué |
| --- | --- | --- |
| Usuarios | Varios apicultores independientes. Cada uno tiene su **explotación** con sus propios datos y puede invitar a su equipo. | Es lo que hace ApiDatos («Equipo asistente») y permite que la usen Marcos, otros apicultores y la escuela sin mezclar datos. |
| Datos | En la nube, en **Supabase** (Postgres + autenticación + almacenamiento de fotos). Plan gratuito. | Sincroniza entre celulares, respalda solo, y la seguridad por fila (RLS) garantiza que cada explotación vea únicamente lo suyo. |
| Formato | **PWA** instalable (una sola página web). | Corre en Android, iPhone y PC; se comparte por WhatsApp; no depende de las tiendas. |
| Mapas | **Leaflet + OpenStreetMap**, con capa satelital de Esri. | Gratis y sin clave de API. Google Maps requiere tarjeta de crédito. |
| Fotos | Se comprimen en el celular (máx. ~1280 px, ~200 KB) antes de subir. | El plan gratuito de Supabase da 1 GB: alcanza para miles de fotos comprimidas. |
| Moneda | Pesos (ARS) con cotización USD opcional por movimiento. | Permite leer resultados de temporadas pasadas sin que la inflación los deforme. |
| Hora | Fechas de trabajo como fecha (sin hora); registros con marca de tiempo UTC. | Igual criterio que el firmware del prototipo de colmena. |

## 2. Qué hace ApiDatos (relevamiento de las capturas)

- **Temporadas** anuales (2023/24, 2024/2025, 2025/2026, 2026/2027) con fecha de inicio; una es la actual. Los apiarios se «cargan» a la temporada.
- **Apiarios**: nombre, capacidad máxima, tipo, modalidad, observaciones, campos compartidos, ubicación en mapa satelital (punto + perímetro dibujado), foto. Pestañas: Datos, Mapa, Historial, Colmenas, Tambores.
- **Revisiones** por apiario: fecha de trabajo, uno o más **trabajos** de una lista fija, cada uno con su cantidad («Colmenas alimentadas: 20», «Colmenas tratadas: 28»), descripción, hasta 3 fotos, y un **recordatorio** corto con fecha que aparece en el panel como pendiente.
- Lista de trabajos: Alimentar · Colmenas muertas · Colocación de alza melaria · Control de enjambrazón · Control de maduración de miel · Control de reservas · Cosecha · División de colmenas · Ingreso por traslado · Mantenimiento · Monitoreo de varroa · Recambio de cuadros · Recambio de reinas · Reducción de piquera · Revisión · Sanidad · Traslado · Trasvasado · Tratamiento contra varroa.
- Historial filtrable por trabajo. Menú: Panel, Temporadas, Usuario, Planes, Configuración, Equipo asistente.
- **No tiene** contabilidad ni stock de miel: eso es lo que Colmenar agrega.

## 3. Módulos de Colmenar

### 3.1 Cuenta y explotación
- Registro e inicio de sesión con correo y contraseña (Supabase Auth). Más adelante: enlace mágico por correo.
- Al registrarse, el usuario crea su explotación (p. ej. «Apiarios Marcos»). Un usuario puede pertenecer a varias explotaciones y cambiar entre ellas.
- Roles: **dueño** (todo, incluido invitar y borrar), **asistente** (carga y edita datos), **lectura** (solo ve).
- Invitaciones por correo: cuando la persona invitada se registra con ese correo, entra sola a la explotación.

### 3.2 Temporadas
- Nombre, fecha de inicio, fecha de cierre (vacía mientras está abierta). Una sola temporada activa por explotación.
- Cada apiario se vincula a la temporada con su **cantidad de colmenas** al inicio y la actual. Así el panel muestra «Hugo: 28 colmenas» sin obligar a cargar colmena por colmena.
- Cerrar una temporada congela sus números; se puede seguir consultando.

### 3.3 Apiarios
- Nombre, capacidad máxima, tipo (fijo / trashumante), modalidad (propio / alquilado / compartido / comodato), observaciones, con quién se comparte el campo, activo/inactivo.
- Ubicación: tocar el mapa o «usar mi ubicación»; perímetro opcional dibujado por puntos (deshacer, limpiar). Foto del apiario.
- Pestañas: **Datos · Mapa · Historial · Colmenas · Tambores · Cuentas** (ingresos y egresos de ese apiario).

### 3.4 Revisiones y trabajos
- Igual que ApiDatos, con mejoras: apiario, fecha de trabajo, uno o más trabajos con cantidad (la etiqueta de la cantidad depende del trabajo: «Colmenas alimentadas», «Kg cosechados», «Reinas cambiadas»…), descripción, hasta **6** fotos, recordatorio (texto + fecha).
- Algunos trabajos piden **datos extra**: Sanidad y Tratamiento contra varroa → producto y dosis; Monitoreo de varroa → método (alcohol / azúcar / tablero) y ácaros por 100 abejas; Alimentar → tipo de alimento y kilos o litros; Cosecha → kilos estimados y alzas retiradas.
- El catálogo de trabajos es **global**, pero cada explotación puede agregar los suyos.
- Historial por apiario con filtro por trabajo y por temporada; búsqueda por texto en descripciones.
- **Panel principal**: recordatorios pendientes (vencidos en rojo), últimas revisiones, apiarios sin visitar hace más de N días (configurable), totales de la temporada.

### 3.5 Colmenas (opcional por apiario)
- Para quien quiera seguimiento individual: código o número, origen (compra / división / enjambre / traslado), fecha de alta, estado (activa / muerta / vendida / trasladada / fusionada), año y origen de la reina, notas.
- Eventos por colmena vinculados a una revisión (p. ej. «recambio de reina 2026-10-19»).
- Si no se cargan colmenas individuales, la app sólo usa la cantidad por apiario y temporada.

### 3.6 Cosecha, miel y tambores
- **Cosecha**: fecha, apiario, temporada, alzas retiradas, kilos obtenidos (al extraer), observaciones. Puede nacer de un trabajo «Cosecha» en una revisión.
- **Tambores**: número, temporada, apiario de origen (o «mezcla»), fecha de llenado, kg bruto, tara, kg neto (calculado), tipo de miel (multifloral, eucalipto, etc.), estado (vacío / lleno / vendido / entregado al acopiador), lote o análisis.
- **Stock**: kilos en tambores llenos, por temporada y por apiario; kilos vendidos; rendimiento por colmena (kg ÷ colmenas) por apiario y temporada.

### 3.7 Contabilidad
- **Movimientos**: fecha, tipo (ingreso / egreso), categoría, descripción, monto en pesos, cotización USD opcional, temporada, apiario (opcional: los gastos generales quedan sin apiario), cantidad y unidad (p. ej. 50 kg de azúcar), foto del comprobante.
- Categorías de egreso: alimento, sanidad y medicamentos, material de colmena (cera, cuadros, alzas, pisos, techos), reinas y núcleos, envases y tambores, combustible y traslados, mano de obra, alquiler de campo o comodato, extracción y sala, impuestos y habilitaciones, herramientas, otros.
- Categorías de ingreso: venta de miel, venta de núcleos y colmenas, venta de reinas, polinización, cera y propóleos, otros.
- **Ventas de miel**: cliente, fecha, kilos, precio por kilo, total, cobrado o no, tambores incluidos. Al guardar una venta se genera su movimiento de ingreso y los tambores pasan a «vendidos».
- **Informes**: resultado por temporada (ingresos − egresos), por apiario, por categoría; costo por colmena y por kilo de miel; comparación entre temporadas; exportación a Excel/CSV.

### 3.8 Configuración y datos
- Datos de la explotación (nombre, localidad, RENAPA), trabajos y categorías propias, días sin visita para alertar, moneda.
- Exportar todo a Excel; importar apiarios desde una planilla.
- Funcionamiento sin señal (etapa 3): la app guarda las cargas en el teléfono y las sube cuando vuelve la conexión. En el campo suele no haber señal: esto es imprescindible, no un lujo.

## 4. Modelo de datos (resumen)

Todas las tablas de datos llevan `explotacion_id`; la seguridad por fila de Postgres sólo deja ver y tocar las filas de las explotaciones donde el usuario es miembro.

```
perfiles ─┐
          ├── miembros (rol) ── explotaciones ── invitaciones
usuarios ─┘                          │
                                     ├── temporadas ──┐
                                     ├── apiarios ────┼── apiarios_temporada (colmenas inicio/actual)
                                     │     ├── revisiones ── revision_trabajos ── tipos_trabajo (global o propio)
                                     │     │                └── revision_fotos
                                     │     ├── colmenas ── colmena_eventos
                                     │     ├── cosechas
                                     │     └── tambores ──┐
                                     ├── ventas ──────────┘
                                     ├── movimientos ── categorias_movimiento (global o propia)
                                     └── vistas: v_resultado, v_stock_miel, v_recordatorios
```

El detalle de columnas, restricciones, políticas y catálogos está en `esquema-v1.sql`.

## 5. Arquitectura técnica

- **Frontend**: un `index.html` autocontenido (HTML + CSS + JavaScript sin framework), `manifest.webmanifest` y `sw.js` (service worker) para instalación y caché. Bibliotecas por CDN: `@supabase/supabase-js`, `leaflet`, `xlsx` (exportación), `browser-image-compression`.
- **Backend**: Supabase (Postgres 15+, Auth, Storage con bucket privado `fotos`, URLs firmadas). Sin servidor propio ni código de servidor en la etapa 1; la lógica de negocio que debe ser confiable (roles, totales de venta, estado de tambores) vive en funciones y disparadores de Postgres.
- **Hosting**: GitHub Pages, Cloudflare Pages o una carpeta en fundaciondd.org.ar. Sólo archivos estáticos.
- **Costos**: Supabase gratuito (500 MB de base, 1 GB de fotos, 50.000 usuarios activos). Ojo: el proyecto gratuito se **pausa tras 7 días sin uso** y hay que reactivarlo a mano; con uso semanal no pasa. El plan Pro (USD 25/mes) quita esa pausa y da copias de seguridad diarias.

## 6. Etapas

| Etapa | Contenido | Resultado |
| --- | --- | --- |
| **0 · Base** (esta entrega) | Especificación, esquema SQL con RLS, catálogos, bucket de fotos, instrucciones de Supabase. | Base lista; se prueba desde el panel de Supabase. |
| **1 · Núcleo** | PWA con registro, explotación, temporadas, apiarios con mapa y foto, revisiones con trabajos, fotos y recordatorios, historial, panel. | Reemplaza lo que hoy hace ApiDatos. |
| **2 · Producción** | Cosechas, tambores, stock, ventas de miel, movimientos y categorías, informes por temporada y apiario, exportación a Excel. | La contabilidad completa. |
| **3 · Campo** | Modo sin señal con cola de sincronización, colmenas individuales y eventos, equipo asistente con invitaciones, importación desde planilla. | Uso real en apiarios sin cobertura. |
| **4 · Extras** | Enlace mágico por correo, notificaciones de recordatorios, informes en PDF, lectura de los sensores del prototipo de colmena monitoreada (ESP32) dentro de la misma app. | Integración con el proyecto de monitoreo. |

## 7. Pendientes a definir con vos

1. Nombre definitivo de la app y, si querés, logo y colores (propongo amarillo miel y marrón oscuro, igual que la paleta de «Misión Colmena»).
2. ¿Exportar los datos actuales de ApiDatos? Si la app permite exportar a Excel, armo un importador; si no, se cargan a mano los apiarios y se arranca con la temporada 2026/2027.
3. Dominio: ¿subcarpeta en fundaciondd.org.ar o dominio propio?
