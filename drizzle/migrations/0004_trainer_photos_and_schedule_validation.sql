ALTER TABLE public.trainers ADD COLUMN photo_path text;
CREATE POLICY "gym photo editors insert" ON storage.objects FOR INSERT TO authenticated WITH CHECK(bucket_id='gym-photos' AND EXISTS(SELECT 1 FROM public.gyms g WHERE g.id::text=(storage.foldername(name))[1] AND public.has_gym_role(g.id,ARRAY['owner','manager']::public.app_role[])));
CREATE POLICY "gym photo editor read" ON storage.objects FOR SELECT TO authenticated USING(bucket_id='gym-photos' AND EXISTS(SELECT 1 FROM public.gyms g WHERE g.id::text=(storage.foldername(name))[1] AND public.has_gym_role(g.id,ARRAY['owner','manager']::public.app_role[])));
CREATE POLICY "published trainer photo read" ON storage.objects FOR SELECT TO anon,authenticated USING(bucket_id='gym-photos' AND EXISTS(SELECT 1 FROM public.trainers t WHERE t.photo_path=name AND t.is_published AND t.is_active));
CREATE FUNCTION public.validate_gym_hours() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$ DECLARE h jsonb; daynames text[]:=ARRAY['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday']; i integer:=0; BEGIN
IF NEW.hours_confirmed THEN
IF jsonb_typeof(NEW.hours)<>'array' OR jsonb_array_length(NEW.hours)<>7 THEN RAISE EXCEPTION 'Enter the complete weekly schedule'; END IF;
FOR h IN SELECT * FROM jsonb_array_elements(NEW.hours) LOOP i:=i+1;
IF h->>'day' IS DISTINCT FROM daynames[i] OR h->>'closed' IS NULL OR h->>'closed' NOT IN ('true','false') THEN RAISE EXCEPTION 'Enter every day in order'; END IF;
IF h->>'closed'='false' AND (coalesce(h->>'open','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' OR coalesce(h->>'close','') !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$') THEN RAISE EXCEPTION 'Enter valid opening and closing times'; END IF;
END LOOP; END IF; RETURN NEW; END $$;
CREATE TRIGGER gym_hours_validation BEFORE INSERT OR UPDATE ON public.gym_settings FOR EACH ROW EXECUTE FUNCTION public.validate_gym_hours();
CREATE FUNCTION public.validate_trainer_photo() RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$ BEGIN
IF NEW.photo_path IS NOT NULL AND split_part(NEW.photo_path,'/',1)<>NEW.gym_id::text THEN RAISE EXCEPTION 'Photo belongs to another gym'; END IF; RETURN NEW; END $$;
CREATE TRIGGER trainer_photo_validation BEFORE INSERT OR UPDATE ON public.trainers FOR EACH ROW EXECUTE FUNCTION public.validate_trainer_photo();