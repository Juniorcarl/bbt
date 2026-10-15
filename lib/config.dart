/// Supabase project settings.
///
/// Find both in the Supabase dashboard → Project Settings → API (or "API Keys").
/// The publishable / anon key is designed to be public: it only allows what the
/// Row Level Security rules in supabase/schema.sql permit (each user sees only
/// their own data). Never put the *secret* / service_role key here.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://ygefozzeljyylimkizkz.supabase.co');
const supabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: 'sb_publishable_wjtfMfmzvYAAlj772PItUQ_INp6qR_0');

bool get backendConfigured => supabaseUrl.startsWith('https://') && !supabaseKey.startsWith('PASTE_');

/// Shown at the bottom of the privacy notice so users know who to contact
/// about their data. Leave empty to hide the line.
const privacyContact = '';
