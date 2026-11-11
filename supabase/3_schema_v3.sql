-- شغّله بعد 1 و 2: تنبيهات، تحكم في المضخة، مدفوعات، لوحة إدارة، صيانة
alter table devices add column low_threshold float not null default 30, add column high_threshold float not null default 40,
  add column last_alert_at timestamptz, add column offline_alert_at timestamptz;

create table user_settings(user_id uuid primary key default auth.uid() references auth.users on delete cascade, telegram_chat_id text);
alter table user_settings enable row level security;
create policy us_own on user_settings for all using(user_id=auth.uid()) with check(user_id=auth.uid());

-- ===== المضخة =====
create table pump_commands(id bigint generated always as identity primary key,
  device_id uuid not null references devices on delete cascade,
  action text not null check(action in('on','off')), minutes int check(minutes between 1 and 60),
  status text not null default 'pending' check(status in('pending','sent','done')), created_at timestamptz default now());
alter table pump_commands enable row level security;
create policy pc_read on pump_commands for select using(exists(select 1 from devices d join farms f on f.id=d.farm_id where d.id=device_id and f.owner=auth.uid()));

create function send_pump_command(p_device uuid,p_action text,p_minutes int default 15) returns void
language plpgsql security definer set search_path=public as $$
begin
  if not exists(select 1 from devices d join farms f on f.id=d.farm_id where d.id=p_device and f.owner=auth.uid()) then raise exception 'غير مسموح'; end if;
  if eff_plan(auth.uid())='free' then raise exception 'التحكم في المضخة متاح في الخطط المدفوعة'; end if;
  update pump_commands set status='done' where device_id=p_device and status in('pending','sent');
  insert into pump_commands(device_id,action,minutes) values(p_device,p_action,least(greatest(coalesce(p_minutes,15),1),60));
end $$;

create function poll_command(p_key text) returns table(cmd_id bigint,cmd_action text,cmd_minutes int)
language plpgsql security definer set search_path=public as $$
declare did uuid;
begin
  select d.id into did from devices d where d.api_key=p_key;
  if did is null then raise exception 'invalid device key'; end if;
  return query update pump_commands c set status='sent'
    where c.id=(select c2.id from pump_commands c2 where c2.device_id=did and c2.status='pending'
                and c2.created_at>now()-interval '10 minutes' order by c2.id desc limit 1)
    returning c.id,c.action,c.minutes;
end $$;

create function ack_command(p_key text,p_id bigint) returns void
language sql security definer set search_path=public as $$
  update pump_commands set status='done' where id=p_id and device_id=(select id from devices where api_key=p_key) $$;

-- ===== المدفوعات =====
create table orders(id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users on delete cascade,
  plan text not null check(plan in('pro','business')), amount_egp int not null,
  status text not null default 'pending' check(status in('pending','paid','failed')),
  provider_ref text, created_at timestamptz default now());
alter table orders enable row level security;
create policy ord_read on orders for select using(user_id=auth.uid());

create function activate_plan(p_user uuid,p_plan text,p_days int) returns void
language sql security definer set search_path=public as $$
  insert into subscriptions(user_id,plan,expires_at) values(p_user,p_plan,now()+make_interval(days=>p_days))
  on conflict(user_id) do update set plan=excluded.plan, updated_at=now(),
    expires_at=(case when subscriptions.plan=excluded.plan and subscriptions.expires_at>now() then subscriptions.expires_at else now() end)+make_interval(days=>p_days) $$;

-- ===== الإدارة =====
create table admins(user_id uuid primary key references auth.users on delete cascade);
alter table admins enable row level security;
create function is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from admins where user_id=auth.uid()) $$;

create function admin_overview() returns table(u_email text,u_plan text,u_expires timestamptz,u_farms bigint,u_devices bigint,u_last timestamptz)
language plpgsql security definer set search_path=public as $$
begin
  if not is_admin() then raise exception 'غير مسموح'; end if;
  return query select u.email::text, coalesce(s.plan,'free'), s.expires_at,
    (select count(*) from farms f where f.owner=u.id),
    (select count(*) from devices d join farms f on f.id=d.farm_id where f.owner=u.id),
    (select max(r.ts) from readings r join devices d on d.id=r.device_id join farms f on f.id=d.farm_id where f.owner=u.id)
  from auth.users u left join subscriptions s on s.user_id=u.id order by u.created_at desc;
end $$;

create function admin_set_plan(p_email text,p_plan text,p_days int) returns void
language plpgsql security definer set search_path=public as $$
declare uid uuid;
begin
  if not is_admin() then raise exception 'غير مسموح'; end if;
  select id into uid from auth.users where email=p_email;
  if uid is null then raise exception 'العميل غير موجود'; end if;
  perform activate_plan(uid,p_plan,p_days);
end $$;

-- ===== للتنبيهات (service role فقط) =====
create function devices_status() returns table(device_id uuid,device_name text,farm_name text,chat text,low_threshold float,
  last_alert_at timestamptz,offline_alert_at timestamptz,last_ts timestamptz,last_moisture float)
language sql security definer set search_path=public as $$
  select d.id,d.name,f.name,us.telegram_chat_id,d.low_threshold,d.last_alert_at,d.offline_alert_at,lr.ts,lr.moisture
  from devices d join farms f on f.id=d.farm_id join user_settings us on us.user_id=f.owner
  left join lateral (select r.ts,r.moisture from readings r where r.device_id=d.id order by r.ts desc limit 1) lr on true
  where coalesce(us.telegram_chat_id,'')<>'' $$;

-- ===== الصلاحيات: الدوال الحساسة مقفولة =====
revoke all on function activate_plan, devices_status, eff_plan, handle_new_user, check_farm_limit, check_device_limit from public, anon, authenticated;
revoke all on function send_pump_command, is_admin, admin_overview, admin_set_plan from public, anon;
grant execute on function send_pump_command, is_admin, admin_overview, admin_set_plan to authenticated;
revoke all on function poll_command, ack_command from public;
grant execute on function poll_command, ack_command to anon, authenticated;

-- ===== الجدولة: فعّل pg_cron و pg_net من Database > Extensions ثم شغّل (بدّل القيم) =====
-- select cron.schedule('agromind-alerts','*/10 * * * *',$$select net.http_post(
--   url:='https://PROJECT_REF.supabase.co/functions/v1/check-alerts',
--   headers:='{"Authorization":"Bearer SERVICE_ROLE_KEY"}'::jsonb)$$);
-- select cron.schedule('prune-readings','0 3 * * *',$$delete from readings where ts<now()-interval '180 days'$$);
-- أول أدمن (إيميلك بعد ما تسجل في التطبيق):
-- insert into admins select id from auth.users where email='you@example.com';
