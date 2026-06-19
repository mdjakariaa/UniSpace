-- ============================================================
-- Standard email authentication, profile ID, and predefined admin
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS profile_id TEXT;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
  requested_role TEXT;
  normalized_email TEXT := LOWER(COALESCE(NEW.email, ''));
BEGIN
  requested_role := LOWER(COALESCE(NEW.raw_user_meta_data->>'role', 'student'));

  IF normalized_email = 'mdjakaria111016@gmail.com' THEN
    requested_role := 'admin';
  ELSIF requested_role NOT IN ('student', 'teacher') THEN
    requested_role := 'student';
  END IF;

  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    role,
    status,
    phone,
    department,
    profile_id
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'full_name', ''), split_part(NEW.email, '@', 1)),
    requested_role,
    'active',
    NULLIF(NEW.raw_user_meta_data->>'phone', ''),
    NULLIF(NEW.raw_user_meta_data->>'department', ''),
    NULLIF(NEW.raw_user_meta_data->>'profile_id', '')
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = COALESCE(EXCLUDED.full_name, public.profiles.full_name),
    role = EXCLUDED.role,
    phone = COALESCE(EXCLUDED.phone, public.profiles.phone),
    department = COALESCE(EXCLUDED.department, public.profiles.department),
    profile_id = COALESCE(EXCLUDED.profile_id, public.profiles.profile_id),
    status = 'active',
    updated_at = NOW();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

DO $$
DECLARE
  v_admin_id UUID;
BEGIN
  SELECT id INTO v_admin_id
  FROM auth.users
  WHERE LOWER(email) = 'mdjakaria111016@gmail.com'
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    v_admin_id := gen_random_uuid();

    INSERT INTO auth.users (
      id,
      instance_id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data,
      raw_user_meta_data,
      created_at,
      updated_at,
      confirmation_token,
      email_change,
      email_change_token_new,
      recovery_token
    )
    VALUES (
      v_admin_id,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      'mdjakaria111016@gmail.com',
      crypt('admin1234', gen_salt('bf')),
      NOW(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      '{"full_name":"Admin User","role":"admin"}'::jsonb,
      NOW(),
      NOW(),
      '',
      '',
      '',
      ''
    );
  ELSE
    UPDATE auth.users
    SET encrypted_password = crypt('admin1234', gen_salt('bf')),
        email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
        raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb,
        raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
          || '{"full_name":"Admin User","role":"admin"}'::jsonb,
        updated_at = NOW()
    WHERE id = v_admin_id;
  END IF;

  INSERT INTO public.profiles (
    id,
    email,
    full_name,
    role,
    status,
    profile_id,
    phone,
    department
  )
  VALUES (
    v_admin_id,
    'mdjakaria111016@gmail.com',
    'Admin User',
    'admin',
    'active',
    'ADMIN',
    NULL,
    NULL
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    role = 'admin',
    status = 'active',
    profile_id = COALESCE(public.profiles.profile_id, EXCLUDED.profile_id),
    updated_at = NOW();
END $$;
