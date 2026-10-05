import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'repository.dart';

// Check the public provider settings before launching a browser, so an
// unconfigured provider does not strand a passenger on an error page.
Future<void> signInRiderWithSocial(OAuthProvider provider) async {
  if (provider != OAuthProvider.google && provider != OAuthProvider.apple) {
    throw const AppFailure('SOCIAL_SIGNIN_RIDERS_ONLY');
  }
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  final response = await http
      .get(Uri.parse('$url/auth/v1/settings'), headers: {'apikey': key})
      .timeout(const Duration(seconds: 15));
  if (response.statusCode != 200) throw const AppFailure('OFFLINE');
  final settings = jsonDecode(response.body) as Map<String, dynamic>;
  if (settings['external']?[provider.name] != true) {
    throw const AppFailure('provider_disabled');
  }
  final opened = await Supabase.instance.client.auth.signInWithOAuth(
    provider,
    redirectTo: 'io.rukkab.app://login-callback',
    scopes: provider == OAuthProvider.apple ? 'email name' : null,
  );
  if (!opened) throw const AppFailure('OFFLINE');
}

bool isSocialSession(String accessToken) {
  try {
    final payload =
        jsonDecode(
              utf8.decode(
                base64Url.decode(
                  base64Url.normalize(accessToken.split('.')[1]),
                ),
              ),
            )
            as Map<String, dynamic>;
    return (payload['amr'] as List<dynamic>? ?? []).any(
      (method) => method is Map && method['method'] == 'oauth',
    );
  } catch (_) {
    return false;
  }
}
