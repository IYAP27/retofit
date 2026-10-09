-- RetoFit V5. Ejecutar una sola vez tras migracion_v4.sql. Conserva todos los datos.
create table if not exists public.app_notifications (
 id uuid primary key default gen_random_uuid(),
 recipient_id uuid not null references public.profiles(id) on delete cascade,
 kind text not null check (kind in ('reply','leader')),
 body text not null check (char_length(body) <= 250),
 challenge_id uuid references public.challenges(id) on delete cascade,
 read_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists app_notifications_recipient_idx on public.app_notifications(recipient_id,created_at desc);
alter table public.app_notifications enable row level security;
drop policy if exists notif_read_own_v5 on public.app_notifications;
create policy notif_read_own_v5 on public.app_notifications for select to authenticated using (recipient_id=(select auth.uid()));
drop policy if exists notif_update_own_v5 on public.app_notifications;
create policy notif_update_own_v5 on public.app_notifications for update to authenticated using (recipient_id=(select auth.uid())) with check (recipient_id=(select auth.uid()));
-- No INSERT/DELETE al cliente: las notificaciones se generan solo por triggers.

create table if not exists public.challenge_events (
 id uuid primary key default gen_random_uuid(),
 challenge_id uuid not null references public.challenges(id) on delete cascade,
 kind text not null check (kind='new_leader'),
 body text not null check (char_length(body)<=250),
 created_at timestamptz not null default now()
);
create index if not exists challenge_events_challenge_idx on public.challenge_events(challenge_id,created_at desc);
alter table public.challenge_events enable row level security;
drop policy if exists challenge_events_member_v5 on public.challenge_events;
create policy challenge_events_member_v5 on public.challenge_events for select to authenticated using (public.is_member(challenge_id));

create or replace function public.retofit_v5_reply_notification() returns trigger
language plpgsql security definer set search_path='' as $$
declare target_user uuid; sender_name text; target_challenge uuid := null;
begin
 if new.reply_to is null then return new; end if;
 if tg_table_name='general_messages' then
   select user_id into target_user from public.general_messages where id=new.reply_to;
 elsif tg_table_name='messages' then
   select user_id into target_user from public.messages where id=new.reply_to and challenge_id=new.challenge_id;
   target_challenge := new.challenge_id;
 else
   return new;
 end if;
 if target_user is null or target_user=new.user_id then return new; end if;
 select username into sender_name from public.profiles where id=new.user_id;
 insert into public.app_notifications(recipient_id,kind,body,challenge_id)
 values(target_user,'reply',coalesce(sender_name,'Alguien')||' respondió a tu mensaje',target_challenge);
 return new;
end;$$;
drop trigger if exists retofit_reply_general_v5 on public.general_messages;
create trigger retofit_reply_general_v5 after insert on public.general_messages for each row execute function public.retofit_v5_reply_notification();
drop trigger if exists retofit_reply_challenge_v5 on public.messages;
create trigger retofit_reply_challenge_v5 after insert on public.messages for each row execute function public.retofit_v5_reply_notification();

-- Notifica solo al producirse un cambio REAL de líder, evitando avisos en cada registro.
create or replace function public.retofit_v5_leader_event() returns trigger
language plpgsql security definer set search_path='' as $$
declare previous_leader uuid; updated_leader uuid; leader_name text; challenge_title text;
begin
 if not exists(select 1 from public.challenges where id=new.challenge_id and starts_at<=now() and ends_at>=now()) then return new; end if;
 with totals as (
  select cm.user_id,coalesce(sum(p.quantity),0) as score
  from public.challenge_members cm left join public.pushups p
   on p.challenge_id=cm.challenge_id and p.user_id=cm.user_id and p.id<>new.id
  where cm.challenge_id=new.challenge_id group by cm.user_id
 ) select user_id into previous_leader from totals order by score desc,user_id limit 1;
 with totals as (
  select cm.user_id,coalesce(sum(p.quantity),0) as score
  from public.challenge_members cm left join public.pushups p
   on p.challenge_id=cm.challenge_id and p.user_id=cm.user_id
  where cm.challenge_id=new.challenge_id group by cm.user_id
 ) select user_id into updated_leader from totals order by score desc,user_id limit 1;
 if updated_leader is distinct from previous_leader and updated_leader=new.user_id then
   select username into leader_name from public.profiles where id=new.user_id;
   select title into challenge_title from public.challenges where id=new.challenge_id;
   insert into public.challenge_events(challenge_id,kind,body)
    values(new.challenge_id,'new_leader','🏆 ¡'||coalesce(leader_name,'Un participante')||' tomó el liderato de '||coalesce(challenge_title,'un reto')||'!');
   insert into public.app_notifications(recipient_id,kind,body,challenge_id)
    select cm.user_id,'leader','🏆 ¡'||coalesce(leader_name,'Alguien')||' es el nuevo líder de '||coalesce(challenge_title,'tu reto')||'!',new.challenge_id
    from public.challenge_members cm where cm.challenge_id=new.challenge_id and cm.user_id<>new.user_id;
 end if;
 return new;
end;$$;
drop trigger if exists retofit_pushup_leader_v5 on public.pushups;
create trigger retofit_pushup_leader_v5 after insert on public.pushups for each row execute function public.retofit_v5_leader_event();

-- Se habilita realtime únicamente en las tablas nuevas.
do $$ begin
 if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='app_notifications') then
  alter publication supabase_realtime add table public.app_notifications;
 end if;
 if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='challenge_events') then
  alter publication supabase_realtime add table public.challenge_events;
 end if;
end $$;
-- El cliente solo puede marcar como leídas sus notificaciones, no cambiar el contenido.
revoke update on public.app_notifications from authenticated;
grant update(read_at) on public.app_notifications to authenticated;
