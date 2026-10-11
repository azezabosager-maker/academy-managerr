# Academy Manager

## Cloud setup: username, password, and device sync

The hosted app uses Supabase Auth and a Postgres database. Each account can read and change only its own students, subscriptions, payments, and expenses through row-level security (RLS).

### 1. Host the web page over HTTPS

Deploy `academy-manager.html` as `index.html` using GitHub Pages or another static HTTPS host. Do not open the `file://` copy when setting up cloud access. The browser loads the Supabase JavaScript client from jsDelivr, so the hosted page needs an internet connection.

### 2. Create and configure Supabase

1. Create a Supabase project.
2. In **SQL Editor**, run the complete `supabase-setup.sql` file.
3. In **Authentication → Providers → Email**, enable password sign-in and disable email confirmation. Accounts use an internal alias ending in `@academy-manager.invalid`; the app does not send email.
4. In **Project Settings → API**, copy the Project URL and the public `anon` or `publishable` key. In the app, enter those values on the connection setup screen. Never put a `service_role` or `sb_secret_` key in the web page.
5. Open the hosted HTTPS address, save the connection settings, then create an account with a unique username and a password of at least 8 characters. On each additional device, enter the same Project URL and public key once, then sign in with the same username and password.

Usernames are case-insensitive and unique within this Supabase project. Because there is no real email address, standard email password-reset links are not used.

### 3. Enable manager-only password recovery

The recovery form requires a deployed Supabase Edge Function and a private administrator recovery key. Install the Supabase CLI, then run these commands from this project folder in PowerShell:

```powershell
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase secrets set --env-file .env.supabase
supabase functions deploy admin-reset-password --no-verify-jwt
```

- Before the last two commands, create a local `.env.supabase` file in this project folder with these three lines; replace each placeholder. The file is git-ignored. Delete it after uploading the secrets.

```text
SUPABASE_SERVICE_ROLE_KEY=YOUR_SERVICE_ROLE_KEY
ACADEMY_RECOVERY_KEY=YOUR_RANDOM_SECRET
ACADEMY_APP_ORIGIN=https://YOUR_SITE_ORIGIN
```

- Find the project reference in the Supabase project URL or project settings.
- Find the **service_role** key in the Supabase API settings. It is a server secret: use it only in the ignored local file, never in HTML, GitHub Pages, or a public repository.
- Generate a unique random administrator recovery secret of at least 32 characters. Keep it private; enter it in the recovery form only when the manager resets a password.
- Set `ACADEMY_APP_ORIGIN` to the exact origin of the hosted site, without a trailing slash (for example, `https://your-name.github.io`). This limits recovery requests to that site.

To reset an account, open the sign-in page, expand **Forgot your password? (Administrator only)**, and enter the account username, a new password, and the administrator recovery key. The key is not saved by the app. If it is lost, replace the `ACADEMY_RECOVERY_KEY` Supabase secret.

### 4. Move existing local data

Keep the old browser data or export a backup before switching. After signing in to the cloud app, choose **Import data from this device** in the header, or use **Import backup** to upload a JSON backup. Import adds the records to the signed-in account; it does not delete the local copy.

## Data and backups

- New records are stored in Supabase and synchronized to other signed-in devices in real time.
- The language preference and Supabase public connection settings stay in the current browser. Passwords are handled by Supabase Auth; the app never stores them.
- Anyone who can reach the public sign-in page can create a separate account. RLS keeps each account's records private from other accounts.
- Export backups regularly. A cloud service is not a substitute for backups, and free-tier availability, quotas, or inactivity policies can change.
- Row-level security is enabled for all application tables. The browser must use only the public anon/publishable key.

## Included features

- Arabic and English responsive interface.
- Monthly subscriptions (1, 3, 6, 12, or custom months), calculated end dates, payment due dates, renewal history, and recorded payments.
- Student profiles with guardian details, sport, coach, training days, and photo.
- Receipt printing for each payment.
- Monthly, quarterly, and annual received-revenue reports, expense tracking, and net totals.
- Search, editing, deletion, backup export, and backup import.
