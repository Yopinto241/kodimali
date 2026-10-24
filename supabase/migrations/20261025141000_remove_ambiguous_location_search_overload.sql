-- A legacy radius overload has the same first fifteen named arguments and a
-- default final argument. PostgREST therefore cannot choose an RPC when the
-- clients send the canonical fifteen-argument request.
drop function if exists public.search_public_listings_v2(
  text, text, uuid, uuid, uuid, uuid, numeric, numeric, text, text,
  integer, integer, double precision, double precision, text, double precision
);
