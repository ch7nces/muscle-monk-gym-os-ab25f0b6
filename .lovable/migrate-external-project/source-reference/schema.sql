
-- ===== ENUMS =====
create type public.app_role as enum ('super_admin','owner','manager','receptionist','trainer','member');
create type public.lead_stage as enum ('new','contacted','trial_scheduled','trial_completed','follow_up','converted','lost');
create type public.lead_source as enum ('website','google_search','google_maps','instagram','facebook','whatsapp','walk_in','referral','other');
create type public.payment_method as enum ('cash','upi','bank_transfer','online','other');
create type public.checkin_method as enum ('reception_scan','entrance_qr','manual');

create or replace function public.touch_updated_at() returns trigger language plpgsql set search_path=public as $$
begin new.updated_at = now(); return new; end $$;

-- ===== GYMS (tenants) =====
create table public.gyms (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique check (slug ~ '^[a-z0-9-]{2,60}$'),
  name text not null,
  name_hi text,
  phone text, whatsapp text, email text,
  address text, city text, state text, postal_code text, country text default 'India',
  latitude numeric, longitude numeric,
  timezone text not null default 'Asia/Kolkata',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select on public.gyms to anon, authenticated;
grant update on public.gyms to authenticated;
grant all on public.gyms to service_role;
alter table public.gyms enable row level security;
create trigger gyms_touch before update on public.gyms for each row execute function public.touch_updated_at();

create table public.gym_settings (
  gym_id uuid primary key references public.gyms(id) on delete cascade,
  hours jsonb not null default '[]'::jsonb,
  about_text text,
  hero_subtitle text,
  checkin_cooldown_minutes int not null default 240 check (checkin_cooldown_minutes between 1 and 1440),
  expiring_soon_days int not null default 7 check (expiring_soon_days between 1 and 60),
  inactive_days int not null default 7 check (inactive_days between 1 and 90),
  entrance_qr_ttl_seconds int not null default 30 check (entrance_qr_ttl_seconds between 10 and 300),
  trial_slots jsonb not null default '["06:00-08:00","08:00-10:00","17:00-19:00","19:00-21:00"]'::jsonb,
  trial_slot_capacity int not null default 5 check (trial_slot_capacity between 1 and 100),
  tax_enabled boolean not null default false,
  tax_label text,
  tax_rate numeric(5,2) not null default 0 check (tax_rate between 0 and 50),
  google_rating numeric(2,1),
  google_review_count int,
  updated_at timestamptz not null default now()
);
grant select on public.gym_settings to anon, authenticated;
grant update on public.gym_settings to authenticated;
grant all on public.gym_settings to service_role;
alter table public.gym_settings enable row level security;
create trigger gym_settings_touch before update on public.gym_settings for each row execute function public.touch_updated_at();

-- ===== PROFILES & ROLES =====
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text, phone text, avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
grant select, insert, update on public.profiles to authenticated;
grant all on public.profiles to service_role;
alter table public.profiles enable row level security;
create policy "own profile read" on public.profiles for select to authenticated using (id = auth.uid());
create policy "own profile update" on public.profiles for update to authenticated using (id = auth.uid());
create policy "own profile insert" on public.profiles for insert to authenticated with check (id = auth.uid());

create table public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  gym_id uuid references public.gyms(id) on delete cascade,
  role public.app_role not null,
  created_at timestamptz not null default now(),
  unique (user_id, gym_id, role),
  check ((role = 'super_admin') = (gym_id is null))
);
grant select on public.user_roles to authenticated;
grant all on public.user_roles to service_role;
alter table public.user_roles enable row level security;

create or replace function public.has_gym_role(_gym uuid, _roles public.app_role[])
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.user_roles where user_id = auth.uid() and gym_id = _gym and role = any(_roles))
$$;
create or replace function public.is_gym_staff(_gym uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_gym_role(_gym, array['owner','manager','receptionist','trainer']::public.app_role[])
$$;
create or replace function public.is_gym_admin(_gym uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_gym_role(_gym, array['owner','manager']::public.app_role[])
$$;
create or replace function public.is_front_desk(_gym uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select public.has_gym_role(_gym, array['owner','manager','receptionist']::public.app_role[])
$$;

create policy "see own roles" on public.user_roles for select to authenticated
  using (user_id = auth.uid() or (gym_id is not null and public.is_gym_admin(gym_id)));

create policy "gym admins update gym" on public.gyms for update to authenticated using (public.has_gym_role(id, array['owner']::public.app_role[]));
create policy "public read gyms" on public.gyms for select to anon, authenticated using (true);
create policy "public read settings" on public.gym_settings for select to anon, authenticated using (true);
create policy "owner updates settings" on public.gym_settings for update to authenticated using (public.is_gym_admin(gym_id));

-- profile auto-create
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id, full_name) values (new.id, coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name'))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- ===== AUDIT =====
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid references public.gyms(id) on delete cascade,
  actor_id uuid,
  action text not null,
  entity text,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index on public.audit_logs(gym_id, created_at desc);
grant select on public.audit_logs to authenticated;
grant all on public.audit_logs to service_role;
alter table public.audit_logs enable row level security;
create policy "admins read audit" on public.audit_logs for select to authenticated using (public.is_gym_admin(gym_id));

create or replace function public.log_audit(_gym uuid, _action text, _entity text, _entity_id uuid, _details jsonb)
returns void language sql security definer set search_path=public as $$
  insert into public.audit_logs(gym_id, actor_id, action, entity, entity_id, details) values (_gym, auth.uid(), _action, _entity, _entity_id, coalesce(_details,'{}'::jsonb));
$$;
revoke execute on function public.log_audit(uuid,text,text,uuid,jsonb) from public, anon;

-- Ownership bootstrap: first user to claim an ownerless gym becomes its owner.
create or replace function public.claim_gym_ownership(_slug text) returns boolean
language plpgsql security definer set search_path=public as $$
declare g uuid;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select id into g from public.gyms where slug = _slug for update;
  if g is null then raise exception 'Gym not found'; end if;
  if exists(select 1 from public.user_roles where gym_id = g and role = 'owner') then return false; end if;
  insert into public.user_roles(user_id, gym_id, role) values (auth.uid(), g, 'owner');
  perform public.log_audit(g, 'gym.owner_claimed', 'gym', g, '{}'::jsonb);
  return true;
end $$;
revoke execute on function public.claim_gym_ownership(text) from public, anon;
grant execute on function public.claim_gym_ownership(text) to authenticated;

create or replace function public.gym_has_owner(_slug text) returns boolean
language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.user_roles r join public.gyms g on g.id=r.gym_id where g.slug=_slug and r.role='owner')
$$;

-- ===== WEBSITE CONTENT =====
create table public.membership_plans (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  name text not null check (length(name) between 1 and 80),
  category text not null default 'monthly' check (category in ('monthly','quarterly','half_yearly','annual','personal_training','custom')),
  duration_days int not null check (duration_days between 1 and 1095),
  price numeric(10,2) not null check (price >= 0),
  joining_fee numeric(10,2) not null default 0 check (joining_fee >= 0),
  discount_label text,
  features text[] not null default '{}',
  is_recommended boolean not null default false,
  is_published boolean not null default false,
  sort_order int not null default 0,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.membership_plans(gym_id);
create trigger plans_touch before update on public.membership_plans for each row execute function public.touch_updated_at();

create table public.facilities (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  name text not null, description text, image_url text,
  is_published boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger facilities_touch before update on public.facilities for each row execute function public.touch_updated_at();

create table public.trainers (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  user_id uuid,
  full_name text not null, photo_url text, specialization text, qualifications text,
  experience_years int check (experience_years between 0 and 60),
  services text[] not null default '{}',
  is_published boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trainers_touch before update on public.trainers for each row execute function public.touch_updated_at();

create table public.testimonials (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  author_name text not null, quote text not null, source text,
  rating int check (rating between 1 and 5),
  consent_confirmed boolean not null default false,
  is_published boolean not null default false check (not is_published or consent_confirmed),
  created_at timestamptz not null default now()
);

create table public.faqs (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  question text not null, answer text not null,
  is_published boolean not null default false,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

do $$ declare t text; begin
  foreach t in array array['membership_plans','facilities','trainers','testimonials','faqs'] loop
    execute format('grant select on public.%I to anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "public read published" on public.%I for select to anon, authenticated using (is_published)', t);
    execute format('create policy "staff read all" on public.%I for select to authenticated using (public.is_gym_staff(gym_id))', t);
    execute format('create policy "admin insert" on public.%I for insert to authenticated with check (public.is_gym_admin(gym_id))', t);
    execute format('create policy "admin update" on public.%I for update to authenticated using (public.is_gym_admin(gym_id)) with check (public.is_gym_admin(gym_id))', t);
    execute format('create policy "admin delete" on public.%I for delete to authenticated using (public.is_gym_admin(gym_id))', t);
  end loop;
end $$;
-- plans should be hidden publicly once archived
drop policy "public read published" on public.membership_plans;
create policy "public read published" on public.membership_plans for select to anon, authenticated using (is_published and archived_at is null);

-- ===== MEMBERS =====
create table public.members (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_code text not null,
  user_id uuid,
  full_name text not null check (length(full_name) between 2 and 120),
  phone text not null check (phone ~ '^\+?[0-9 ]{10,15}$'),
  email text,
  date_of_birth date,
  emergency_contact text,
  photo_url text,
  joined_on date not null default current_date,
  assigned_trainer_id uuid references public.trainers(id) on delete set null,
  notes text,
  marketing_consent boolean not null default false,
  archived_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (gym_id, member_code),
  unique (gym_id, phone)
);
create index on public.members(gym_id, archived_at);
create index on public.members(user_id);
create trigger members_touch before update on public.members for each row execute function public.touch_updated_at();

create sequence public.member_code_seq start 1001;
create or replace function public.set_member_code() returns trigger language plpgsql set search_path=public as $$
begin
  if new.member_code is null or new.member_code = '' then
    new.member_code := 'MM' || nextval('public.member_code_seq');
  end if;
  return new;
end $$;
create trigger members_code before insert on public.members for each row execute function public.set_member_code();

grant select, insert, update on public.members to authenticated;
grant all on public.members to service_role;
grant usage on sequence public.member_code_seq to authenticated;
alter table public.members enable row level security;
create policy "front desk read members" on public.members for select to authenticated using (public.is_front_desk(gym_id));
create policy "trainer read assigned" on public.members for select to authenticated using (
  public.has_gym_role(gym_id, array['trainer']::public.app_role[])
  and assigned_trainer_id in (select id from public.trainers t where t.user_id = auth.uid()));
create policy "member read self" on public.members for select to authenticated using (user_id = auth.uid());
create policy "front desk insert members" on public.members for insert to authenticated with check (public.is_front_desk(gym_id));
create policy "front desk update members" on public.members for update to authenticated using (public.is_front_desk(gym_id)) with check (public.is_front_desk(gym_id));

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  plan_id uuid references public.membership_plans(id) on delete set null,
  plan_name text not null,
  start_date date not null,
  end_date date not null,
  price numeric(10,2) not null default 0 check (price >= 0),
  joining_fee numeric(10,2) not null default 0 check (joining_fee >= 0),
  discount numeric(10,2) not null default 0 check (discount >= 0),
  amount_due numeric(10,2) generated always as (greatest(price + joining_fee - discount, 0)) stored,
  state text not null default 'active' check (state in ('active','frozen','cancelled')),
  created_by uuid,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);
create index on public.memberships(gym_id, end_date);
create index on public.memberships(member_id);
grant select, insert, update on public.memberships to authenticated;
grant all on public.memberships to service_role;
alter table public.memberships enable row level security;
create policy "front desk read memberships" on public.memberships for select to authenticated using (public.is_front_desk(gym_id));
create policy "member read own memberships" on public.memberships for select to authenticated using (member_id in (select id from public.members where user_id = auth.uid()));
create policy "front desk write memberships" on public.memberships for insert to authenticated with check (public.is_front_desk(gym_id) and member_id in (select id from public.members m where m.gym_id = memberships.gym_id));
create policy "front desk update memberships" on public.memberships for update to authenticated using (public.is_front_desk(gym_id));

-- ===== PAYMENTS & EXPENSES =====
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete restrict,
  membership_id uuid references public.memberships(id) on delete set null,
  amount numeric(10,2) not null check (amount <> 0),
  method public.payment_method not null,
  reference text,
  kind text not null default 'payment' check (kind in ('payment','refund','reversal')),
  notes text,
  paid_at timestamptz not null default now(),
  recorded_by uuid default auth.uid(),
  created_at timestamptz not null default now(),
  check ((kind = 'payment' and amount > 0) or (kind <> 'payment' and amount < 0))
);
create index on public.payments(gym_id, paid_at desc);
create unique index payments_reference_uniq on public.payments(gym_id, reference) where reference is not null and method = 'online';
grant select, insert on public.payments to authenticated;
grant all on public.payments to service_role;
alter table public.payments enable row level security;
create policy "front desk read payments" on public.payments for select to authenticated using (public.is_front_desk(gym_id));
create policy "member read own payments" on public.payments for select to authenticated using (member_id in (select id from public.members where user_id = auth.uid()));
create policy "front desk record payments" on public.payments for insert to authenticated with check (public.is_front_desk(gym_id) and recorded_by = auth.uid() and member_id in (select id from public.members m where m.gym_id = payments.gym_id));

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  category text not null check (category in ('rent','electricity','salaries','equipment_maintenance','marketing','cleaning','internet','repairs','other')),
  amount numeric(10,2) not null check (amount > 0),
  description text,
  spent_on date not null default current_date,
  is_recurring boolean not null default false,
  voided_at timestamptz,
  recorded_by uuid default auth.uid(),
  created_at timestamptz not null default now()
);
create index on public.expenses(gym_id, spent_on);
grant select, insert, update on public.expenses to authenticated;
grant all on public.expenses to service_role;
alter table public.expenses enable row level security;
create policy "admin read expenses" on public.expenses for select to authenticated using (public.is_gym_admin(gym_id));
create policy "admin add expenses" on public.expenses for insert to authenticated with check (public.is_gym_admin(gym_id));
create policy "admin void expenses" on public.expenses for update to authenticated using (public.is_gym_admin(gym_id));

-- ===== LEADS & TRIALS =====
create table public.leads (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  full_name text not null, phone text not null, email text,
  source public.lead_source not null default 'website',
  stage public.lead_stage not null default 'new',
  fitness_goal text, notes text, lost_reason text,
  assigned_to uuid,
  next_followup_at timestamptz,
  converted_member_id uuid references public.members(id) on delete set null,
  consent_to_contact boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.leads(gym_id, stage);
create trigger leads_touch before update on public.leads for each row execute function public.touch_updated_at();

create table public.trial_bookings (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  lead_id uuid references public.leads(id) on delete set null,
  full_name text not null, phone text not null, email text,
  preferred_date date not null, time_slot text not null,
  fitness_goal text,
  status text not null default 'pending' check (status in ('pending','confirmed','completed','no_show','cancelled')),
  created_at timestamptz not null default now(),
  unique (gym_id, phone, preferred_date)
);
create index on public.trial_bookings(gym_id, preferred_date);

create table public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  full_name text not null, phone text not null, message text not null,
  handled boolean not null default false,
  created_at timestamptz not null default now()
);

do $$ declare t text; begin
  foreach t in array array['leads','trial_bookings','contact_messages'] loop
    execute format('grant select, insert, update on public.%I to authenticated', t);
    execute format('grant all on public.%I to service_role', t);
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy "front desk read" on public.%I for select to authenticated using (public.is_front_desk(gym_id))', t);
    execute format('create policy "front desk insert" on public.%I for insert to authenticated with check (public.is_front_desk(gym_id))', t);
    execute format('create policy "front desk update" on public.%I for update to authenticated using (public.is_front_desk(gym_id))', t);
  end loop;
end $$;

-- ===== ATTENDANCE =====
create table public.attendance (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  checked_out_at timestamptz,
  method public.checkin_method not null,
  recorded_by uuid,
  reason text,
  created_at timestamptz not null default now()
);
create index on public.attendance(gym_id, checked_in_at desc);
create index on public.attendance(member_id, checked_in_at desc);
grant select on public.attendance to authenticated;
grant all on public.attendance to service_role;
alter table public.attendance enable row level security;
create policy "front desk read attendance" on public.attendance for select to authenticated using (public.is_front_desk(gym_id));
create policy "member read own attendance" on public.attendance for select to authenticated using (member_id in (select id from public.members where user_id = auth.uid()));

-- short-lived personal tokens shown by members (Method A)
create table public.attendance_checkin_tokens (
  token text primary key,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  expires_at timestamptz not null,
  used_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.attendance_checkin_tokens(member_id, created_at desc);
grant all on public.attendance_checkin_tokens to service_role;
alter table public.attendance_checkin_tokens enable row level security;

-- entrance display challenges (Method B)
create table public.attendance_qr_challenges (
  nonce text primary key,
  gym_id uuid not null references public.gyms(id) on delete cascade,
  expires_at timestamptz not null,
  created_by uuid,
  created_at timestamptz not null default now()
);
create index on public.attendance_qr_challenges(gym_id, created_at desc);
grant all on public.attendance_qr_challenges to service_role;
alter table public.attendance_qr_challenges enable row level security;

-- Membership status derived from dates
create or replace function public.member_status(_member uuid) returns text
language sql stable security definer set search_path=public as $$
  with m as (
    select ms.*, s.expiring_soon_days from public.memberships ms
    join public.gym_settings s on s.gym_id = ms.gym_id
    where ms.member_id = _member and ms.state <> 'cancelled'
    order by ms.end_date desc limit 1)
  select case
    when not exists(select 1 from m) then 'none'
    when (select state from m) = 'frozen' then 'frozen'
    when (select end_date from m) < (now() at time zone 'Asia/Kolkata')::date then 'expired'
    when (select start_date from m) > (now() at time zone 'Asia/Kolkata')::date then 'upcoming'
    when (select end_date from m) <= (now() at time zone 'Asia/Kolkata')::date + (select expiring_soon_days from m) then 'expiring_soon'
    else 'active' end
$$;

-- core check-in routine (internal)
create or replace function public._do_checkin(_gym uuid, _member uuid, _method public.checkin_method, _reason text, _at timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare st text; cooldown int; last timestamptz; m record; new_id uuid;
begin
  select id, full_name, member_code, photo_url, gym_id, archived_at into m from public.members where id = _member;
  if m.id is null or m.gym_id <> _gym then return jsonb_build_object('ok',false,'reason','Member not found in this gym'); end if;
  if m.archived_at is not null then return jsonb_build_object('ok',false,'reason','Member is archived','member_name',m.full_name); end if;
  st := public.member_status(_member);
  if st not in ('active','expiring_soon') then
    perform public.log_audit(_gym,'attendance.rejected','member',_member,jsonb_build_object('status',st,'method',_method));
    return jsonb_build_object('ok',false,'reason','Membership is '||replace(st,'_',' '),'member_name',m.full_name,'member_code',m.member_code,'photo_url',m.photo_url,'status',st);
  end if;
  select checkin_cooldown_minutes into cooldown from public.gym_settings where gym_id = _gym;
  select max(checked_in_at) into last from public.attendance where member_id = _member;
  if last is not null and last > _at - make_interval(mins => coalesce(cooldown,240)) and _method <> 'manual' then
    return jsonb_build_object('ok',false,'duplicate',true,'reason','Already checked in at '||to_char(last at time zone 'Asia/Kolkata','HH24:MI'),'member_name',m.full_name,'member_code',m.member_code,'photo_url',m.photo_url,'status',st);
  end if;
  insert into public.attendance(gym_id, member_id, checked_in_at, method, recorded_by, reason)
    values (_gym, _member, _at, _method, auth.uid(), _reason) returning id into new_id;
  perform public.log_audit(_gym,'attendance.checkin','attendance',new_id,jsonb_build_object('method',_method,'member_id',_member));
  return jsonb_build_object('ok',true,'member_name',m.full_name,'member_code',m.member_code,'photo_url',m.photo_url,'status',st,'checked_in_at',_at);
end $$;
revoke execute on function public._do_checkin(uuid,uuid,public.checkin_method,text,timestamptz) from public, anon, authenticated;

-- Member: issue personal rotating token (60s)
create or replace function public.issue_member_checkin_token() returns jsonb
language plpgsql security definer set search_path=public, extensions as $$
declare m record; tok text; recent int;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  select id, gym_id into m from public.members where user_id = auth.uid() and archived_at is null limit 1;
  if m.id is null then raise exception 'No membership linked to this account'; end if;
  select count(*) into recent from public.attendance_checkin_tokens where member_id = m.id and created_at > now() - interval '1 minute';
  if recent > 10 then raise exception 'Too many requests, wait a minute'; end if;
  delete from public.attendance_checkin_tokens where expires_at < now() - interval '1 hour';
  tok := encode(gen_random_bytes(24), 'hex');
  insert into public.attendance_checkin_tokens(token, gym_id, member_id, expires_at) values (tok, m.gym_id, m.id, now() + interval '60 seconds');
  return jsonb_build_object('token','MMT1.'||tok,'expires_at',now() + interval '60 seconds');
end $$;
revoke execute on function public.issue_member_checkin_token() from public, anon;
grant execute on function public.issue_member_checkin_token() to authenticated;

-- Reception: redeem scanned member token
create or replace function public.redeem_member_token(_gym uuid, _token text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare t record; raw text;
begin
  if not public.is_front_desk(_gym) then raise exception 'Not authorised'; end if;
  raw := regexp_replace(coalesce(_token,''), '^MMT1\.', '');
  if raw !~ '^[0-9a-f]{48}$' then return jsonb_build_object('ok',false,'reason','Not a valid Muscle Monk QR'); end if;
  update public.attendance_checkin_tokens set used_at = now()
    where token = raw and used_at is null and expires_at > now() and gym_id = _gym
    returning * into t;
  if t.token is null then
    perform public.log_audit(_gym,'attendance.token_rejected','token',null,'{}'::jsonb);
    return jsonb_build_object('ok',false,'reason','QR expired, already used, or from another gym. Ask the member to refresh.');
  end if;
  return public._do_checkin(_gym, t.member_id, 'reception_scan', null, now());
end $$;
revoke execute on function public.redeem_member_token(uuid,text) from public, anon;
grant execute on function public.redeem_member_token(uuid,text) to authenticated;

-- Reception display: issue entrance challenge
create or replace function public.issue_entrance_challenge(_gym uuid) returns jsonb
language plpgsql security definer set search_path=public, extensions as $$
declare n text; ttl int;
begin
  if not public.is_front_desk(_gym) then raise exception 'Not authorised'; end if;
  select entrance_qr_ttl_seconds into ttl from public.gym_settings where gym_id = _gym;
  delete from public.attendance_qr_challenges where expires_at < now() - interval '1 hour';
  n := encode(gen_random_bytes(24), 'hex');
  insert into public.attendance_qr_challenges(nonce, gym_id, expires_at, created_by) values (n, _gym, now() + make_interval(secs => ttl), auth.uid());
  return jsonb_build_object('payload','MMG1.'||n,'expires_at',now() + make_interval(secs => ttl),'ttl',ttl);
end $$;
revoke execute on function public.issue_entrance_challenge(uuid) from public, anon;
grant execute on function public.issue_entrance_challenge(uuid) to authenticated;

-- Member: scan entrance QR
create or replace function public.member_entrance_checkin(_payload text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c record; m record; raw text;
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  raw := regexp_replace(coalesce(_payload,''), '^MMG1\.', '');
  if raw !~ '^[0-9a-f]{48}$' then return jsonb_build_object('ok',false,'reason','This is not the gym entrance QR'); end if;
  select * into c from public.attendance_qr_challenges where nonce = raw and expires_at > now();
  if c.nonce is null then return jsonb_build_object('ok',false,'reason','This QR has expired. Scan the live code on the screen.'); end if;
  select id into m from public.members where user_id = auth.uid() and gym_id = c.gym_id and archived_at is null;
  if m.id is null then return jsonb_build_object('ok',false,'reason','Your account is not a member of this gym'); end if;
  return public._do_checkin(c.gym_id, m.id, 'entrance_qr', null, now());
end $$;
revoke execute on function public.member_entrance_checkin(text) from public, anon;
grant execute on function public.member_entrance_checkin(text) to authenticated;

-- Manual check-in
create or replace function public.manual_checkin(_gym uuid, _member uuid, _at timestamptz, _reason text) returns jsonb
language plpgsql security definer set search_path=public as $$
begin
  if not public.is_front_desk(_gym) then raise exception 'Not authorised'; end if;
  if _at > now() + interval '5 minutes' then raise exception 'Check-in time cannot be in the future'; end if;
  return public._do_checkin(_gym, _member, 'manual', nullif(trim(_reason),''), coalesce(_at, now()));
end $$;
revoke execute on function public.manual_checkin(uuid,uuid,timestamptz,text) from public, anon;
grant execute on function public.manual_checkin(uuid,uuid,timestamptz,text) to authenticated;

-- Link a signed-in user to their member record by verified email
create or replace function public.link_member_account() returns boolean
language plpgsql security definer set search_path=public as $$
declare em text; m record;
begin
  if auth.uid() is null then return false; end if;
  if exists(select 1 from public.members where user_id = auth.uid()) then return true; end if;
  select email into em from auth.users where id = auth.uid() and email_confirmed_at is not null;
  if em is null then return false; end if;
  select id, gym_id into m from public.members where lower(email) = lower(em) and user_id is null and archived_at is null limit 1;
  if m.id is null then return false; end if;
  update public.members set user_id = auth.uid() where id = m.id;
  insert into public.user_roles(user_id, gym_id, role) values (auth.uid(), m.gym_id, 'member') on conflict do nothing;
  return true;
end $$;
revoke execute on function public.link_member_account() from public, anon;
grant execute on function public.link_member_account() to authenticated;

-- ===== SEED: the Muscle Monk tenant (business facts only, no fake numbers) =====
insert into public.gyms(slug, name, name_hi, phone, whatsapp, address, city, state, postal_code, latitude, longitude)
values ('muscle-monk','Muscle Monk Gymnasium','मसल मोंक जिम्नेजियम','+919755966358','+919755966358',
 '1st Floor, Above Cooperative Bank, In Front of Mamaji Complex, Sai Vihar Colony, Rau','Indore','Madhya Pradesh','453331', 22.6385, 75.8115);
insert into public.gym_settings(gym_id, google_rating, google_review_count, hours)
select id, 4.0, 4, '[]'::jsonb from public.gyms where slug='muscle-monk';
insert into public.facilities(gym_id, name, description, sort_order)
select g.id, f.n, f.d, f.o from public.gyms g, (values
 ('Strength Training Zone','Racks, benches and bars for serious strength work.',1),
 ('Cardio Training Zone','Treadmills and cardio machines for endurance.',2),
 ('Free Weights','Dumbbells and plates across a wide range.',3),
 ('Resistance Machines','Guided machines for every major muscle group.',4),
 ('Functional Training','Space for mobility, conditioning and bodyweight work.',5),
 ('Personal Training','One-to-one coaching with a trainer.',6),
 ('Changing Facilities','Space to change before and after training.',7),
 ('Parking','Parking near the building.',8)) as f(n,d,o)
where g.slug='muscle-monk';
