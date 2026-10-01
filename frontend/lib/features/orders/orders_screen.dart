import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';
import 'order_detail.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  late Future<Map<String, dynamic>> future;
  int page = 1;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = context.read<Session>().api.get('/orders', query: {'page': page});
  }

  void refresh() => setState(load);
  @override
  Widget build(BuildContext context) => PageBody(
      child: AsyncPanel(
          future: future,
          retry: refresh,
          builder: (data) {
            final rows = (data['results'] as List).cast<Map<String, dynamic>>();
            return RefreshIndicator(
                onRefresh: () async {
                  refresh();
                  await future;
                },
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text('Мои перевозки',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 20),
                      if (rows.isEmpty)
                        const EmptyState(
                            'После выбора перевозчика здесь появится заказ.'),
                      ...rows.map((order) => Card(
                          elevation: 0,
                          child: ListTile(
                              contentPadding: const EdgeInsets.all(16),
                              leading: const Icon(Icons.local_shipping_outlined,
                                  color: green),
                              title: Text(
                                  'Заказ №${order['id']} • ${money(order['agreed_price'])}'),
                              subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${order['shipper_profile']['first_name']} → ${order['carrier_profile']['first_name']}'),
                                    StatusChip(order['status'] as String)
                                  ]),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () async {
                                await Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => OrderDetail(
                                            id: order['id'] as int)));
                                if (mounted) refresh();
                              }))),
                      Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                                onPressed: data['previous'] == null
                                    ? null
                                    : () => setState(() {
                                          page--;
                                          load();
                                        }),
                                icon: const Icon(Icons.chevron_left)),
                            Text('Страница $page'),
                            IconButton(
                                onPressed: data['next'] == null
                                    ? null
                                    : () => setState(() {
                                          page++;
                                          load();
                                        }),
                                icon: const Icon(Icons.chevron_right))
                          ])
                    ]));
          }));
}
