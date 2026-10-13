# Pilotage QHSE Delafosse — version en ligne

Tableau de bord QHSE partagé entre les membres de la cellule : les saisies sont enregistrées dans une base Supabase et apparaissent en direct chez tous les membres connectés. Connexion par e-mail et mot de passe ; l'accès aux données est réservé aux membres validés par un administrateur.

Deux fichiers :

- `index.html` — la page elle-même (un seul fichier, aucune compilation).
- `supabase-setup.sql` — crée la base, les règles d'accès et le journal des modifications.

Tout est gratuit : Supabase (offre Free) pour la base, GitHub Pages ou Netlify pour l'hébergement.

---

## 1. Créer la base (≈ 10 min)

1. Créer un compte sur [supabase.com](https://supabase.com), puis **New project**. Choisir une région proche (ex. Europe) et noter le mot de passe de base de données quelque part.
2. Ouvrir **SQL Editor**, coller tout le contenu de `supabase-setup.sql`.
3. **Avant de lancer**, remplacer les adresses de la section 8 par les vraies adresses des membres (`editeur` = peut saisir, `lecteur` = consultation seule). Cliquer **Run**.
4. Aller dans **Project Settings → API** et copier :
   - **Project URL** (ex. `https://abcdefghijkl.supabase.co`)
   - la clé **anon** / **publishable**

   Ces deux valeurs sont faites pour être publiques : la protection des données repose sur les règles d'accès créées par le script. Ne jamais utiliser la clé `service_role` / `secret` dans la page.

## 2. Renseigner la page

Ouvrir `index.html` dans un éditeur de texte, chercher `QHSE_CONFIG` (en haut du fichier) et coller les deux valeurs :

```js
window.QHSE_CONFIG = {
  supabaseUrl: 'https://abcdefghijkl.supabase.co',
  supabaseAnonKey: 'eyJhbGciOi…'
};
```

Si ces champs restent vides, la page fonctionne comme avant, en mode local (un suivi par navigateur).

## 3. Mettre en ligne

**Option A — GitHub Pages (recommandée pour continuer à retravailler la page)**

1. Créer un dépôt sur GitHub, y déposer `index.html` (via **Add file → Upload files**).
2. **Settings → Pages** → Source : *Deploy from a branch*, branche `main`, dossier `/ (root)`.
3. L'adresse apparaît après une minute, du type `https://<compte>.github.io/<depot>/`.

Chaque modification de `index.html` dans le dépôt est remise en ligne automatiquement.

**Option B — Netlify Drop (le plus rapide)**

Aller sur [app.netlify.com/drop](https://app.netlify.com/drop) et glisser le dossier contenant `index.html`.

## 4. Autoriser l'adresse du site dans Supabase

Indispensable pour que le lien reçu par e-mail ramène au tableau de bord :

**Authentication → URL Configuration**

- **Site URL** : l'adresse du site (ex. `https://compte.github.io/qhse/`)
- **Redirect URLs** : ajouter la même adresse

## 5. Utilisation et embarquement des membres

- **Se connecter** : adresse e-mail et mot de passe. À la première visite, cliquer **Créer votre compte** et choisir un mot de passe (8 caractères minimum). Un e-mail n'est envoyé qu'en cas de **mot de passe oublié**.
- **Rôles** : *administrateur* (saisit et gère la cellule), *éditeur* (saisit), *lecteur* (consulte seulement).
- **Faire entrer un nouveau membre**, deux façons :
  1. *Il fait la demande* : il ouvre le tableau de bord, se connecte, et voit le formulaire « Rejoindre la cellule » (nom, fonction). Un administrateur voit la demande dans **Gérer la cellule**, choisit le rôle et clique **Accepter**.
  2. *L'administrateur l'inscrit directement* : **Gérer la cellule → Ajouter directement un membre**, puis lui envoie l'adresse du tableau de bord.
- Depuis **Gérer la cellule**, un administrateur peut aussi changer un rôle ou retirer un membre. Il ne peut ni se retirer lui-même, ni s'enlever le rôle d'administrateur : nommez un second administrateur pour ne jamais perdre la main.
- Une adresse non inscrite qui se connecte ne voit aucune donnée.
- **Qui a modifié quoi** : table `qhse_journal` dans Supabase (Table Editor).
- Le **mode démonstration** et l'**export CSV** fonctionnent comme avant.

## Limites de l'offre gratuite à connaître

- **E-mails de connexion** : le service d'envoi intégré de Supabase est volontairement limité (quelques e-mails par heure pour tout le projet). Suffisant pour une cellule dont les membres restent connectés ; si cela bloque, brancher un SMTP gratuit (Brevo, Resend…) dans **Authentication → Emails → SMTP Settings**.
- **Mise en veille** : un projet gratuit sans aucune activité pendant une semaine est mis en pause. Il se réactive en un clic depuis le tableau de bord Supabase, sans perte de données. Un usage hebdomadaire normal suffit à l'éviter.
- **Sauvegarde** : l'offre gratuite n'inclut pas de restauration à un instant donné. Exporter le CSV à chaque revue de direction et l'archiver.

## Structure des données (pour qui retravaille la page)

Une table unique `qhse_docs (collection, doc_id, data jsonb)` :

| collection    | doc_id               | data                                                  |
|---------------|----------------------|-------------------------------------------------------|
| `suivi`       | code activité (`PIL-01`) | `{statut, maj}`                                   |
| `indicateurs` | code indicateur (`I-QE-3`) | `{valeur, maj}`                                 |
| `filieres`    | identifiant de ligne | `{nom, niv, reg, eff, aban, assi, pres, adm, n1, cible, sortj, emp, supprime, maj}` |
| `config`      | `general`            | `{demarrage}`                                         |

Les activités, indicateurs et filières de référence sont définis en tête du `<script>` de `index.html` (`ACTIVITES`, `INDICATEURS`, `FILIERES_BASE`) : les modifier là ne touche pas aux saisies déjà enregistrées, tant que les codes restent les mêmes.
