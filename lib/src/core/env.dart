/// Credenciais do Supabase.
///
/// Nunca commit chaves reais no repositório público. Em produção, passe
/// via `--dart-define=SUPABASE_URL=...` e `--dart-define=SUPABASE_ANON_KEY=...`
/// (a anon key é pública por natureza, mas mesmo assim evite hardcode
/// direto num repositório público — use dart-define ou um .env ignorado).
class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://SEU-PROJETO.supabase.co',
  );

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'SUA-ANON-KEY-AQUI',
  );
}
