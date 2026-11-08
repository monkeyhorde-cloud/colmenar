# Colmenar

App de gestión apícola: apiarios, revisiones, colmenas, cosecha, tambores y contabilidad.
Pensada para reemplazar a ApiDatos, para varios apicultores independientes, con datos en la nube y uso desde el celular.

**Estado:** etapa 0 terminada (especificación y base de datos). Etapa 1 (PWA) en construcción.

## Estructura del repositorio

| Carpeta / archivo | Contenido |
| --- | --- |
| `docs/especificacion-v1.md` | Relevamiento de ApiDatos, decisiones, módulos, modelo de datos, arquitectura y etapas. |
| `supabase/esquema-v1.sql` | Base de datos para Supabase: tablas, seguridad por fila, disparadores, vistas, catálogos y bucket de fotos. |
| `supabase/LEEME-v1.md` | Pasos para crear el proyecto en Supabase y cargar el esquema. |
| `index.html` | La aplicación (PWA de una sola página). |
| `manifest.webmanifest`, `sw.js`, `iconos/` | Instalación en el celular y funcionamiento con caché. |

## Tecnología

- **Frontend:** HTML, CSS y JavaScript sin framework; Leaflet + OpenStreetMap para mapas.
- **Backend:** Supabase (Postgres, autenticación, almacenamiento de fotos). Sin servidor propio.
- **Publicación:** GitHub Pages, desde la rama `main`.

## Etapas

0. Base: especificación y esquema. ✅
1. Núcleo: cuentas, explotación, temporadas, apiarios con mapa, revisiones con trabajos, fotos y recordatorios, historial, panel.
2. Producción: cosechas, tambores, stock, ventas, movimientos, informes, exportación a Excel.
3. Campo: modo sin señal, colmenas individuales, equipo asistente, importación desde planilla.
4. Extras: enlace mágico, notificaciones, informes PDF, integración con el prototipo de colmena monitoreada.

## Versiones

Cada archivo entregado lleva su número de versión en el nombre (`-v1`, `-v2`…). La versión de la app se muestra en su pantalla de configuración.
