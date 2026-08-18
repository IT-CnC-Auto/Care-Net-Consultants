
insert into storage.buckets (id, name, public)
values ('profile-photos','profile-photos',false),
       ('cnc-profile-photos','cnc-profile-photos',false)
on conflict (id) do nothing;

create policy profile_photos_select on storage.objects for select to public
  using ((bucket_id = 'profile-photos') and (is_admin_or_owner() or (auth.uid())::text = (storage.foldername(name))[1]));
create policy profile_photos_insert on storage.objects for insert to public
  with check ((bucket_id = 'profile-photos') and (is_admin_or_owner() or (auth.uid())::text = (storage.foldername(name))[1]));
create policy profile_photos_update on storage.objects for update to public
  using ((bucket_id = 'profile-photos') and (is_admin_or_owner() or (auth.uid())::text = (storage.foldername(name))[1]));
create policy profile_photos_delete on storage.objects for delete to public
  using ((bucket_id = 'profile-photos') and (is_admin_or_owner() or (auth.uid())::text = (storage.foldername(name))[1]));

create policy storage_admin_all on storage.objects for all to authenticated
  using ((bucket_id = 'cnc-profile-photos') and is_admin_or_owner())
  with check ((bucket_id = 'cnc-profile-photos') and is_admin_or_owner());
create policy storage_member_select_own on storage.objects for select to authenticated
  using ((bucket_id = 'cnc-profile-photos') and ((storage.foldername(name))[1] = (auth.uid())::text));
create policy storage_member_insert_own on storage.objects for insert to authenticated
  with check ((bucket_id = 'cnc-profile-photos') and ((storage.foldername(name))[1] = (auth.uid())::text));
create policy storage_member_update_own on storage.objects for update to authenticated
  using ((bucket_id = 'cnc-profile-photos') and ((storage.foldername(name))[1] = (auth.uid())::text))
  with check ((bucket_id = 'cnc-profile-photos') and ((storage.foldername(name))[1] = (auth.uid())::text));
