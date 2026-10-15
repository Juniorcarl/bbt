/// Hides account and card numbers in statement text before it is kept
/// anywhere (memory, database, learning).
///
/// - Botswana numbers written with the country code (267 + 8 digits) are
///   shortened to the 8-digit local number, so "send to your own number"
///   detection keeps working.
/// - Card numbers the bank already half-masked (471396*5328) and any run of
///   9 or more digits (account numbers, long references) keep only their last
///   4 digits: 62012345678 → ••••5678.
/// - 8-digit numbers (local phone numbers) are kept, because bbt uses them to
///   recognise money sent to your own phone.
///
/// The same rules are applied to existing rows by supabase/005_security.sql;
/// keep the two in step.
String maskPrivate(String text) => text
    .replaceAllMapped(RegExp(r'(?<!\d)267(\d{8})(?!\d)'), (m) => m[1]!)
    .replaceAllMapped(
        RegExp(r'(?<!\d)\d{4,}[x*#]+(\d{2,4})(?!\d)', caseSensitive: false), (m) => '••••${m[1]}')
    .replaceAllMapped(RegExp(r'(?<!\d)\d{5,}(\d{4})(?!\d)'), (m) => '••••${m[1]}');
