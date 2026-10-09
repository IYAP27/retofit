-- Ejecutar en Supabase > SQL Editor, una vez en un proyecto nuevo.
create extension if not exists pgcrypto;

create table public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 username text not null check (char_length(username) between 3 and 30),
 created_at timestamptz not null default now()
);
create unique index profiles_username_unique on public.profiles(lower(username));
create table public.challenges (
 id uuid primary key default gen_random_uuid(),
 title text not null check(char_length(title) between 3 and 80),
 creator_id uuid not null references public.profiles(id),
 join_code text not null unique default upper(encode(gen_random_bytes(4),'hex')),
 duration_days integer not null check(duration_days in (7,14,30)),
 starts_at timestamptz not null default now(),
 ends_at timestamptz not null,
 created_at timestamptz not null default now(),
 check (ends_at>starts_at)
);
create table public.challenge_members (
 challenge_id uuid not null references public.challenges(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 joined_at timestamptz not null default now(),
 primary key(challenge_id,user_id)
);
create table public.pushups (
 id uuid primary key default gen_random_uuid(),
 challenge_id uuid not null references public.challenges(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 quantity integer not null check(quantity between 1 and 10000),
 created_at timestamptz not null default now()
);
create index pushups_challenge_idx on public.pushups(challenge_id,created_at);
create table public.messages (
 id uuid primary key default gen_random_uuid(),
 challenge_id uuid not null references public.challenges(id) on delete cascade,
 user_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 1000),
 created_at timestamptz not null default now()
);
create index messages_challenge_idx on public.messages(challenge_id,created_at);

-- Crear el perfil automáticamente a partir de Auth.
create or replace function public.new_user_profile() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,username) values(new.id,coalesce(nullif(left(trim(new.raw_user_meta_data->>'username'),30),''),'User-'||left(new.id::text,8)));
 return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.new_user_profile();

-- Helpers SECURITY DEFINER para evitar políticas circulares en las tablas de participantes.
create or replace function public.is_member(c uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.challenge_members where challenge_id=c and user_id=(select auth.uid()));
$$;
create or replace function public.owns_challenge(c uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.challenges where id=c and creator_id=(select auth.uid()));
$$;
revoke all on function public.is_member(uuid),public.owns_challenge(uuid) from public;
grant execute on function public.is_member(uuid),public.owns_challenge(uuid) to authenticated;

-- RPC transaccional: el creador entra como primer participante.
create or replace function public.create_challenge(p_title text,p_days integer) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise exception 'Inicia sesión'; end if;
 if char_length(trim(p_title)) not between 3 and 80 or p_days not in(7,14,30) then raise exception 'Datos de reto inválidos'; end if;
 insert into public.challenges(title,creator_id,duration_days,starts_at,ends_at)
 values(trim(p_title),auth.uid(),p_days,now(),now()+make_interval(days=>p_days)) returning id into cid;
 insert into public.challenge_members(challenge_id,user_id) values(cid,auth.uid());
 return cid;
end; $$;
create or replace function public.join_challenge(p_code text) returns uuid language plpgsql security definer set search_path='' as $$
declare cid uuid;
begin
 if auth.uid() is null then raise exception 'Inicia sesión'; end if;
 select id into cid from public.challenges where join_code=upper(trim(p_code)) and ends_at>now();
 if cid is null then raise exception 'Código inválido o reto finalizado'; end if;
 insert into public.challenge_members(challenge_id,user_id) values(cid,auth.uid()) on conflict do nothing;
 return cid;
end; $$;
revoke all on function public.create_challenge(text,integer),public.join_challenge(text) from public;
grant execute on function public.create_challenge(text,integer),public.join_challenge(text) to authenticated;

alter table public.profiles enable row level security;
alter table public.challenges enable row level security;
alter table public.challenge_members enable row level security;
alter table public.pushups enable row level security;
alter table public.messages enable row level security;
create policy profile_read on public.profiles for select to authenticated using(true);
create policy challenge_read on public.challenges for select to authenticated using(public.is_member(id));
create policy member_read on public.challenge_members for select to authenticated using(public.is_member(challenge_id));
create policy pushup_read on public.pushups for select to authenticated using(public.is_member(challenge_id));
create policy pushup_add on public.pushups for insert to authenticated with check(
 user_id=(select auth.uid()) and public.is_member(challenge_id)
 and exists(select 1 from public.challenges c where c.id=challenge_id and now() between c.starts_at and c.ends_at)
);
create policy pushup_delete on public.pushups for delete to authenticated using(
 user_id=(select auth.uid()) and public.is_member(challenge_id)
 and exists(select 1 from public.challenges c where c.id=challenge_id and now()<c.ends_at)
);
create policy message_read on public.messages for select to authenticated using(public.is_member(challenge_id));
create policy message_add on public.messages for insert to authenticated with check(
 user_id=(select auth.uid()) and public.is_member(challenge_id)
 and exists(select 1 from public.challenges c where c.id=challenge_id and now()<c.ends_at)
);
-- Supabase Realtime escucha cambios; las políticas RLS siguen rigiendo visibilidad.
alter publication supabase_realtime add table public.pushups;
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.challenge_members;

-- Chat general para todos los usuarios autenticados.
create table public.general_messages (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references public.profiles(id) on delete cascade,
 body text not null check(char_length(trim(body)) between 1 and 1000),
 created_at timestamptz not null default now()
);
create index general_messages_created_idx on public.general_messages(created_at);
alter table public.general_messages enable row level security;
create policy general_message_read on public.general_messages for select to authenticated using(true);
create policy general_message_add on public.general_messages for insert to authenticated with check(user_id=(select auth.uid()));
alter publication supabase_realtime add table public.general_messages;
