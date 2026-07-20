/// feedback_repository.dart – Feature-Wünsche und Fehlermeldungen senden.
library;

import 'package:supabase_flutter/supabase_flutter.dart';

enum FeedbackType { feature, bug }

abstract class FeedbackRepository {
  Future<void> submit(
    FeedbackType type,
    String message, {
    String? appVersion,
    String? platform,
  });
}

class SupabaseFeedbackRepository implements FeedbackRepository {
  SupabaseFeedbackRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> submit(
    FeedbackType type,
    String message, {
    String? appVersion,
    String? platform,
  }) async {
    await _client.from('feedback').insert({
      'group_id': _client.auth.currentUser?.id,
      'type': type.name,
      'message': message.trim(),
      'app_version': appVersion,
      'platform': platform,
    });
  }
}

/// Demo-Modus: nimmt Feedback entgegen, verwirft es aber.
class NoopFeedbackRepository implements FeedbackRepository {
  @override
  Future<void> submit(
    FeedbackType type,
    String message, {
    String? appVersion,
    String? platform,
  }) async {}
}
