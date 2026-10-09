-- RetoFit V4. Ejecutar DESPUÉS del schema.sql y de migracion_v3.sql.
-- No borra usuarios, mensajes, retos ni registros.
alter table public.profiles add column if not exists bio text not null default '' check (char_length(bio)<=160);
alter table public.profiles add column if not exists avatar_emoji text not null default '💪' check (avatar_emoji in ('💪','🔥','🏆','😎','🦁','🐺','⚡','🥊','🚀','⭐'));
drop policy if exists profile_update_own_v4 on public.profiles;
create policy profile_update_own_v4 on public.profiles for update to authenticated using (id=(select auth.uid())) with check (id=(select auth.uid()));

-- Devuelve exclusivamente resultados de retos finalizados donde el usuario es participante.
-- El resultado se computa a partir de datos ya almacenados (no permite alterar ganadores).
create or replace function public.retofit_hall_of_fame()
returns table(challenge_id uuid, challenge_title text, ends_at timestamptz, winner_id uuid, winner_name text, winner_total bigint)
language sql stable security invoker set search_path='' as $$
 with eligible as (
   select c.id,c.title,c.ends_at
   from public.challenges c
   where c.ends_at<=now() and public.is_member(c.id)
 ), totals as (
   select e.id as cid, cm.user_id, coalesce(sum(p.quantity),0)::bigint as score
   from eligible e join public.challenge_members cm on cm.challenge_id=e.id
   left join public.pushups p on p.challenge_id=e.id and p.user_id=cm.user_id
   group by e.id,cm.user_id
 ), winners as (
   select t.*,row_number() over(partition by t.cid order by t.score desc,t.user_id) as pos from totals t
 )
 select e.id,e.title,e.ends_at,w.user_id,pr.username,w.score
 from eligible e left join winners w on w.cid=e.id and w.pos=1
 left join public.profiles pr on pr.id=w.user_id
 order by e.ends_at desc;
$$;
revoke all on function public.retofit_hall_of_fame() from public;
grant execute on function public.retofit_hall_of_fame() to authenticated;
