import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../shared/ui.dart';
import 'cargo/cargo_list.dart';
import 'orders/orders_screen.dart';
import 'profile/profile_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final carrier = context.watch<Session>().isCarrier;
    final pages = [
      const CargoList(),
      const OrdersScreen(),
      const CargoList(favorites: true),
      const ProfileScreen()
    ];
    final destinations = [
      NavigationDestination(
          icon: const Icon(Icons.dashboard_outlined),
          selectedIcon: const Icon(Icons.dashboard),
          label: carrier ? 'Грузы' : 'Мои грузы'),
      const NavigationDestination(
          icon: Icon(Icons.route_outlined), label: 'Заказы'),
      const NavigationDestination(
          icon: Icon(Icons.bookmark_border), label: 'Избранное'),
      const NavigationDestination(
          icon: Icon(Icons.person_outline), label: 'Профиль')
    ];
    return Scaffold(
      appBar: AppBar(
          title: const Text('JOL CARGO',
              style:
                  TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5)),
          actions: [
            IconButton(
                tooltip: 'Уведомления',
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NotificationsScreen())),
                icon: const Icon(Icons.notifications_none)),
            const SizedBox(width: 12)
          ]),
      body: Row(children: [
        if (MediaQuery.sizeOf(context).width > 850)
          NavigationRail(
              selectedIndex: selected,
              onDestinationSelected: (v) => setState(() => selected = v),
              labelType: NavigationRailLabelType.all,
              destinations: destinations
                  .map((d) => NavigationRailDestination(
                      icon: d.icon,
                      selectedIcon: d.selectedIcon,
                      label: Text(d.label)))
                  .toList()),
        Expanded(child: pages[selected])
      ]),
      bottomNavigationBar: MediaQuery.sizeOf(context).width <= 850
          ? NavigationBar(
              selectedIndex: selected,
              onDestinationSelected: (v) => setState(() => selected = v),
              destinations: destinations)
          : null,
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = context.read<Session>().api.get('/notifications');
  }

  void refresh() => setState(load);
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Уведомления')),
      body: PageBody(
          child: AsyncPanel(
              future: future,
              retry: refresh,
              builder: (data) {
                final rows =
                    (data['results'] as List).cast<Map<String, dynamic>>();
                if (rows.isEmpty)
                  return const EmptyState('Уведомлений пока нет');
                return ListView(children: [
                  TextButton(
                      onPressed: () async {
                        try {
                          await context
                              .read<Session>()
                              .api
                              .post('/notifications/read-all');
                          if (mounted) refresh();
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      },
                      child: const Text('Прочитать все')),
                  ...rows.map((n) => ListTile(
                      leading: Icon(
                          n['is_read'] == true
                              ? Icons.notifications_none
                              : Icons.notifications_active,
                          color: green),
                      title: Text(n['title'] as String),
                      subtitle: Text(n['message'] as String? ?? ''),
                      trailing: n['is_read'] == true
                          ? null
                          : const Icon(Icons.circle, size: 8, color: green),
                      onTap: () async {
                        try {
                          await context
                              .read<Session>()
                              .api
                              .post('/notifications/${n['id']}/read');
                          if (mounted) refresh();
                        } catch (e) {
                          if (context.mounted) showError(context, e);
                        }
                      }))
                ]);
              })));
}
