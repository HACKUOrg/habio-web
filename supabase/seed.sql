-- Dev seed data for Habio
-- Password for all test users: password123
-- Run via: supabase db reset (local) or apply manually in dev project

-- Fixed UUIDs for reproducible dev data
-- Manager: 11111111-1111-1111-1111-111111111101
-- Tenant:  11111111-1111-1111-1111-111111111102
-- Tech:    11111111-1111-1111-1111-111111111103
-- HK:      11111111-1111-1111-1111-111111111104
-- Property: 22222222-2222-2222-2222-222222222201
-- Room:     33333333-3333-3333-3333-333333333301

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

-- Profiles are created by handle_new_user trigger; update roles
UPDATE public.profiles SET role = 'manager', full_name = 'Dev Manager'
  WHERE id = '11111111-1111-1111-1111-111111111101';

UPDATE public.profiles SET role = 'tenant', full_name = 'Dev Tenant'
  WHERE id = '11111111-1111-1111-1111-111111111102';

UPDATE public.profiles SET role = 'technician', full_name = 'Dev Technician'
  WHERE id = '11111111-1111-1111-1111-111111111103';

UPDATE public.profiles SET role = 'housekeeper', full_name = 'Dev Housekeeper'
  WHERE id = '11111111-1111-1111-1111-111111111104';

-- Property
INSERT INTO public.properties (id, manager_id, name, address, description)
VALUES (
  '22222222-2222-2222-2222-222222222201',
  '11111111-1111-1111-1111-111111111101',
  'Habio Dev Dormitory',
  '123 Test Street, Bangkok',
  'Development test property'
)
ON CONFLICT (id) DO NOTHING;

-- Room
INSERT INTO public.rooms (id, property_id, room_number, floor, room_type, status, monthly_rate)
VALUES (
  '33333333-3333-3333-3333-333333333301',
  '22222222-2222-2222-2222-222222222201',
  '101',
  1,
  'single',
  'available',
  5000.00
)
ON CONFLICT (id) DO NOTHING;

-- Tenant lease (activates room occupancy via trigger)
INSERT INTO public.tenants (
  id,
  user_id,
  property_id,
  room_id,
  lease_start,
  lease_end,
  lease_status
)
VALUES (
  '44444444-4444-4444-4444-444444444401',
  '11111111-1111-1111-1111-111111111102',
  '22222222-2222-2222-2222-222222222201',
  '33333333-3333-3333-3333-333333333301',
  CURRENT_DATE,
  CURRENT_DATE + interval '1 year',
  'active'
)
ON CONFLICT (id) DO NOTHING;

-- Property staff
INSERT INTO public.property_staff (property_id, user_id, role)
VALUES
  ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111103', 'technician'),
  ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111104', 'housekeeper')
ON CONFLICT (property_id, user_id) DO NOTHING;
