import '../../core/error_messages.dart';
import '../../shared/home_app_bar.dart';
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/repository.dart';
import '../../core/home_refresh.dart';
import '../../core/translations.dart';
import '../../core/notification_service.dart';
import '../rider/search_screen.dart';
import '../bookings/bookings_screen.dart';
import '../driver/driver_screen.dart';
import '../account/account_screen.dart';
import '../requests/requests_screen.dart';

class HomeScreen extends StatefulWidget {
  final RideRepository repository;
  const HomeScreen({super.key, required this.repository});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Record? _profile;
  List<Record> _routes = [],
      _stops = [],
      _vehicles = [],
      _bookings = [],
      _requests = [],
      _offers = [],
      _notifications = [],
      _violations = [];
  String? _error;
  bool _busy = false, _online = true;
  DateTime? _updated;
  int _tab = 0;
  bool _passengerMode = false;
  RealtimeChannel? _channel;
  StreamSubscription<List<ConnectivityResult>>? _network;
  Timer? _refresh;
  final _refreshQueue = HomeRefreshQueue();
  StreamSubscription<String>? _push;
  @override
  void initState() {
    super.initState();
    _passengerMode = sessionStorage.startAsPassenger;
    _load();
    NotificationService.register();
    _push = NotificationService.foregroundMessages.listen((body) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(body)));
      }
    });
    _network = Connectivity().onConnectivityChanged.listen((result) {
      if (!mounted) return;
      setState(() => _online = !result.contains(ConnectivityResult.none));
      if (_online) _load();
    });
    _channel = widget.repository.client
        .channel('home-${widget.repository.userId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          callback: (event) {
            final resources = homeRefreshResources(event.table);
            if (event.table == 'notifications' &&
                (event.newRecord['kind'] as String? ?? '').startsWith(
                  'document.',
                )) {
              resources.add('vehicles');
            }
            if (resources.isEmpty) return;
            _refreshQueue.add(resources);
            _refresh?.cancel();
            _refresh = Timer(
              const Duration(milliseconds: 500),
              _drainRefreshes,
            );
          },
        )
        .subscribe();
  }

  @override
  void dispose() {
    _network?.cancel();
    _push?.cancel();
    _refresh?.cancel();
    if (_channel != null) widget.repository.client.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    _refreshQueue.add(homeResources);
    await _drainRefreshes();
  }

  Future<dynamic> _fetchResource(String resource) => switch (resource) {
    'profiles' => widget.repository.profile(),
    'bookings' => widget.repository.bookings(),
    'stops' => widget.repository.list('stops', order: 'sequence'),
    _ => widget.repository.list(resource),
  };

  Future<void> _drainRefreshes() async {
    if (_busy || !mounted) return;
    setState(() => _busy = true);
    try {
      while (!_refreshQueue.isEmpty && mounted) {
        final resources = _refreshQueue.take().toList();
        try {
          final results = await Future.wait(resources.map(_fetchResource));
          if (!mounted) return;
          final data = Map<String, dynamic>.fromIterables(resources, results);
          setState(() {
            if (data.containsKey('profiles')) {
              _profile = data['profiles'];
            }
            if (data.containsKey('routes')) {
              _routes = data['routes'];
            }
            if (data.containsKey('stops')) {
              _stops = data['stops'];
            }
            if (data.containsKey('vehicles')) {
              _vehicles = data['vehicles'];
            }
            if (data.containsKey('bookings')) {
              _bookings = data['bookings'];
            }
            if (data.containsKey('ride_requests')) {
              _requests = data['ride_requests'];
            }
            if (data.containsKey('offers')) {
              _offers = data['offers'];
            }
            if (data.containsKey('notifications')) {
              _notifications = data['notifications'];
            }
            if (data.containsKey('violations')) {
              _violations = data['violations'];
            }
            _updated = DateTime.now();
            _error = null;
          });
        } catch (e) {
          if (mounted) setState(() => _error = errorMessage(e));
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final driverAccount = _profile?['role'] == 'driver';
    final driver = driverAccount && !_passengerMode;
    final screens = <Widget>[
      driver
          ? DriverScreen(
              repository: widget.repository,
              vehicles: _vehicles,
              routes: _routes,
              stops: _stops,
              onRefresh: _load,
            )
          : SearchScreen(
              repository: widget.repository,
              routes: _routes,
              stops: _stops,
              onBooked: () {
                setState(() => _tab = 1);
                _load();
              },
            ),
      BookingsScreen(
        repository: widget.repository,
        bookings: _bookings
            .where(
              (booking) => driver
                  ? booking['rider_id'] != widget.repository.userId
                  : booking['rider_id'] == widget.repository.userId,
            )
            .toList(),
        driver: driver,
        onRefresh: _load,
      ),
      RequestsScreen(
        repository: widget.repository,
        requests: _requests,
        offers: _offers,
        driver: driver,
        onRefresh: _load,
      ),
      AccountScreen(
        repository: widget.repository,
        profile: _profile,
        notifications: _notifications,
        violations: _violations,
        onRefresh: _load,
      ),
    ];
    return Scaffold(
      appBar: HomeAppBar(
        driverAccount: driverAccount,
        passengerMode: _passengerMode,
        busy: _busy,
        unreadCount: _notifications
            .where(
              (n) =>
                  n['user_id'] == widget.repository.userId &&
                  n['read_at'] == null,
            )
            .length,
        onSwitchMode: () => setState(() {
          _passengerMode = !_passengerMode;
          _tab = 0;
        }),
        onNotifications: () => setState(() => _tab = 3),
        onLanguage: language.toggle,
        onRefresh: _load,
      ),
      body: Column(
        children: [
          if (!_online)
            MaterialBanner(
              content: Text(
                language.text(
                  'غير متصل · التغييرات متوقفة',
                  'Offline · changes are disabled',
                ),
              ),
              actions: const [SizedBox.shrink()],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.deepOrange),
              ),
            ),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _profile == null
                ? Center(
                    child: Text(
                      language.text(
                        'جارٍ تحميل حسابك…',
                        'Loading your account…',
                      ),
                    ),
                  )
                : AbsorbPointer(
                    absorbing: !_online,
                    child: IndexedStack(index: _tab, children: screens),
                  ),
          ),
          if (_updated != null)
            Padding(
              padding: const EdgeInsets.all(4),
              child: Text(
                '${language.text('آخر تحديث', 'Last update')}: ${TimeOfDay.fromDateTime(_updated!).format(context)}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: [
          NavigationDestination(
            icon: Icon(driver ? Icons.directions_bus_outlined : Icons.search),
            label: driver
                ? language.text('سيارتي', 'My vehicle')
                : language.text('رحلتي', 'Find a ride'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.confirmation_number_outlined),
            label: language.text('الحجوزات', 'Bookings'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.forum_outlined),
            label: language.text('الطلبات', 'Requests'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            label: language.text('حسابي', 'Account'),
          ),
        ],
      ),
    );
  }
}
