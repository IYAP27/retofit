-- Ejecutar SOLO UNA VEZ en el SQL Editor del proyecto existente.
-- Conserva todas las cuentas, retos y mensajes anteriores.
alter table public.general_messages add column if not exists reply_to uuid references public.general_messages(id) on delete set null;
alter table public.messages add column if not exists reply_to uuid references public.messages(id) on delete set null;
create table if not exists public.chat_reactions (
 id uuid primary key default gen_random_uuid(),
 scope text not null check(scope in ('general','reto')),
 message_id uuid not null,
 user_id uuid not null references public.profiles(id) on delete cascade,
 emoji text not null check(emoji in ('👍','❤️','😂','🔥','💪','🏆')),
 created_at timestamptz not null default now(),
 unique(scope,message_id,user_id,emoji)
);
create index if not exists chat_reactions_lookup on public.chat_reactions(scope,message_id);
alter table public.chat_reactions enable row level security;
-- Los chats privados se mantienen privados incluso en las reacciones.
create policy chat_reactions_read on public.chat_reactions for select to authenticated using (
 (scope='general' and exists(select 1 from public.general_messages m where m.id=message_id)) or
 (scope='reto' and exists(select 1 from public.messages m where m.id=message_id and public.is_member(m.challenge_id)))
);
create policy chat_reactions_insert on public.chat_reactions for insert to authenticated with check (
 user_id=(select auth.uid()) and (
 (scope='general' and exists(select 1 from public.general_messages m where m.id=message_id)) or
 (scope='reto' and exists(select 1 from public.messages m where m.id=message_id and public.is_member(m.challenge_id)))
 ));
create policy chat_reactions_delete on public.chat_reactions for delete to authenticated using (user_id=(select auth.uid()));
-- Previene respuestas cruzadas entre retos y respuestas a mensajes invisibles.
create or replace function public.validate_chat_reply() returns trigger language plpgsql security invoker set search_path=public as $$
begin
 if new.reply_to is null then return new; end if;
 if tg_table_name='messages' then
  if not exists(select 1 from public.messages m where m.id=new.reply_to and m.challenge_id=new.challenge_id) then
   raise exception 'La respuesta debe pertenecer al mismo reto';
  end if;
 end if;
 return new;
end; $$;
drop trigger if exists validate_challenge_reply on public.messages;
create trigger validate_challenge_reply before insert or update of reply_to on public.messages for each row execute function public.validate_chat_reply();
do $$ begin
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='chat_reactions') then
  alter publication supabase_realtime add table public.chat_reactions;
 end if;
end $$;
