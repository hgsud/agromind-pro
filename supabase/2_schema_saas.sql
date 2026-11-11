-- شغّله بعد schema.sql: خطط الاشتراك وحدودها (بتتفرض من قاعدة البيانات نفسها مش من الواجهة)
create table subscriptions(
  user_id uuid primary key references auth.users on delete cascade,
  plan text not null default 'free' check (plan in ('free','pro','business')),
  expires_at timestamptz, updated_at timestamptz default now());
alter table subscriptions enable row level security;
create policy sub_read on subscriptions for select using (user_id=auth.uid());  -- العميل يقرأ فقط، التعديل من عندك

create function handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into subscriptions(user_id) values(new.id) on conflict do nothing; return new; end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function handle_new_user();
insert into subscriptions(user_id) select id from auth.users on conflict do nothing;

create function eff_plan(p_user uuid) returns text language sql stable security definer set search_path=public as $$
  select coalesce((select case when plan='free' or expires_at>now() then plan else 'free' end
                   from subscriptions where user_id=p_user),'free') $$;

create function check_farm_limit() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if (select count(*) from farms where owner=new.owner) >=
     case eff_plan(new.owner) when 'business' then 50 when 'pro' then 5 else 1 end
  then raise exception 'وصلت للحد الأقصى للمزارع في خطتك. رقّي الخطة.'; end if;
  return new; end $$;
create trigger farm_limit before insert on farms for each row execute function check_farm_limit();

create function check_device_limit() returns trigger language plpgsql security definer set search_path=public as $$
declare o uuid;
begin
  select owner into o from farms where id=new.farm_id;
  if (select count(*) from devices d join farms f on f.id=d.farm_id where f.owner=o) >=
     case eff_plan(o) when 'business' then 200 when 'pro' then 20 else 1 end
  then raise exception 'وصلت للحد الأقصى للأجهزة في خطتك. رقّي الخطة.'; end if;
  return new; end $$;
create trigger device_limit before insert on devices for each row execute function check_device_limit();

-- ترقية عميل بعد ما يدفع (من SQL Editor):
-- update subscriptions set plan='pro', expires_at=now()+interval '30 days'
--   where user_id=(select id from auth.users where email='client@example.com');
