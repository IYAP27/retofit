-- RetoFit V5.1: reparar respuestas del chat general sin borrar datos.
-- Ejecutar en Supabase SQL Editor luego de haber aplicado migracion_v5.sql.
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
