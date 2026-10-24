-- Remove the matching legacy radius overload for the home feed RPC.
drop function if exists public.get_public_home_feed(
  integer, integer, uuid, uuid, uuid, uuid,
  double precision, double precision, text, double precision
);
