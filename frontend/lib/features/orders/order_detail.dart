import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';
import 'chat_screen.dart';

const progressStates = [
  'carrier_selected',
  'heading_to_pickup',
  'loading',
  'in_transit',
  'delivered',
  'completed'
];

class OrderDetail extends StatefulWidget {
  const OrderDetail({super.key, required this.id});
  final int id;
  @override
  State<OrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<OrderDetail> {
  late Future<Map<String, dynamic>> future;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = context.read<Session>().api.get('/orders/${widget.id}');
  }

  void refresh() => setState(load);
  Future<void> change(String status) async {
    if (status == 'cancelled') {
      final yes = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Отменить перевозку?'),
                  content:
                      const Text('Заказ будет отменён, машина освободится.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Назад')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Отменить'))
                  ]));
      if (yes != true) return;
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await context
          .read<Session>()
          .api
          .patch('/orders/${widget.id}/status', {'status': status});
      if (mounted) refresh();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text('Заказ №${widget.id}'), actions: [
        IconButton(onPressed: refresh, icon: const Icon(Icons.refresh))
      ]),
      body: PageBody(
          child: AsyncPanel(
              future: future,
              retry: refresh,
              builder: (order) {
                final session = context.watch<Session>();
                final status = order['status'] as String;
                final current = progressStates.indexOf(status);
                final carrier = order['carrier'] == session.userId;
                final next = carrier && current >= 0 && current < 4
                    ? progressStates[current + 1]
                    : !carrier && status == 'delivered'
                        ? 'completed'
                        : null;
                return ListView(padding: const EdgeInsets.all(24), children: [
                  Text(money(order['agreed_price']),
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                          color: brandBlue)),
                  StatusChip(status),
                  const SizedBox(height: 16),
                  Text(
                      'Грузовладелец: ${order['shipper_profile']['first_name']}'),
                  Text('Перевозчик: ${order['carrier_profile']['first_name']}'),
                  const SizedBox(height: 24),
                  ...progressStates.asMap().entries.map((e) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                          current >= e.key
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          color: current >= e.key ? brandBlue : Colors.grey),
                      title: Text(label(e.value)))),
                  if (next != null)
                    FilledButton(
                        onPressed: busy ? null : () => change(next),
                        child: Text(busy
                            ? 'Сохраняем…'
                            : next == 'completed'
                                ? 'Подтвердить получение груза'
                                : label(next))),
                  if (carrier && status == 'delivered')
                    const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                            'Ожидаем подтверждение получения от грузовладельца.')),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => ChatScreen(
                                  id: order['conversation_id'] as int))),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Открыть чат')),
                  if (current >= 0 && current < 3)
                    TextButton(
                        onPressed: busy ? null : () => change('cancelled'),
                        child: const Text('Отменить перевозку',
                            style: TextStyle(color: Colors.red))),
                  if (status == 'completed') ...[
                    const SizedBox(height: 24),
                    ReviewPanel(orderId: widget.id)
                  ],
                ]);
              })));
}

class ReviewPanel extends StatefulWidget {
  const ReviewPanel({super.key, required this.orderId});
  final int orderId;
  @override
  State<ReviewPanel> createState() => _ReviewPanelState();
}

class _ReviewPanelState extends State<ReviewPanel> {
  final comment = TextEditingController();
  late Future<List<dynamic>> future;
  int rating = 5;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = context
        .read<Session>()
        .api
        .dio
        .get('/orders/${widget.orderId}/reviews')
        .then((r) => r.data as List);
  }

  @override
  void dispose() {
    comment.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    setState(() => busy = true);
    try {
      await context.read<Session>().api.post(
          '/orders/${widget.orderId}/reviews',
          {'rating': rating, 'comment': comment.text.trim()});
      if (mounted) setState(load);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AsyncPanel(
      future: future,
      retry: () => setState(load),
      builder: (rows) {
        final own =
            rows.any((r) => r['author'] == context.read<Session>().userId);
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Отзывы о перевозке',
                  style: Theme.of(context).textTheme.titleLarge),
              ...rows.map((r) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.star, color: Colors.amber),
                  title: Text('${r['rating']} / 5'),
                  subtitle: Text(r['comment'] as String))),
              if (!own) ...[
                const SizedBox(height: 16),
                Wrap(
                    children: List.generate(
                        5,
                        (i) => IconButton(
                            tooltip: '${i + 1} из 5',
                            onPressed: busy
                                ? null
                                : () => setState(() => rating = i + 1),
                            icon: Icon(
                                i < rating ? Icons.star : Icons.star_border,
                                color: Colors.amber)))),
                TextField(
                    controller: comment,
                    maxLines: 3,
                    decoration: const InputDecoration(
                        labelText: 'Как прошла перевозка?')),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'Отправляем…' : 'Оставить отзыв'))
              ]
            ]);
      });
}
