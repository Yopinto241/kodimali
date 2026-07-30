create or replace function public.get_admin_role_directory() returns table(user_id uuid,full_name text,account_email text,roles jsonb)
language sql stable security definer set search_path=public as $$
 select p.id,p.full_name,p.account_email,coalesce(jsonb_agg(jsonb_build_object('id',r.id,'name',r.name) order by r.rank desc) filter(where r.id is not null),'[]'::jsonb)
 from public.profiles p left join public.admin_role_assignments a on a.user_id=p.id left join public.admin_role_definitions r on r.id=a.role_id
 where public.is_super_admin() group by p.id,p.full_name,p.account_email order by case when count(r.id)>0 then 0 else 1 end,p.full_name limit 1000;
$$;
grant execute on function public.get_admin_role_directory() to authenticated;
