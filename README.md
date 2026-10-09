# RetoFit — MVP de retos de lagartijas

Web React + Vite + Supabase con registro/login, retos privados por código, múltiples registros diarios, ranking, gráficas personales y generales, chat general y chat por reto e historial de competencias concluidas.

## Puesta en marcha

1. Instala Node.js LTS (20.19+ o 22.12+ recomendado para Vite 6).
2. Crea un proyecto en https://supabase.com/dashboard.
3. Abre **SQL Editor**, copia `supabase/schema.sql` y ejecútalo en un proyecto vacío. No uses esta migración directamente en bases de datos con tablas del mismo nombre.
4. En **Project Settings > API** (o *Connect* según la versión), copia **Project URL** y la **publishable key / anon key**. Nunca pongas la `service_role` en el cliente.
5. Copia `.env.example` como `.env` y reemplaza ambos valores.
6. En esta carpeta, ejecuta:
   ```bash
   npm install
   npm run dev
   ```
7. Abre la dirección local que muestra Vite. Crea dos cuentas diferentes para probar ranking y chat. Si Supabase exige confirmar correo, revisa el enlace de confirmación o configura Auth > Providers > Email.
8. Para publicar: sube el proyecto a GitHub y usa Vercel, configurando las mismas dos variables de entorno `VITE_*` en Vercel. Añade el dominio publicado a **Authentication > URL Configuration** como Redirect URL y Site URL en Supabase.

## Decisiones de la primera versión

- Todos los retos son privados por código. Cualquier usuario autenticado puede crear retos.
- El reto comienza al crearse; dura exactamente 7/14/30 días desde ese instante. La pantalla agrupa registros por fecha local del dispositivo.
- Cada reto tiene su propio chat. Reacciones, notificaciones, invitaciones con enlaces y PWA instalable serán parte de la segunda iteración.
- El historial muestra retos terminados y conserva las puntuaciones, pero no genera premios ni badges.
- Los registros pueden borrarse por su autor mientras el reto esté activo. No hay prevención de trampas ni verificación física.
- El chat carga los 200 mensajes más antiguos actualmente; para producción se debe implementar paginación trayendo los 200 más recientes e historial anterior.
- La UI recarga los datos al recibir eventos realtime. Para muchos usuarios convendría usar actualizaciones incrementales.

## Seguridad

Las reglas de acceso RLS permiten leer registros y chat solo si el usuario es participante, e insertar únicamente con su propio `auth.uid()`. Los códigos son aleatorios. Las funciones de creación y unión corren en una transacción y validan sus parámetros. La clave `anon`/`publishable` es pública y depende de RLS; la clave `service_role` jamás se debe poner en `.env` del navegador.

## Mejoras sugeridas

Chat general, actualizaciones instantáneas locales tras enviar (optimistic UI), grupos de amigos, tipos de ejercicio, retos programados, ajustes de zona horaria del reto, perfiles más completos, medallas y PWA.
