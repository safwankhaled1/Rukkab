import 'package:flutter/material.dart';
import '../core/translations.dart';
import 'brand_mark.dart';

/// Keep the same actions reachable on narrow screens and with larger text.
class HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool driverAccount, passengerMode, busy;
  final int unreadCount;
  final VoidCallback onSwitchMode, onNotifications, onLanguage, onRefresh;
  const HomeAppBar({
    super.key,
    required this.driverAccount,
    required this.passengerMode,
    required this.busy,
    required this.unreadCount,
    required this.onSwitchMode,
    required this.onNotifications,
    required this.onLanguage,
    required this.onRefresh,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(
    title: Row(
      children: [
        const BrandMark(size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Text('ركاب', maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
    actions: [
      IconButton(
        tooltip: language.text('الإشعارات', 'Notifications'),
        onPressed: onNotifications,
        icon: Badge(
          isLabelVisible: unreadCount > 0,
          label: Text(unreadCount > 99 ? '99+' : '$unreadCount'),
          child: const Icon(Icons.notifications_outlined),
        ),
      ),
      PopupMenuButton<String>(
        tooltip: language.text('خيارات الحساب', 'Account options'),
        onSelected: (action) {
          switch (action) {
            case 'mode':
              onSwitchMode();
            case 'language':
              onLanguage();
            case 'refresh':
              onRefresh();
          }
        },
        itemBuilder: (_) => [
          PopupMenuItem<String>(
            enabled: false,
            child: Text(
              driverAccount && !passengerMode
                  ? language.text('وضع السائق', 'Driver mode')
                  : language.text('وضع الراكب', 'Passenger mode'),
            ),
          ),
          if (driverAccount)
            PopupMenuItem<String>(
              value: 'mode',
              child: Text(
                passengerMode
                    ? language.text('العودة لوضع السائق', 'Switch to driving')
                    : language.text(
                        'حجز رحلة كراكب',
                        'Book a ride as a passenger',
                      ),
              ),
            ),
          PopupMenuItem<String>(
            value: 'language',
            child: Text(language.text('English', 'العربية')),
          ),
          PopupMenuItem<String>(
            value: 'refresh',
            enabled: !busy,
            child: Text(language.text('تحديث البيانات', 'Refresh data')),
          ),
        ],
      ),
    ],
  );
}
