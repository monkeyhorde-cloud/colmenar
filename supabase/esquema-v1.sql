-- =============================================================================
--  Colmenar · esquema de base de datos v1 (Supabase / Postgres 15+)
--  Gestión apícola: explotaciones, temporadas, apiarios, revisiones, colmenas,
--  cosecha, tambores, ventas y contabilidad.
--
--  Cómo usarlo: en el panel de Supabase, SQL Editor → New query → pegar todo
--  este archivo → Run. Se puede correr una sola vez sobre un proyecto vacío.
--
--  Criterios:
--   · Todas las tablas de datos llevan explotacion_id. La seguridad por fila
--     (RLS) sólo deja ver/tocar filas de explotaciones donde el usuario es
--     miembro; editar requiere rol duenio o asistente.
--   · Catálogos (tipos de trabajo, categorías) tienen filas globales
--     (explotacion_id NULL, visibles para todos) y filas propias de cada
--     explotación.
--   · Las fechas de trabajo son DATE; las marcas de registro son TIMESTAMPTZ.
--   · Textos y nombres en español, sin tildes en identificadores.
-- =============================================================================

create extension if not exists pgcrypto;

-- -----------------------------------------------------------------------------
-- 1. Usuarios, explotaciones y membresías
-- -----------------------------------------------------------------------------
create table public.perfiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  nombre      text,
  celular     text,
  creado_en   timestamptz not null default now()
);

create table public.explotaciones (
  id            uuid primary key default gen_random_uuid(),
  nombre        text not null check (length(trim(nombre)) > 0),
  localidad     text,
  renapa        text,                       -- registro nacional de productores apícolas
  moneda        text not null default 'ARS',
  dias_sin_visita_alerta int not null default 30,
  creada_por    uuid not null default auth.uid() references auth.users (id),
  creada_en     timestamptz not null default now()
);

create table public.miembros (
  explotacion_id uuid not null references public.explotaciones (id) on delete cascade,
  usuario_id     uuid not null references auth.users (id) on delete cascade,
  rol            text not null default 'asistente' check (rol in ('duenio', 'asistente', 'lectura')),
  agregado_en    timestamptz not null default now(),
  primary key (explotacion_id, usuario_id)
);
create index miembros_usuario_idx on public.miembros (usuario_id);

create table public.invitaciones (
  id             uuid primary key default gen_random_uuid(),
  explotacion_id uuid not null references public.explotaciones (id) on delete cascade,
  email          text not null,
  rol            text not null default 'asistente' check (rol in ('duenio', 'asistente', 'lectura')),
  creada_por     uuid default auth.uid() references auth.users (id),
  creada_en      timestamptz not null default now(),
  aceptada_en    timestamptz,
  unique (explotacion_id, email)
);

-- Funciones de autorización. SECURITY DEFINER evita la recursión de RLS al
-- consultar miembros desde las políticas de miembros.
create or replace function public.es_miembro(p_explotacion uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.miembros
    where explotacion_id = p_explotacion and usuario_id = auth.uid()
  );
$$;

create or replace function public.puede_editar(p_explotacion uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.miembros
    where explotacion_id = p_explotacion and usuario_id = auth.uid()
      and rol in ('duenio', 'asistente')
  );
$$;

create or replace function public.es_duenio(p_explotacion uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.miembros
    where explotacion_id = p_explotacion and usuario_id = auth.uid() and rol = 'duenio'
  );
$$;

-- Al registrarse un usuario: crear su perfil y aceptar invitaciones pendientes.
create or replace function public.al_crear_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.perfiles (id, nombre)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'nombre', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;

  insert into public.miembros (explotacion_id, usuario_id, rol)
  select explotacion_id, new.id, rol
  from public.invitaciones
  where lower(email) = lower(new.email) and aceptada_en is null
  on conflict do nothing;

  update public.invitaciones set aceptada_en = now()
  where lower(email) = lower(new.email) and aceptada_en is null;

  return new;
end $$;

create trigger t_al_crear_usuario
after insert on auth.users
for each row execute function public.al_crear_usuario();

-- Quien crea una explotación queda como dueño.
create or replace function public.al_crear_explotacion()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.miembros (explotacion_id, usuario_id, rol)
  values (new.id, new.creada_por, 'duenio')
  on conflict do nothing;
  return new;
end $$;

create trigger t_al_crear_explotacion
after insert on public.explotaciones
for each row execute function public.al_crear_explotacion();

-- -----------------------------------------------------------------------------
-- 2. Temporadas y apiarios
-- -----------------------------------------------------------------------------
create table public.temporadas (
  id             uuid primary key default gen_random_uuid(),
  explotacion_id uuid not null references public.explotaciones (id) on delete cascade,
  nombre         text not null,              -- "2026/2027"
  fecha_inicio   date not null,
  fecha_cierre   date,
  activa         boolean not null default true,
  notas          text,
  creada_en      timestamptz not null default now(),
  unique (explotacion_id, nombre),
  check (fecha_cierre is null or fecha_cierre >= fecha_inicio)
);
-- Una sola temporada activa por explotación.
create unique index temporadas_activa_unica on public.temporadas (explotacion_id) where activa;

create table public.apiarios (
  id               uuid primary key default gen_random_uuid(),
  explotacion_id   uuid not null references public.explotaciones (id) on delete cascade,
  nombre           text not null,
  capacidad_maxima int check (capacidad_maxima is null or capacidad_maxima >= 0),
  tipo             text check (tipo is null or tipo in ('fijo', 'trashumante')),
  modalidad        text check (modalidad is null or modalidad in ('propio', 'alquilado', 'compartido', 'comodato')),
  compartido_con   text,                     -- con quién se comparte el campo
  observaciones    text,
  lat              double precision check (lat is null or lat between -90 and 90),
  lng              double precision check (lng is null or lng between -180 and 180),
  perimetro        jsonb,                    -- [[lat,lng], [lat,lng], ...]
  foto_ruta        text,                     -- ruta dentro del bucket "fotos"
  activo           boolean not null default true,
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now(),
  unique (explotacion_id, nombre)
);

-- Apiario "cargado" a una temporada, con su cantidad de colmenas.
create table public.apiarios_temporada (
  id                      uuid primary key default gen_random_uuid(),
  explotacion_id          uuid not null references public.explotaciones (id) on delete cascade,
  apiario_id              uuid not null references public.apiarios (id) on delete cascade,
  temporada_id            uuid not null references public.temporadas (id) on delete cascade,
  colmenas_inicio         int not null default 0 check (colmenas_inicio >= 0),
  colmenas_actual         int not null default 0 check (colmenas_actual >= 0),
  nucleos_actual          int not null default 0 check (nucleos_actual >= 0),
  notas                   text,
  actualizado_en          timestamptz not null default now(),
  unique (apiario_id, temporada_id)
);

-- -----------------------------------------------------------------------------
-- 3. Trabajos y revisiones
-- -----------------------------------------------------------------------------
create table public.tipos_trabajo (
  id                uuid primary key default gen_random_uuid(),
  explotacion_id    uuid references public.explotaciones (id) on delete cascade, -- NULL = global
  clave             text not null,          -- identificador estable: 'alimentar'
  nombre            text not null,
  etiqueta_cantidad text,                   -- "Colmenas alimentadas"; NULL = no pide cantidad
  unidad_cantidad   text,                   -- 'colmenas', 'kg', 'alzas', 'reinas', 'cuadros', 'nucleos'
  campos_extra      jsonb not null default '[]'::jsonb, -- definición de datos adicionales
  orden             int not null default 100,
  activo            boolean not null default true,
  unique (explotacion_id, clave)
);
-- Las filas globales también deben tener clave única (NULL no participa en UNIQUE).
create unique index tipos_trabajo_global_clave on public.tipos_trabajo (clave) where explotacion_id is null;

create table public.revisiones (
  id                  uuid primary key default gen_random_uuid(),
  explotacion_id      uuid not null references public.explotaciones (id) on delete cascade,
  apiario_id          uuid not null references public.apiarios (id) on delete cascade,
  temporada_id        uuid references public.temporadas (id) on delete set null,
  fecha_trabajo       date not null default current_date,
  descripcion         text,
  recordatorio_texto  text check (recordatorio_texto is null or length(recordatorio_texto) <= 120),
  recordatorio_fecha  date,
  recordatorio_hecho  boolean not null default false,
  creada_por          uuid default auth.uid() references auth.users (id),
  creada_en           timestamptz not null default now(),
  actualizado_en      timestamptz not null default now()
);
create index revisiones_apiario_fecha_idx on public.revisiones (apiario_id, fecha_trabajo desc);
create index revisiones_explotacion_fecha_idx on public.revisiones (explotacion_id, fecha_trabajo desc);
create index revisiones_recordatorio_idx on public.revisiones (explotacion_id, recordatorio_fecha)
  where recordatorio_fecha is not null and not recordatorio_hecho;

create table public.revision_trabajos (
  id              uuid primary key default gen_random_uuid(),
  explotacion_id  uuid not null references public.explotaciones (id) on delete cascade,
  revision_id     uuid not null references public.revisiones (id) on delete cascade,
  tipo_trabajo_id uuid not null references public.tipos_trabajo (id),
  cantidad        numeric(12, 2) check (cantidad is null or cantidad >= 0),
  detalle         jsonb not null default '{}'::jsonb, -- producto, dosis, método, etc.
  unique (revision_id, tipo_trabajo_id)
);
create index revision_trabajos_tipo_idx on public.revision_trabajos (explotacion_id, tipo_trabajo_id);

create table public.revision_fotos (
  id             uuid primary key default gen_random_uuid(),
  explotacion_id uuid not null references public.explotaciones (id) on delete cascade,
  revision_id    uuid not null references public.revisiones (id) on delete cascade,
  ruta           text not null,             -- ruta dentro del bucket "fotos"
  orden          int not null default 0,
  subida_en      timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- 4. Colmenas individuales (opcional)
-- -----------------------------------------------------------------------------
create table public.colmenas (
  id             uuid primary key default gen_random_uuid(),
  explotacion_id uuid not null references public.explotaciones (id) on delete cascade,
  apiario_id     uuid references public.apiarios (id) on delete set null,
  codigo         text not null,             -- número o etiqueta
  origen         text check (origen is null or origen in ('compra', 'division', 'enjambre', 'traslado', 'otro')),
  fecha_alta     date not null default current_date,
  estado         text not null default 'activa'
                 check (estado in ('activa', 'muerta', 'vendida', 'trasladada', 'fusionada')),
  reina_anio     int check (reina_anio is null or reina_anio between 2000 and 2100),
  reina_origen   text,
  notas          text,
  actualizado_en timestamptz not null default now(),
  unique (explotacion_id, codigo)
);
create index colmenas_apiario_idx on public.colmenas (apiario_id);

create table public.colmena_eventos (
  id             uuid primary key default gen_random_uuid(),
  explotacion_id uuid not null references public.explotaciones (id) on delete cascade,
  colmena_id     uuid not null references public.colmenas (id) on delete cascade,
  revision_id    uuid references public.revisiones (id) on delete set null,
  fecha          date not null default current_date,
  tipo           text not null,             -- 'recambio_reina', 'traslado', 'muerte', 'division', 'nota'...
  detalle        text,
  creado_en      timestamptz not null default now()
);
create index colmena_eventos_colmena_idx on public.colmena_eventos (colmena_id, fecha desc);

-- -----------------------------------------------------------------------------
-- 5. Cosecha, tambores y ventas
-- -----------------------------------------------------------------------------
create table public.cosechas (
  id             uuid primary key default gen_random_uuid(),
  explotacion_id uuid not null references public.explotaciones (id) on delete cascade,
  apiario_id     uuid not null references public.apiarios (id) on delete cascade,
  temporada_id   uuid references public.temporadas (id) on delete set null,
  revision_id    uuid references public.revisiones (id) on delete set null,
  fecha          date not null default current_date,
  alzas          int check (alzas is null or alzas >= 0),
  kg_miel        numeric(10, 2) check (kg_miel is null or kg_miel >= 0),
  tipo_miel      text,
  observaciones  text,
  creada_en      timestamptz not null default now()
);
create index cosechas_temporada_idx on public.cosechas (explotacion_id, temporada_id);

create table public.ventas (
  id             uuid primary key default gen_random_uuid(),
  explotacion_id uuid not null references public.explotaciones (id) on delete cascade,
  temporada_id   uuid references public.temporadas (id) on delete set null,
  fecha          date not null default current_date,
  cliente        text,
  producto       text not null default 'miel',
  kg             numeric(10, 2) check (kg is null or kg >= 0),
  precio_kg      numeric(14, 2) check (precio_kg is null or precio_kg >= 0),
  total          numeric(14, 2) not null check (total >= 0),
  moneda         text not null default 'ARS',
  cotizacion_usd numeric(12, 2),            -- pesos por dólar el día de la venta
  cobrada        boolean not null default false,
  notas          text,
  creada_en      timestamptz not null default now()
);

create table public.tambores (
  id               uuid primary key default gen_random_uuid(),
  explotacion_id   uuid not null references public.explotaciones (id) on delete cascade,
  numero           text not null,
  temporada_id     uuid references public.temporadas (id) on delete set null,
  apiario_id       uuid references public.apiarios (id) on delete set null, -- NULL = mezcla
  fecha_llenado    date,
  kg_bruto         numeric(10, 2) check (kg_bruto is null or kg_bruto >= 0),
  tara             numeric(10, 2) check (tara is null or tara >= 0),
  kg_neto          numeric(10, 2) generated always as (greatest(coalesce(kg_bruto, 0) - coalesce(tara, 0), 0)) stored,
  tipo_miel        text,
  lote             text,
  estado           text not null default 'lleno'
                   check (estado in ('vacio', 'lleno', 'vendido', 'entregado')),
  venta_id         uuid references public.ventas (id) on delete set null,
  notas            text,
  actualizado_en   timestamptz not null default now(),
  unique (explotacion_id, numero, temporada_id)
);
create index tambores_estado_idx on public.tambores (explotacion_id, estado);

-- -----------------------------------------------------------------------------
-- 6. Contabilidad
-- -----------------------------------------------------------------------------
create table public.categorias_movimiento (
  id             uuid primary key default gen_random_uuid(),
  explotacion_id uuid references public.explotaciones (id) on delete cascade, -- NULL = global
  clave          text not null,
  nombre         text not null,
  tipo           text not null check (tipo in ('ingreso', 'egreso')),
  orden          int not null default 100,
  activa         boolean not null default true,
  unique (explotacion_id, clave)
);
create unique index categorias_global_clave on public.categorias_movimiento (clave) where explotacion_id is null;

create table public.movimientos (
  id               uuid primary key default gen_random_uuid(),
  explotacion_id   uuid not null references public.explotaciones (id) on delete cascade,
  temporada_id     uuid references public.temporadas (id) on delete set null,
  apiario_id       uuid references public.apiarios (id) on delete set null, -- NULL = gasto general
  venta_id         uuid references public.ventas (id) on delete cascade,
  fecha            date not null default current_date,
  tipo             text not null check (tipo in ('ingreso', 'egreso')),
  categoria_id     uuid not null references public.categorias_movimiento (id),
  descripcion      text,
  monto            numeric(14, 2) not null check (monto >= 0),
  moneda           text not null default 'ARS',
  cotizacion_usd   numeric(12, 2) check (cotizacion_usd is null or cotizacion_usd > 0),
  cantidad         numeric(12, 2),
  unidad           text,                    -- 'kg', 'l', 'unidades', 'km'...
  comprobante_ruta text,                    -- foto del ticket en el bucket "fotos"
  creado_por       uuid default auth.uid() references auth.users (id),
  creado_en        timestamptz not null default now(),
  actualizado_en   timestamptz not null default now()
);
create index movimientos_temporada_idx on public.movimientos (explotacion_id, temporada_id, fecha desc);
create index movimientos_apiario_idx on public.movimientos (apiario_id);

-- Al registrar una venta se crea (o actualiza) su movimiento de ingreso.
create or replace function public.sincronizar_movimiento_venta()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_categoria uuid;
begin
  select id into v_categoria
  from public.categorias_movimiento
  where explotacion_id is null and clave = case when new.producto = 'miel' then 'venta_miel' else 'otros_ingresos' end;

  if exists (select 1 from public.movimientos where venta_id = new.id) then
    update public.movimientos
       set fecha = new.fecha, monto = new.total, moneda = new.moneda,
           cotizacion_usd = new.cotizacion_usd, temporada_id = new.temporada_id,
           cantidad = new.kg, unidad = case when new.kg is not null then 'kg' end,
           descripcion = concat_ws(' · ', 'Venta', new.producto, new.cliente),
           actualizado_en = now()
     where venta_id = new.id;
  else
    insert into public.movimientos
      (explotacion_id, temporada_id, venta_id, fecha, tipo, categoria_id, descripcion,
       monto, moneda, cotizacion_usd, cantidad, unidad, creado_por)
    values
      (new.explotacion_id, new.temporada_id, new.id, new.fecha, 'ingreso', v_categoria,
       concat_ws(' · ', 'Venta', new.producto, new.cliente),
       new.total, new.moneda, new.cotizacion_usd, new.kg,
       case when new.kg is not null then 'kg' end, auth.uid());
  end if;
  return new;
end $$;

create trigger t_sincronizar_movimiento_venta
after insert or update on public.ventas
for each row execute function public.sincronizar_movimiento_venta();

-- Un tambor asociado a una venta pasa a "vendido"; si se desasocia, vuelve a "lleno".
create or replace function public.actualizar_estado_tambor()
returns trigger language plpgsql as $$
begin
  if new.venta_id is not null and new.estado in ('lleno', 'vacio') then
    new.estado := 'vendido';
  elsif new.venta_id is null and new.estado = 'vendido' then
    new.estado := 'lleno';
  end if;
  return new;
end $$;

create trigger t_actualizar_estado_tambor
before insert or update of venta_id on public.tambores
for each row execute function public.actualizar_estado_tambor();

-- -----------------------------------------------------------------------------
-- 7. Marca de actualización automática
-- -----------------------------------------------------------------------------
create or replace function public.marcar_actualizado()
returns trigger language plpgsql as $$
begin
  new.actualizado_en := now();
  return new;
end $$;

do $$
declare t text;
begin
  foreach t in array array['apiarios', 'apiarios_temporada', 'revisiones', 'colmenas',
                           'tambores', 'movimientos']
  loop
    execute format('create trigger t_actualizado before update on public.%I
                    for each row execute function public.marcar_actualizado()', t);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 8. Seguridad por fila (RLS)
-- -----------------------------------------------------------------------------
alter table public.perfiles enable row level security;
create policy perfiles_select on public.perfiles for select
  using (id = auth.uid()
         or exists (select 1 from public.miembros m1
                    join public.miembros m2 on m1.explotacion_id = m2.explotacion_id
                    where m1.usuario_id = auth.uid() and m2.usuario_id = perfiles.id));
create policy perfiles_update on public.perfiles for update
  using (id = auth.uid()) with check (id = auth.uid());

alter table public.explotaciones enable row level security;
create policy explotaciones_select on public.explotaciones for select using (public.es_miembro(id));
create policy explotaciones_insert on public.explotaciones for insert with check (creada_por = auth.uid());
create policy explotaciones_update on public.explotaciones for update
  using (public.es_duenio(id)) with check (public.es_duenio(id));
create policy explotaciones_delete on public.explotaciones for delete using (public.es_duenio(id));

alter table public.miembros enable row level security;
create policy miembros_select on public.miembros for select using (public.es_miembro(explotacion_id));
create policy miembros_insert on public.miembros for insert with check (public.es_duenio(explotacion_id));
create policy miembros_update on public.miembros for update
  using (public.es_duenio(explotacion_id)) with check (public.es_duenio(explotacion_id));
create policy miembros_delete on public.miembros for delete
  using (public.es_duenio(explotacion_id) or usuario_id = auth.uid()); -- uno puede irse

alter table public.invitaciones enable row level security;
create policy invitaciones_select on public.invitaciones for select using (public.es_miembro(explotacion_id));
create policy invitaciones_insert on public.invitaciones for insert with check (public.es_duenio(explotacion_id));
create policy invitaciones_delete on public.invitaciones for delete using (public.es_duenio(explotacion_id));

-- Tablas de datos: ver si es miembro, editar si es dueño o asistente.
do $$
declare t text;
begin
  foreach t in array array['temporadas', 'apiarios', 'apiarios_temporada', 'revisiones',
                           'revision_trabajos', 'revision_fotos', 'colmenas', 'colmena_eventos',
                           'cosechas', 'ventas', 'tambores', 'movimientos']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using (public.es_miembro(explotacion_id))', t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (public.puede_editar(explotacion_id))', t || '_insert', t);
    execute format('create policy %I on public.%I for update using (public.puede_editar(explotacion_id)) with check (public.puede_editar(explotacion_id))', t || '_update', t);
    execute format('create policy %I on public.%I for delete using (public.puede_editar(explotacion_id))', t || '_delete', t);
  end loop;
end $$;

-- Catálogos: las filas globales las ve todo usuario autenticado; las propias, sus miembros.
do $$
declare t text;
begin
  foreach t in array array['tipos_trabajo', 'categorias_movimiento']
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select using ((explotacion_id is null and auth.uid() is not null) or public.es_miembro(explotacion_id))', t || '_select', t);
    execute format('create policy %I on public.%I for insert with check (explotacion_id is not null and public.puede_editar(explotacion_id))', t || '_insert', t);
    execute format('create policy %I on public.%I for update using (explotacion_id is not null and public.puede_editar(explotacion_id)) with check (explotacion_id is not null and public.puede_editar(explotacion_id))', t || '_update', t);
    execute format('create policy %I on public.%I for delete using (explotacion_id is not null and public.puede_editar(explotacion_id))', t || '_delete', t);
  end loop;
end $$;

-- -----------------------------------------------------------------------------
-- 9. Vistas de consulta (respetan RLS del usuario que consulta)
-- -----------------------------------------------------------------------------
create view public.v_recordatorios with (security_invoker = true) as
select r.id as revision_id, r.explotacion_id, r.apiario_id, a.nombre as apiario,
       r.recordatorio_texto, r.recordatorio_fecha, r.fecha_trabajo,
       (r.recordatorio_fecha < current_date) as vencido
from public.revisiones r
join public.apiarios a on a.id = r.apiario_id
where r.recordatorio_fecha is not null and not r.recordatorio_hecho;

create view public.v_resultado with (security_invoker = true) as
select m.explotacion_id, m.temporada_id, m.apiario_id, m.categoria_id, c.nombre as categoria, m.tipo,
       sum(m.monto) as monto,
       sum(case when m.cotizacion_usd is not null then m.monto / m.cotizacion_usd end) as monto_usd
from public.movimientos m
join public.categorias_movimiento c on c.id = m.categoria_id
group by m.explotacion_id, m.temporada_id, m.apiario_id, m.categoria_id, c.nombre, m.tipo;

create view public.v_stock_miel with (security_invoker = true) as
select explotacion_id, temporada_id, apiario_id, estado,
       count(*) as tambores, sum(kg_neto) as kg
from public.tambores
group by explotacion_id, temporada_id, apiario_id, estado;

create view public.v_ultima_visita with (security_invoker = true) as
select a.explotacion_id, a.id as apiario_id, a.nombre,
       max(r.fecha_trabajo) as ultima_visita,
       (current_date - max(r.fecha_trabajo)) as dias_sin_visita
from public.apiarios a
left join public.revisiones r on r.apiario_id = a.id
where a.activo
group by a.explotacion_id, a.id, a.nombre;

-- -----------------------------------------------------------------------------
-- 10. Catálogos globales
-- -----------------------------------------------------------------------------
insert into public.tipos_trabajo (clave, nombre, etiqueta_cantidad, unidad_cantidad, campos_extra, orden) values
  ('alimentar',             'Alimentar',                    'Colmenas alimentadas',  'colmenas', '[{"clave":"alimento","etiqueta":"Alimento","tipo":"opcion","opciones":["jarabe","torta","sustituto polen","miel"]},{"clave":"cantidad_alimento","etiqueta":"Kg o litros","tipo":"numero"}]', 10),
  ('colmenas_muertas',      'Colmenas muertas',             'Colmenas muertas',      'colmenas', '[{"clave":"causa","etiqueta":"Causa probable","tipo":"texto"}]', 20),
  ('alza_melaria',          'Colocación de alza melaria',   'Alzas colocadas',       'alzas',    '[]', 30),
  ('control_enjambrazon',   'Control de enjambrazón',       'Colmenas controladas',  'colmenas', '[{"clave":"celdas_reales","etiqueta":"Colmenas con celdas reales","tipo":"numero"}]', 40),
  ('maduracion_miel',       'Control de maduración de miel','Colmenas controladas',  'colmenas', '[]', 50),
  ('control_reservas',      'Control de reservas',          'Colmenas controladas',  'colmenas', '[{"clave":"sin_reservas","etiqueta":"Colmenas sin reservas","tipo":"numero"}]', 60),
  ('cosecha',               'Cosecha',                      'Alzas retiradas',       'alzas',    '[{"clave":"kg_estimados","etiqueta":"Kg estimados","tipo":"numero"}]', 70),
  ('division',              'División de colmenas',         'Núcleos hechos',        'nucleos',  '[]', 80),
  ('ingreso_traslado',      'Ingreso por traslado',         'Colmenas ingresadas',   'colmenas', '[{"clave":"origen","etiqueta":"Apiario de origen","tipo":"texto"}]', 90),
  ('mantenimiento',         'Mantenimiento',                null,                    null,       '[]', 100),
  ('monitoreo_varroa',      'Monitoreo de varroa',          'Colmenas monitoreadas', 'colmenas', '[{"clave":"metodo","etiqueta":"Método","tipo":"opcion","opciones":["alcohol","azúcar","tablero","CO2"]},{"clave":"acaros_100","etiqueta":"Ácaros cada 100 abejas (promedio)","tipo":"numero"}]', 110),
  ('recambio_cuadros',      'Recambio de cuadros',          'Cuadros cambiados',     'cuadros',  '[]', 120),
  ('recambio_reinas',       'Recambio de reinas',           'Reinas cambiadas',      'reinas',   '[{"clave":"origen_reinas","etiqueta":"Origen de las reinas","tipo":"texto"}]', 130),
  ('reduccion_piquera',     'Reducción de piquera',         'Colmenas',              'colmenas', '[]', 140),
  ('revision',              'Revisión',                     'Colmenas revisadas',    'colmenas', '[]', 150),
  ('sanidad',               'Sanidad',                      'Colmenas tratadas',     'colmenas', '[{"clave":"producto","etiqueta":"Producto","tipo":"texto"},{"clave":"dosis","etiqueta":"Dosis","tipo":"texto"}]', 160),
  ('traslado',              'Traslado',                     'Colmenas trasladadas',  'colmenas', '[{"clave":"destino","etiqueta":"Apiario de destino","tipo":"texto"}]', 170),
  ('trasvasado',            'Trasvasado',                   'Colmenas trasvasadas',  'colmenas', '[]', 180),
  ('tratamiento_varroa',    'Tratamiento contra varroa',    'Colmenas tratadas',     'colmenas', '[{"clave":"producto","etiqueta":"Producto","tipo":"texto"},{"clave":"dosis","etiqueta":"Dosis","tipo":"texto"},{"clave":"retiro","etiqueta":"Fecha de retiro","tipo":"fecha"}]', 190);

insert into public.categorias_movimiento (clave, nombre, tipo, orden) values
  ('alimento',          'Alimento (azúcar, jarabe, tortas)',           'egreso', 10),
  ('sanidad',           'Sanidad y medicamentos',                      'egreso', 20),
  ('material',          'Material de colmena (cera, cuadros, alzas)',  'egreso', 30),
  ('reinas_nucleos',    'Reinas y núcleos',                            'egreso', 40),
  ('envases',           'Envases y tambores',                          'egreso', 50),
  ('combustible',       'Combustible y traslados',                     'egreso', 60),
  ('mano_obra',         'Mano de obra',                                'egreso', 70),
  ('campo',             'Alquiler de campo / comodato',                'egreso', 80),
  ('extraccion',        'Extracción y sala',                           'egreso', 90),
  ('impuestos',         'Impuestos y habilitaciones',                  'egreso', 100),
  ('herramientas',      'Herramientas e indumentaria',                 'egreso', 110),
  ('otros_egresos',     'Otros egresos',                               'egreso', 120),
  ('venta_miel',        'Venta de miel',                               'ingreso', 10),
  ('venta_nucleos',     'Venta de núcleos y colmenas',                 'ingreso', 20),
  ('venta_reinas',      'Venta de reinas',                             'ingreso', 30),
  ('polinizacion',      'Servicio de polinización',                    'ingreso', 40),
  ('cera_propoleos',    'Cera y propóleos',                            'ingreso', 50),
  ('otros_ingresos',    'Otros ingresos',                              'ingreso', 60);

-- -----------------------------------------------------------------------------
-- 11. Almacenamiento de fotos (bucket privado "fotos")
--     Ruta de cada archivo: <explotacion_id>/<carpeta>/<archivo>.jpg
--     La app pide URLs firmadas para mostrarlas.
-- -----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', false, 3145728, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy fotos_select on storage.objects for select
  using (bucket_id = 'fotos' and public.es_miembro(((storage.foldername(name))[1])::uuid));
create policy fotos_insert on storage.objects for insert
  with check (bucket_id = 'fotos' and public.puede_editar(((storage.foldername(name))[1])::uuid));
create policy fotos_update on storage.objects for update
  using (bucket_id = 'fotos' and public.puede_editar(((storage.foldername(name))[1])::uuid));
create policy fotos_delete on storage.objects for delete
  using (bucket_id = 'fotos' and public.puede_editar(((storage.foldername(name))[1])::uuid));

-- -----------------------------------------------------------------------------
-- 12. Función de arranque: crear explotación + primera temporada en un paso
-- -----------------------------------------------------------------------------
create or replace function public.crear_explotacion(p_nombre text, p_temporada text, p_inicio date default current_date)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  v_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Debe iniciar sesión';
  end if;
  insert into public.explotaciones (nombre, creada_por) values (p_nombre, auth.uid()) returning id into v_id;
  insert into public.temporadas (explotacion_id, nombre, fecha_inicio) values (v_id, p_temporada, p_inicio);
  return v_id;
end $$;

grant execute on function public.crear_explotacion(text, text, date) to authenticated;

-- Fin del esquema v1.
