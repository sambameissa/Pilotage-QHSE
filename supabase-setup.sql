-- =====================================================================
-- Pilotage QHSE Delafosse — mise en place de la base partagée (Supabase)
-- À coller une seule fois dans Supabase > SQL Editor (projet pilotage-qhse), puis « Run ».
-- =====================================================================

-- 1. Membres (admin = éditeur qui gère aussi la cellule) ---------------
create table if not exists public.qhse_membres (
  email      text primary key,
  role       text not null default 'editeur' check (role in ('admin', 'editeur', 'lecteur')),
  nom        text,
  ajoute_le  timestamptz not null default now()
);
alter table public.qhse_membres enable row level security;

-- 2. Demandes d'accès en attente ------------------------------------------
create table if not exists public.qhse_demandes (
  email       text primary key,
  nom         text check (char_length(nom) <= 120),
  fonction    text check (char_length(fonction) <= 120),
  demande_le  timestamptz not null default now()
);
alter table public.qhse_demandes enable row level security;

-- 3. Données du tableau de bord ---------------------------------------------
create table if not exists public.qhse_docs (
  collection  text not null check (collection in ('suivi', 'indicateurs', 'filieres', 'config')),
  doc_id      text not null check (char_length(doc_id) between 1 and 80),
  data        jsonb not null check (pg_column_size(data) < 8000),
  updated_at  timestamptz not null default now(),
  updated_by  text,
  primary key (collection, doc_id)
);
alter table public.qhse_docs enable row level security;

-- 4. Rôle de la personne connectée -----------------------------------------
create or replace function public.mon_role()
returns text language sql stable security definer set search_path = ''
as $$
  select m.role from public.qhse_membres m
  where lower(m.email) = lower(auth.jwt() ->> 'email')
$$;
revoke all on function public.mon_role() from public, anon;
grant execute on function public.mon_role() to authenticated;

-- 5. Règles d'accès -----------------------------------------------------------
drop policy if exists "membres lisent"     on public.qhse_docs;
drop policy if exists "editeurs ajoutent"  on public.qhse_docs;
drop policy if exists "editeurs modifient" on public.qhse_docs;
create policy "membres lisent" on public.qhse_docs
  for select to authenticated using ((select public.mon_role()) is not null);
create policy "editeurs ajoutent" on public.qhse_docs
  for insert to authenticated with check ((select public.mon_role()) in ('admin', 'editeur'));
create policy "editeurs modifient" on public.qhse_docs
  for update to authenticated
  using ((select public.mon_role()) in ('admin', 'editeur'))
  with check ((select public.mon_role()) in ('admin', 'editeur'));
-- Aucune règle de suppression : rien ne peut être effacé depuis la page.

-- 6. Horodatage et auteur imposés par le serveur ----------------------------
create or replace function public.qhse_horodater()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.jwt() ->> 'email';
  return new;
end
$$;
drop trigger if exists qhse_docs_horodatage on public.qhse_docs;
create trigger qhse_docs_horodatage
  before insert or update on public.qhse_docs
  for each row execute function public.qhse_horodater();

-- 7. Journal des modifications (preuve d'audit) ------------------------------
create table if not exists public.qhse_journal (
  id          bigint generated always as identity primary key,
  collection  text not null,
  doc_id      text not null,
  avant       jsonb,
  apres       jsonb,
  par         text,
  le          timestamptz not null default now()
);
alter table public.qhse_journal enable row level security;
drop policy if exists "membres lisent le journal" on public.qhse_journal;
create policy "membres lisent le journal" on public.qhse_journal
  for select to authenticated using ((select public.mon_role()) is not null);

create or replace function public.qhse_journaliser()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  insert into public.qhse_journal (collection, doc_id, avant, apres, par)
  values (new.collection, new.doc_id,
          case when tg_op = 'UPDATE' then old.data end, new.data, new.updated_by);
  return new;
end
$$;
drop trigger if exists qhse_docs_journal on public.qhse_docs;
create trigger qhse_docs_journal
  after insert or update on public.qhse_docs
  for each row execute function public.qhse_journaliser();

-- 8. Embarquement des membres (appelé depuis la page) -------------------------
create or replace function public.demander_acces(p_nom text, p_fonction text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_email text := lower(auth.jwt() ->> 'email');
begin
  if v_email is null then raise exception 'Connexion requise' using errcode = '42501'; end if;
  if exists (select 1 from public.qhse_membres where lower(email) = v_email) then return; end if;
  insert into public.qhse_demandes (email, nom, fonction)
  values (v_email, left(trim(p_nom), 120), left(trim(p_fonction), 120))
  on conflict (email) do update set nom = excluded.nom, fonction = excluded.fonction, demande_le = now();
end
$$;

create or replace function public.ma_demande()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.qhse_demandes where email = lower(auth.jwt() ->> 'email'))
$$;

create or replace function public.qhse_exiger_admin()
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if coalesce(public.mon_role(), '') <> 'admin' then
    raise exception 'Réservé aux administrateurs de la cellule' using errcode = '42501';
  end if;
end
$$;

create or replace function public.membres_lister()
returns table (email text, nom text, role text, ajoute_le timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.qhse_exiger_admin();
  return query select m.email, m.nom, m.role, m.ajoute_le
               from public.qhse_membres m order by m.role, m.nom, m.email;
end
$$;

create or replace function public.demandes_lister()
returns table (email text, nom text, fonction text, demande_le timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public.qhse_exiger_admin();
  return query select d.email, d.nom, d.fonction, d.demande_le
               from public.qhse_demandes d order by d.demande_le;
end
$$;

create or replace function public.membre_enregistrer(p_email text, p_nom text, p_role text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_email text := lower(trim(p_email));
begin
  perform public.qhse_exiger_admin();
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Adresse e-mail invalide'; end if;
  if p_role not in ('admin', 'editeur', 'lecteur') then raise exception 'Rôle invalide'; end if;
  if v_email = lower(auth.jwt() ->> 'email') and p_role <> 'admin' then
    raise exception 'Vous ne pouvez pas retirer votre propre rôle d''administrateur';
  end if;
  insert into public.qhse_membres (email, nom, role)
  values (v_email, nullif(left(trim(p_nom), 120), ''), p_role)
  on conflict (email) do update
    set nom = coalesce(excluded.nom, public.qhse_membres.nom), role = excluded.role;
  delete from public.qhse_demandes where email = v_email;
end
$$;

create or replace function public.membre_retirer(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_email text := lower(trim(p_email));
begin
  perform public.qhse_exiger_admin();
  if v_email = lower(auth.jwt() ->> 'email') then
    raise exception 'Vous ne pouvez pas vous retirer vous-même';
  end if;
  delete from public.qhse_membres where lower(email) = v_email;
end
$$;

create or replace function public.demande_refuser(p_email text)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  perform public.qhse_exiger_admin();
  delete from public.qhse_demandes where email = lower(trim(p_email));
end
$$;

do $$
declare f text;
begin
  foreach f in array array['demander_acces(text,text)', 'ma_demande()', 'qhse_exiger_admin()',
                           'membres_lister()', 'demandes_lister()', 'membre_enregistrer(text,text,text)',
                           'membre_retirer(text)', 'demande_refuser(text)']
  loop
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
  execute 'revoke all on function public.qhse_horodater() from public, anon, authenticated';
  execute 'revoke all on function public.qhse_journaliser() from public, anon, authenticated';
end
$$;

-- 9. Mises à jour en direct entre les postes ---------------------------------
do $$
begin
  if not exists (select 1 from pg_publication_tables
                 where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'qhse_docs') then
    alter publication supabase_realtime add table public.qhse_docs;
  end if;
end
$$;

-- 10. Première administratrice -------------------------------------------------
--     Les autres membres s'ajoutent ensuite depuis la page (« Gérer la cellule »).
insert into public.qhse_membres (email, role, nom)
values ('rieme@hotmail.fr', 'admin', 'Responsable qualité')
on conflict (email) do update set role = 'admin';
