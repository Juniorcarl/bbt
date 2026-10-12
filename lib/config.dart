/// Supabase project settings.
///
/// Find both in the Supabase dashboard → Project Settings → API (or "API Keys").
/// The publishable / anon key is designed to be public: it only allows what the
/// Row Level Security rules in supabase/schema.sql permit (each user sees only
/// their own data). Never put the *secret* / service_role key here.
const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: 'PASTE_PROJECT_URL_HERE');
const supabaseKey = String.fromEnvironment('SUPABASE_KEY', defaultValue: 'PASTE_PUBLISHABLE_KEY_HERE');

bool get backendConfigured => supabaseUrl.startsWith('https://') && !supabaseKey.startsWith('PASTE_');
