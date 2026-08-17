import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase_providers.dart';
import '../data/voicemail_repository.dart';
import '../domain/voicemail.dart';

final voicemailRepositoryProvider = Provider<VoicemailRepository>((ref) {
  return VoicemailRepository(supabase: ref.watch(supabaseClientProvider));
});

final voicemailsProvider = FutureProvider<List<Voicemail>>((ref) async {
  final repo = ref.watch(voicemailRepositoryProvider);
  return repo.fetchMyVoicemails();
});

final unheardVoicemailCountProvider = FutureProvider<int>((ref) async {
  final repo = ref.watch(voicemailRepositoryProvider);
  return repo.fetchUnheardCount();
});
