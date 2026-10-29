-- Ejecutar únicamente en la base de datos de desarrollo del proyecto.
BEGIN;
CREATE TABLE IF NOT EXISTS public.favorito_casino (
  usuario_id INTEGER NOT NULL REFERENCES public.usuario(id) ON DELETE CASCADE,
  juego_casino_id INTEGER NOT NULL REFERENCES public.juego_casino(id) ON DELETE CASCADE,
  fecha_agregado TIMESTAMP DEFAULT NOW(),
  PRIMARY KEY (usuario_id, juego_casino_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS favorito_casino_usuario_juego_unique
  ON public.favorito_casino(usuario_id, juego_casino_id);
-- El JWT de NestJS no es una sesión Supabase Auth. El backend aplica el
-- aislamiento por usuario y usa su clave privada service_role.
ALTER TABLE public.favorito_casino DISABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, DELETE ON TABLE public.favorito_casino TO anon, authenticated, service_role;
COMMIT;
