drop policy if exists "Admins can delete member photos" on storage.objects;
create policy "Staff can delete member photos"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'member_photos'
    and public.has_app_role(array['admin', 'assistant'])
  );

drop policy if exists "Admins can delete choreography documents" on storage.objects;
create policy "Staff can delete choreography documents"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'choreography_docs'
    and public.has_app_role(array['admin', 'assistant'])
  );
