# bbt.

Personal finance app for Botswana: upload a bank statement → see where your money goes.

## Features
- Sign up / sign in / password reset (Supabase Auth)
- Upload PDF or CSV statements (password-protected PDFs supported). The file is read on the phone; only transactions are saved.
- Multi-month view, month-by-month breakdown, charts, monthly budgets per category
- Learning categoriser: corrections are saved to your account and train an on-device Naive Bayes model

## Backend (Supabase, free tier)
1. Create a project at supabase.com.
2. SQL Editor → paste `supabase/schema.sql` → Run.
3. Put the Project URL and publishable key in `lib/config.dart`.
4. Monitor users: Authentication → Users. Data: Table Editor. Activity: `events` table, or `select * from admin_overview;` in the SQL editor.

## Code map
- `lib/services/backend.dart` – every database call
- `lib/data/statement_parser.dart` – PDF/CSV → transactions
- `lib/data/smart_categorizer.dart` – learning categoriser; `categorizer.dart` – keyword rules
- `lib/data/spending_store.dart` – app state and all the maths
- `lib/screens/` – UI

## Run
```
flutter pub get
flutter test
flutter run
```
Android APKs are built by GitHub Actions on every push: https://github.com/Juniorcarl/bbt/releases/latest/download/bbt.apk
