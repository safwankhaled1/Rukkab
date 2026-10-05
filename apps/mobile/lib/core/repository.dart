import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef Record = Map<String, dynamic>;

final sessionStorage = SecureSessionStorage();

class SecureSessionStorage extends LocalStorage {
  /// A screen preference only; server roles still authorize every operation.
  bool startAsPassenger = false;
  final _storage = const FlutterSecureStorage();
  bool _remember = true;

  /// Turning persistence off removes the saved session, without signing out
  /// the current in-memory session. Refreshes must not save it again.
  Future<void> setRemember(bool remember) async {
    await _storage.write(key: 'rukkab_remember_session', value: '$remember');
    _remember = remember;
    if (!remember) await removePersistedSession();
  }

  @override
  Future<void> initialize() async {
    _remember = await _storage.read(key: 'rukkab_remember_session') != 'false';
    if (!_remember) await removePersistedSession();
  }

  @override
  Future<bool> hasAccessToken() async =>
      await _storage.containsKey(key: 'rukkab_session');
  @override
  Future<String?> accessToken() => _storage.read(key: 'rukkab_session');
  @override
  Future<void> persistSession(String persistSessionString) async {
    if (_remember) {
      await _storage.write(key: 'rukkab_session', value: persistSessionString);
    } else {
      await removePersistedSession();
    }
  }

  @override
  Future<void> removePersistedSession() =>
      _storage.delete(key: 'rukkab_session');
}

class RideRepository {
  final SupabaseClient client;
  RideRepository(this.client);
  String get userId => client.auth.currentUser!.id;
  Future<void> requireConnection() async {
    final result = await Connectivity().checkConnectivity();
    if (result.every((x) => x == ConnectivityResult.none)) {
      throw const AppFailure('OFFLINE');
    }
  }

  Future<dynamic> rpc(String name, Record parameters) async {
    await requireConnection();
    return client.rpc(name, params: parameters);
  }

  Future<List<Record>> list(
    String table, {
    String? key,
    dynamic value,
    String order = 'created_at',
  }) async {
    // Route catalogs must not silently stop at 100 entries as coverage grows.
    final complete = ['routes', 'stops', 'vehicle_routes'].contains(table);
    final rows = <Record>[];
    var offset = 0;
    do {
      dynamic query = client.from(table).select();
      if (key != null) query = query.eq(key, value);
      query = query.order(order, ascending: table == 'stops');
      query = query.order(table == 'vehicle_routes' ? 'route_id' : 'id');
      final List<dynamic> page = await query.range(offset, offset + 99);
      rows.addAll(page.map((e) => Map<String, dynamic>.from(e)));
      if (!complete || page.length < 100) break;
      offset += 100;
    } while (true);
    return rows;
  }

  Future<Record> profile() async => Map<String, dynamic>.from(
    await client.from('profiles').select().eq('id', userId).single(),
  );
  Future<Record?> driverIdentity() async => await client
      .from('driver_details')
      .select()
      .eq('user_id', userId)
      .maybeSingle();
  Future<bool> vehicleReady(String id) async =>
      await rpc('vehicle_ready', {'v': id}) as bool;
  Future<List<Record>> bookings() async {
    const activeStates = [
      'pending',
      'confirmed',
      'boarded',
      'reschedule_pending',
    ];
    final all = <String, Record>{};
    var offset = 0;
    // Keep all actionable bookings even when older history exceeds one page.
    while (true) {
      final rows = await client
          .from('bookings')
          .select('*, trips(*), profiles(full_name)')
          .inFilter('state', activeStates)
          .order('created_at', ascending: false)
          .order('id')
          .range(offset, offset + 99);
      for (final row in rows) {
        all[row['id']] = Map<String, dynamic>.from(row);
      }
      if (rows.length < 100) break;
      offset += 100;
    }
    final history = await client
        .from('bookings')
        .select('*, trips(*), profiles(full_name)')
        .not('state', 'in', '(pending,confirmed,boarded,reschedule_pending)')
        .order('created_at', ascending: false)
        .order('id')
        .limit(100);
    for (final row in history) {
      all[row['id']] = Map<String, dynamic>.from(row);
    }
    return all.values.toList()..sort(
      (a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String),
    );
  }

  /// Resolve every displayed offer directly, even when its trip is older than the newest page.
  Future<List<Record>> tripsForOffers(Iterable<String> tripIds) async {
    final ids = tripIds.toSet().toList();
    final trips = <Record>[];
    for (var offset = 0; offset < ids.length; offset += 100) {
      final end = (offset + 100).clamp(0, ids.length);
      final rows = await client
          .from('trips')
          .select()
          .inFilter('id', ids.sublist(offset, end));
      trips.addAll(rows.map((row) => Map<String, dynamic>.from(row)));
    }
    return trips;
  }

  /// Load every eligible published trip for these vehicles, without scanning the public fleet.
  Future<List<Record>> publishedTripsForVehicles(
    Iterable<String> vehicleIds,
  ) async {
    final ids = vehicleIds.toSet().toList();
    final trips = <Record>[];
    final now = DateTime.now().toUtc().toIso8601String();
    for (var start = 0; start < ids.length; start += 100) {
      final end = (start + 100).clamp(0, ids.length);
      var offset = 0;
      while (true) {
        final rows = await client
            .from('trips')
            .select()
            .inFilter('vehicle_id', ids.sublist(start, end))
            .eq('state', 'published')
            .gt('ends_at', now)
            .order('starts_at', ascending: true)
            .order('id', ascending: true)
            .range(offset, offset + 99);
        trips.addAll(rows.map((row) => Map<String, dynamic>.from(row)));
        if (rows.length < 100) break;
        offset += 100;
      }
    }
    return trips;
  }

  /// Embed seat-only booking data in the same read; keep all live trips beyond the history bound.
  Future<List<Record>> vehicleTrips(String vehicleId) async {
    final trips = <Record>[];
    var offset = 0;
    while (true) {
      final rows = await client
          .from('trips')
          .select('*, bookings(seats,state)')
          .eq('vehicle_id', vehicleId)
          .inFilter('state', ['published', 'active'])
          .order('starts_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + 99);
      trips.addAll(rows.map((row) => Map<String, dynamic>.from(row)));
      if (rows.length < 100) break;
      offset += 100;
    }
    final history = await client
        .from('trips')
        .select('*, bookings(seats,state)')
        .eq('vehicle_id', vehicleId)
        .not('state', 'in', '(published,active)')
        .order('created_at', ascending: false)
        .order('id', ascending: true)
        .limit(100);
    final byId = {for (final trip in trips) trip['id']: trip};
    for (final row in history) {
      byId.putIfAbsent(row['id'], () => Map<String, dynamic>.from(row));
    }
    return byId.values.toList();
  }

  Future<List<Record>> search(Record p) async {
    final List<dynamic> rows = await rpc('search_trips', {'p': p});
    return rows.map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> bookingAction(String id, String action) async =>
      rpc('booking_action', {'bid': id, 'a': action, 'reason': null});
  Future<void> tripAction(
    String id,
    String action, [
    Record p = const {},
  ]) async => rpc('trip_action', {'tid': id, 'a': action, 'p': p});
  Future<void> accountAction(String action, Record p) async =>
      rpc('account_action', {'a': action, 'p': p});
  Future<void> uploadDocument({
    required String vehicleId,
    required String kind,
    required String filename,
    required List<int> bytes,
    required String? expiresOn,
  }) async {
    await requireConnection();
    final extension = filename.split('.').last.toLowerCase();
    if (kind == 'vehicle_photo' && extension == 'pdf') {
      throw const AppFailure('DOCUMENT_FORMAT');
    }
    if (kind != 'vehicle_photo' && (expiresOn == null || expiresOn.isEmpty)) {
      throw const AppFailure('DOCUMENT_EXPIRY_REQUIRED');
    }
    if (!['pdf', 'png', 'jpg', 'jpeg'].contains(extension)) {
      throw const AppFailure('DOCUMENT_FORMAT');
    }
    if (bytes.length > 10 * 1024 * 1024) {
      throw const AppFailure('DOCUMENT_TOO_LARGE');
    }
    final path =
        '$userId/$vehicleId/${DateTime.now().microsecondsSinceEpoch}.$extension';
    await client.storage
        .from('driver-documents')
        .uploadBinary(
          path,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: extension == 'pdf'
                ? 'application/pdf'
                : extension == 'png'
                ? 'image/png'
                : 'image/jpeg',
          ),
        );
    await accountAction('document', {
      'vehicle_id': vehicleId,
      'kind': kind,
      'storage_path': path,
      'expires_on': expiresOn,
    });
  }
}

class AppFailure implements Exception {
  final String code;
  const AppFailure(this.code);
  @override
  String toString() => code;
}
