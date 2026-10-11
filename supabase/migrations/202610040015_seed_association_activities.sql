insert into public.activities (id, name, color_code, icon)
values
  (
    '00000000-0000-0000-0000-000000000002',
    'Chant',
    '#7C4DFF',
    'mic'
  ),
  (
    '00000000-0000-0000-0000-000000000003',
    'Line Dance',
    '#A67C52',
    'celebration'
  )
on conflict (name) do update
set color_code = excluded.color_code,
    icon = excluded.icon,
    is_active = true;
