ALTER TABLE public.facilities ADD COLUMN is_verified boolean NOT NULL DEFAULT false;
ALTER TABLE public.membership_plans ADD COLUMN amount numeric;
UPDATE public.membership_plans SET amount = price;
COMMENT ON COLUMN public.membership_plans.price IS 'DEPRECATED: replaced by nullable amount; legacy required field is not a quoted price';
ALTER TABLE public.gym_settings ADD COLUMN hours_confirmed boolean NOT NULL DEFAULT false;
CREATE FUNCTION public.validate_gym_content() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$ BEGIN
IF TG_TABLE_NAME='facilities' AND NEW.is_published AND NOT NEW.is_verified THEN RAISE EXCEPTION 'Verify this facility before publishing'; END IF;
IF TG_TABLE_NAME='membership_plans' THEN
IF NEW.amount < 0 OR NEW.duration_days <= 0 THEN RAISE EXCEPTION 'Enter a valid price and duration'; END IF;
IF NEW.is_published AND NEW.amount IS NULL THEN RAISE EXCEPTION 'Add a price before publishing'; END IF;
END IF; RETURN NEW; END $$;
CREATE TRIGGER facilities_publication BEFORE INSERT OR UPDATE ON public.facilities FOR EACH ROW EXECUTE FUNCTION public.validate_gym_content();
CREATE TRIGGER plans_publication BEFORE INSERT OR UPDATE ON public.membership_plans FOR EACH ROW EXECUTE FUNCTION public.validate_gym_content();
CREATE TABLE public.members(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),gym_id uuid NOT NULL REFERENCES public.gyms(id),user_id uuid,full_name text NOT NULL,phone text NOT NULL,email text,plan_id uuid REFERENCES public.membership_plans(id),starts_on date NOT NULL,ends_on date NOT NULL,status text NOT NULL DEFAULT 'active' CHECK(status IN ('active','paused','cancelled')),created_at timestamptz NOT NULL DEFAULT now(),CHECK(ends_on>=starts_on));
GRANT SELECT,INSERT,UPDATE ON public.members TO authenticated; GRANT ALL ON public.members TO service_role;
ALTER TABLE public.members ENABLE ROW LEVEL SECURITY;
CREATE POLICY "staff manage members" ON public.members FOR ALL TO authenticated USING(public.has_gym_role(gym_id,ARRAY['owner','manager','receptionist']::public.app_role[])) WITH CHECK(public.has_gym_role(gym_id,ARRAY['owner','manager','receptionist']::public.app_role[]));
CREATE POLICY "members read own membership" ON public.members FOR SELECT TO authenticated USING(user_id=auth.uid());
CREATE UNIQUE INDEX members_gym_user ON public.members(gym_id,user_id) WHERE user_id IS NOT NULL;
CREATE TABLE public.attendance(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),gym_id uuid NOT NULL REFERENCES public.gyms(id),member_id uuid NOT NULL REFERENCES public.members(id),checked_in_at timestamptz NOT NULL DEFAULT now(),method text NOT NULL,actor_id uuid NOT NULL);
GRANT SELECT ON public.attendance TO authenticated; GRANT ALL ON public.attendance TO service_role;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
CREATE POLICY "staff attendance read" ON public.attendance FOR SELECT TO authenticated USING(public.has_gym_role(gym_id,ARRAY['owner','manager','receptionist']::public.app_role[]));
CREATE POLICY "member attendance read" ON public.attendance FOR SELECT TO authenticated USING(EXISTS(SELECT 1 FROM public.members m WHERE m.id=member_id AND m.user_id=auth.uid()));
CREATE INDEX attendance_member_time ON public.attendance(member_id,checked_in_at DESC);
CREATE TABLE public.attendance_tokens(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),gym_id uuid NOT NULL REFERENCES public.gyms(id),member_id uuid REFERENCES public.members(id),token_hash text NOT NULL UNIQUE,kind text NOT NULL CHECK(kind IN ('member','entrance')),issued_by uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),expires_at timestamptz NOT NULL,used_at timestamptz);
GRANT ALL ON public.attendance_tokens TO service_role; ALTER TABLE public.attendance_tokens ENABLE ROW LEVEL SECURITY;
CREATE TABLE public.attendance_attempts(id uuid PRIMARY KEY DEFAULT gen_random_uuid(),actor_id uuid NOT NULL,created_at timestamptz NOT NULL DEFAULT now());
GRANT ALL ON public.attendance_attempts TO service_role; ALTER TABLE public.attendance_attempts ENABLE ROW LEVEL SECURITY;
CREATE INDEX attendance_attempts_actor_time ON public.attendance_attempts(actor_id,created_at);
CREATE TABLE public.attendance_redemptions(token_id uuid NOT NULL REFERENCES public.attendance_tokens(id),member_id uuid NOT NULL REFERENCES public.members(id),PRIMARY KEY(token_id,member_id));
GRANT ALL ON public.attendance_redemptions TO service_role; ALTER TABLE public.attendance_redemptions ENABLE ROW LEVEL SECURITY;
CREATE FUNCTION public.validate_member() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$ BEGIN
IF length(trim(NEW.full_name))<2 OR NEW.phone !~ '^\+?[0-9]{10,15}$' THEN RAISE EXCEPTION 'Enter valid member details'; END IF;
IF NEW.plan_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.membership_plans WHERE id=NEW.plan_id AND gym_id=NEW.gym_id) THEN RAISE EXCEPTION 'Plan belongs to another gym'; END IF;
IF NEW.user_id IS NOT NULL AND NOT EXISTS(SELECT 1 FROM public.profiles WHERE id=NEW.user_id) THEN RAISE EXCEPTION 'Member account does not exist'; END IF;
RETURN NEW; END $$;
CREATE TRIGGER member_validation BEFORE INSERT OR UPDATE ON public.members FOR EACH ROW EXECUTE FUNCTION public.validate_member();
CREATE FUNCTION public.issue_attendance_token(_gym uuid,_kind text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$ DECLARE m public.members; tok text; expiry timestamptz; BEGIN
IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text,1));
IF (SELECT count(*) FROM public.attendance_tokens WHERE issued_by=auth.uid() AND created_at>now()-interval '1 minute')>=10 THEN RAISE EXCEPTION 'Too many QR requests'; END IF;
IF _kind='entrance' THEN
IF NOT public.has_gym_role(_gym,ARRAY['owner','manager','receptionist']::public.app_role[]) THEN RAISE EXCEPTION 'Not authorized'; END IF;
expiry:=now()+interval '30 seconds';
ELSIF _kind='member' THEN
SELECT * INTO m FROM public.members WHERE gym_id=_gym AND user_id=auth.uid() AND status='active' AND starts_on <= (now() AT TIME ZONE 'Asia/Kolkata')::date AND ends_on >= (now() AT TIME ZONE 'Asia/Kolkata')::date;
IF m.id IS NULL THEN RAISE EXCEPTION 'An active membership is required'; END IF;
expiry:=now()+interval '60 seconds';
ELSE RAISE EXCEPTION 'Invalid QR type'; END IF;
tok:=gen_random_uuid()::text||gen_random_uuid()::text;
INSERT INTO public.attendance_tokens(gym_id,member_id,token_hash,kind,issued_by,expires_at) VALUES(_gym,m.id,encode(sha256(convert_to(tok,'UTF8')),'hex'),_kind,auth.uid(),expiry);
RETURN jsonb_build_object('token',tok,'expiresAt',expiry,'kind',_kind); END $$;
REVOKE ALL ON FUNCTION public.issue_attendance_token(uuid,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.issue_attendance_token(uuid,text) TO authenticated;
CREATE FUNCTION public.redeem_attendance_token(_gym uuid,_token text) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$ DECLARE t public.attendance_tokens; m public.members; aid uuid; cooldown integer; BEGIN
IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Sign in first'; END IF;
PERFORM pg_advisory_xact_lock(hashtextextended(auth.uid()::text,2));
IF (SELECT count(*) FROM public.attendance_attempts WHERE actor_id=auth.uid() AND created_at>now()-interval '1 minute')>=20 THEN RETURN jsonb_build_object('error','Too many scans. Wait one minute.'); END IF;
INSERT INTO public.attendance_attempts(actor_id) VALUES(auth.uid());
SELECT * INTO t FROM public.attendance_tokens WHERE token_hash=encode(sha256(convert_to(_token,'UTF8')),'hex') AND gym_id=_gym FOR UPDATE;
IF t.id IS NULL OR t.expires_at<=now() OR t.used_at IS NOT NULL THEN RETURN jsonb_build_object('error','QR expired or already used'); END IF;
IF t.kind='member' THEN
IF NOT public.has_gym_role(_gym,ARRAY['owner','manager','receptionist']::public.app_role[]) THEN RETURN jsonb_build_object('error','Only gym staff can scan a member pass'); END IF;
SELECT * INTO m FROM public.members WHERE id=t.member_id AND gym_id=_gym FOR UPDATE;
ELSE
SELECT * INTO m FROM public.members WHERE user_id=auth.uid() AND gym_id=_gym FOR UPDATE;
END IF;
IF m.id IS NULL OR m.status<>'active' OR m.starts_on>(now() AT TIME ZONE 'Asia/Kolkata')::date OR m.ends_on<(now() AT TIME ZONE 'Asia/Kolkata')::date THEN RETURN jsonb_build_object('error','An active membership is required'); END IF;
IF EXISTS(SELECT 1 FROM public.attendance_redemptions WHERE token_id=t.id AND member_id=m.id) THEN RETURN jsonb_build_object('error','This QR has already been scanned'); END IF;
SELECT checkin_cooldown_minutes INTO cooldown FROM public.gym_settings WHERE gym_id=_gym;
IF EXISTS(SELECT 1 FROM public.attendance WHERE member_id=m.id AND checked_in_at>now()-make_interval(mins=>coalesce(cooldown,240))) THEN RETURN jsonb_build_object('error','Already checked in recently'); END IF;
INSERT INTO public.attendance(gym_id,member_id,method,actor_id) VALUES(_gym,m.id,t.kind,auth.uid()) RETURNING id INTO aid;
INSERT INTO public.attendance_redemptions VALUES(t.id,m.id);
IF t.kind='member' THEN UPDATE public.attendance_tokens SET used_at=now() WHERE id=t.id; END IF;
INSERT INTO public.audit_logs(gym_id,actor_id,action,entity,entity_id,details) VALUES(_gym,auth.uid(),'attendance.checkin','members',m.id,jsonb_build_object('attendance_id',aid,'method',t.kind));
RETURN jsonb_build_object('id',aid,'name',m.full_name,'checkedInAt',now()); END $$;
REVOKE ALL ON FUNCTION public.redeem_attendance_token(uuid,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.redeem_attendance_token(uuid,text) TO authenticated;
CREATE FUNCTION public.link_member_account(_gym uuid,_member uuid,_email text) RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$ DECLARE uid uuid; BEGIN
IF NOT public.has_gym_role(_gym,ARRAY['owner','manager','receptionist']::public.app_role[]) THEN RAISE EXCEPTION 'Not authorized'; END IF;
SELECT id INTO uid FROM auth.users WHERE lower(email)=lower(trim(_email)) AND email_confirmed_at IS NOT NULL;
IF uid IS NULL THEN RAISE EXCEPTION 'Ask the member to sign up and verify this email first'; END IF;
UPDATE public.members SET user_id=uid WHERE id=_member AND gym_id=_gym;
IF NOT FOUND THEN RAISE EXCEPTION 'Member not found'; END IF; RETURN true; END $$;
REVOKE ALL ON FUNCTION public.link_member_account(uuid,uuid,text) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.link_member_account(uuid,uuid,text) TO authenticated;