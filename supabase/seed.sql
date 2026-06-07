-- Dev seed data for Habio (membership-based RBAC)
-- Password for all test users: password123
-- Run via: supabase db reset (local) or apply manually in dev project

-- Fixed UUIDs for reproducible dev data
-- Manager/Owner: 11111111-1111-1111-1111-111111111101
-- Tenant:         11111111-1111-1111-1111-111111111102
-- Tech:           11111111-1111-1111-1111-111111111103
-- HK:             11111111-1111-1111-1111-111111111104
-- Org:            55555555-5555-5555-5555-555555555501
-- Property:       22222222-2222-2222-2222-222222222201
-- Building:       66666666-6666-6666-6666-666666666601
-- Room:           33333333-3333-3333-3333-333333333301
-- Tenant profile: 44444444-4444-4444-4444-444444444401

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
  recovery_token,
  email_change_token_new,
  email_change
)
VALUES
  (
    '11111111-1111-1111-1111-111111111101',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'manager@habio.dev',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Dev Manager"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  ),
  (
    '11111111-1111-1111-1111-111111111102',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'tenant@habio.dev',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Dev Tenant"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  ),
  (
    '11111111-1111-1111-1111-111111111103',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'technician@habio.dev',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Dev Technician"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  ),
  (
    '11111111-1111-1111-1111-111111111104',
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    'housekeeper@habio.dev',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Dev Housekeeper"}',
    now(),
    now(),
    '',
    '',
    '',
    ''
  )
ON CONFLICT (id) DO NOTHING;

UPDATE public.profiles SET full_name = 'Dev Manager'
  WHERE id = '11111111-1111-1111-1111-111111111101';

UPDATE public.profiles SET full_name = 'Dev Tenant'
  WHERE id = '11111111-1111-1111-1111-111111111102';

UPDATE public.profiles SET full_name = 'Dev Technician'
  WHERE id = '11111111-1111-1111-1111-111111111103';

UPDATE public.profiles SET full_name = 'Dev Housekeeper'
  WHERE id = '11111111-1111-1111-1111-111111111104';

INSERT INTO public.organizations (id, name, slug)
VALUES (
  '55555555-5555-5555-5555-555555555501',
  'Habio Dev Organization',
  'habio-dev-org'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.properties (id, organization_id, name, address, description)
VALUES (
  '22222222-2222-2222-2222-222222222201',
  '55555555-5555-5555-5555-555555555501',
  'Habio Dev Dormitory',
  '123 Test Street, Bangkok',
  'Development test property'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.buildings (id, property_id, organization_id, name, total_floors)
VALUES (
  '66666666-6666-6666-6666-666666666601',
  '22222222-2222-2222-2222-222222222201',
  '55555555-5555-5555-5555-555555555501',
  'Main Building',
  1
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.rooms (id, property_id, building_id, room_number, floor, room_type, status, monthly_rate)
VALUES (
  '33333333-3333-3333-3333-333333333301',
  '22222222-2222-2222-2222-222222222201',
  '66666666-6666-6666-6666-666666666601',
  '101',
  1,
  'single',
  'available',
  5000.00
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.memberships (id, user_id, organization_id, property_id, role)
VALUES
  (
    '77777777-7777-7777-7777-777777777701',
    '11111111-1111-1111-1111-111111111101',
    '55555555-5555-5555-5555-555555555501',
    NULL,
    'owner'
  ),
  (
    '77777777-7777-7777-7777-777777777702',
    '11111111-1111-1111-1111-111111111101',
    '55555555-5555-5555-5555-555555555501',
    '22222222-2222-2222-2222-222222222201',
    'manager'
  ),
  (
    '77777777-7777-7777-7777-777777777703',
    '11111111-1111-1111-1111-111111111102',
    '55555555-5555-5555-5555-555555555501',
    '22222222-2222-2222-2222-222222222201',
    'tenant'
  ),
  (
    '77777777-7777-7777-7777-777777777704',
    '11111111-1111-1111-1111-111111111103',
    '55555555-5555-5555-5555-555555555501',
    '22222222-2222-2222-2222-222222222201',
    'technician'
  ),
  (
    '77777777-7777-7777-7777-777777777705',
    '11111111-1111-1111-1111-111111111104',
    '55555555-5555-5555-5555-555555555501',
    '22222222-2222-2222-2222-222222222201',
    'housekeeper'
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.tenant_profiles (
  id,
  user_id,
  membership_id,
  organization_id,
  property_id,
  room_id,
  lease_start,
  lease_end,
  lease_status
)
VALUES (
  '44444444-4444-4444-4444-444444444401',
  '11111111-1111-1111-1111-111111111102',
  '77777777-7777-7777-7777-777777777703',
  '55555555-5555-5555-5555-555555555501',
  '22222222-2222-2222-2222-222222222201',
  '33333333-3333-3333-3333-333333333301',
  CURRENT_DATE,
  CURRENT_DATE + interval '1 year',
  'active'
)
ON CONFLICT (id) DO NOTHING;
