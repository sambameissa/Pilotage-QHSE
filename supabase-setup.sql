-- =====================================================================
-- Pilotage QHSE Delafosse — mise en place de la base partagée (Supabase)
-- À coller une seule fois dans Supabase > SQL Editor, puis « Run ».
-- Le script peut être relancé sans dommage.
-- =====================================================================

-- 1. Membres autorisés -------------------------------------------------
--    role = 'editeur' : peut saisir ; 'lecteur' : consultation seule.
--    Cette table n'est jamais lisible depuis le navigateur (RLS sans règle).
create table if not exists public.qhse_membres (
  email      text primary key,
  role       text not null default 'editeur' check (role in ('editeur', 'lecteur')),
  nom        text,
  ajoute_le  timestamptz not null default now()
);
alter table public.qhse_membres enable row level security;

-- 2. Données du tableau de bord -----------------------------------------
--    Une ligne par élément suivi : statut d'activité, relevé d'indicateur,
--    filière, ou réglage (date de démarrage).
create table if not exists public.qhse_docs (
  collection  text not null check (collection in ('suivi', 'indicateurs', 'filieres', 'config')),
  doc_id      text not null check (char_length(doc_id) between 1 and 80),
  data        jsonb not null check (pg_column_size(data) < 8000),
  updated_at  timestamptz not null default now(),
  updated_by  text,
  primary key (collection, doc_id)
);
alter table public.qhse_docs enable row level security;

-- 3. Rôle de la personne connectée (null si elle n'est pas membre) -------
create or replace function public.mon_role()
returns text
language sql stable security definer
set search_path = ''
as $$
  select m.role from public.qhse_membres m
  where lower(m.email) = lower(auth.jwt() ->> 'email')
$$;
revoke all on function public.mon_role() from public, anon;
grant execute on function public.mon_role() to authenticated;

-- 4. Règles d'accès -----------------------------------------------------
drop policy if exists "membres lisent"     on public.qhse_docs;
drop policy if exists "editeurs ajoutent"  on public.qhse_docs;
drop policy if exists "editeurs modifient" on public.qhse_docs;

create policy "membres lisent" on public.qhse_docs
  for select to authenticated
  using ((select public.mon_role()) is not null);

create policy "editeurs ajoutent" on public.qhse_docs
  for insert to authenticated
  with check ((select public.mon_role()) = 'editeur');

create policy "editeurs modifient" on public.qhse_docs
  for update to authenticated
  using ((select public.mon_role()) = 'editeur')
  with check ((select public.mon_role()) = 'editeur');
-- Aucune règle de suppression : rien ne peut être effacé depuis la page.

-- 5. Traçabilité : date et auteur imposés par le serveur -----------------
create or replace function public.qhse_horodater()
returns trigger
language plpgsql security definer
set search_path = ''
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

-- 6. Journal des modifications (preuve d'audit) --------------------------
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
  for select to authenticated
  using ((select public.mon_role()) is not null);

create or replace function public.qhse_journaliser()
returns trigger
language plpgsql security definer
set search_path = ''
as $$
begin
  insert into public.qhse_journal (collection, doc_id, avant, apres, par)
  values (new.collection, new.doc_id,
          case when tg_op = 'UPDATE' then old.data end,
          new.data, new.updated_by);
  return new;
end
$$;
drop trigger if exists qhse_docs_journal on public.qhse_docs;
create trigger qhse_docs_journal
  after insert or update on public.qhse_docs
  for each row execute function public.qhse_journaliser();

-- 7. Mises à jour en direct entre les postes -----------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'qhse_docs'
  ) then
    alter publication supabase_realtime add table public.qhse_docs;
  end if;
end
$$;

-- 8. Inscrire les membres de la cellule -----------------------------------
--    Remplacez les adresses ci-dessous, ajoutez une ligne par personne.
insert into public.qhse_membres (email, role, nom) values
  ('responsable.qualite@exemple.sn', 'editeur', 'Responsable qualité'),
  ('referent.hse@exemple.sn',        'editeur', 'Référent HSE'),
  ('direction@exemple.sn',           'lecteur', 'Direction du centre')
on conflict (email) do update set role = excluded.role, nom = excluded.nom;

-- Pour retirer quelqu'un plus tard :
--   delete from public.qhse_membres where email = 'adresse@exemple.sn';
-- Pour consulter qui a modifié quoi :
--   select le, par, collection, doc_id, avant, apres from public.qhse_journal order by le desc limit 100;
