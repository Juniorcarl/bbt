# bbt.

Personal finance app for Botswana. **Stage 1:** upload a bank statement → see your spending.

## How it works
1. **Upload** (`lib/services/statement_import.dart`): pick a PDF or CSV. Password-protected PDFs prompt for the password.
2. **Read** (`lib/data/statement_parser.dart`):
   - PDF → text (Syncfusion), then every line that *starts with a date* and *ends with amounts* is a transaction.
     With two or more amounts, the last is the running balance; the balance change (or a `Cr`/`Dr` marker) decides money in vs out.
   - CSV → finds the header row (Date / Description / Amount or Debit+Credit / Balance).
3. **Categorise** (`lib/data/categorizer.dart`): keyword rules for local merchants (Choppies, Sefalana, Mascom, BPC, WUC, Puma…). Add more there.
4. **Show** (`lib/data/spending_store.dart`): one `ChangeNotifier` computes month totals, category split, charts and the insight line for Home, Dashboard and Budget.

Everything runs on the device; nothing is sent to a server.

## Run
```
flutter pub get
flutter test
flutter run
```

Note: `syncfusion_flutter_pdf` uses the Syncfusion Community License (free for individuals and companies under USD 1M revenue).
