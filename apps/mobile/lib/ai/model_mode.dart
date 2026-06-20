import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the [SharedPreferences] instance. Overridden in `main()` (after
/// `SharedPreferences.getInstance()`) and in tests with an in-memory instance.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('override sharedPreferencesProvider in main()'),
);
