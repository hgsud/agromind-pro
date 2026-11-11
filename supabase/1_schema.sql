-- AgroMind: شغّل الملف ده كله مرة واحدة في Supabase > SQL Editor
create extension if not exists pgcrypto;

create table farms(
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references auth.users on delete cascade,
  name text not null, lat float, crop text, soil text,
  created_at timestamptz default now());

create table devices(
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references farms on delete cascade,
  name text not null,
  api_key text not null unique default encode(gen_random_bytes(16),'hex'),
  created_at timestamptz default now());

create table readings(
  id bigint generated always as identity primary key,
  device_id uuid not null references devices on delete cascade,
  ts timestamptz not null default now(),
  moisture float, temp float, rh float, ec float);
create index on readings(device_id, ts desc);

alter table farms enable row level security;
alter table devices enable row level security;
alter table readings enable row level security;

create policy farms_own on farms for all using (owner=auth.uid()) with check (owner=auth.uid());
create policy dev_own on devices for all
  using (exists(select 1 from farms f where f.id=farm_id and f.owner=auth.uid()))
  with check (exists(select 1 from farms f where f.id=farm_id and f.owner=auth.uid()));
create policy read_own on readings for select
  using (exists(select 1 from devices d join farms f on f.id=d.farm_id where d.id=device_id and f.owner=auth.uid()));

-- الجهاز (ESP32) بيكتب عن طريق الدالة دي فقط، بمفتاح الجهاز، من غير تسجيل دخول
create or replace function ingest_reading(p_key text, p_moisture float, p_temp float, p_rh float, p_ec float default null)
returns void language plpgsql security definer set search_path=public as $$
declare did uuid;
begin
  select id into did from devices where api_key=p_key;
  if did is null then raise exception 'invalid device key'; end if;
  if p_moisture<0 or p_moisture>100 then raise exception 'moisture out of range'; end if;
  insert into readings(device_id,moisture,temp,rh,ec) values(did,p_moisture,p_temp,p_rh,p_ec);
end $$;
revoke all on function ingest_reading from public;
grant execute on function ingest_reading to anon, authenticated;
