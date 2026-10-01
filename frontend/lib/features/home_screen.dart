import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/session.dart';
import '../shared/ui.dart';
import 'cargo/cargo_list.dart';
import 'cargo/cargo_detail.dart';
import 'cargo/cargo_form.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key, required this.openCargo, required this.openProfile});
  final VoidCallback openCargo, openProfile;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<Map<String, dynamic>>> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    final session = context.read<Session>();
    future = Future.wait([
      session.api.get('/cargo',
          query: session.isCarrier ? {'status': 'active'} : {'mine': 'true'}),
      if (session.isCarrier) session.api.get('/vehicles'),
      session.api.get('/orders'),
    ]);
  }

  void refresh() => setState(load);
  Future<void> createCargo() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CargoForm()));
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) => PageBody(
      child: AsyncPanel(
          future: future,
          retry: refresh,
          builder: (data) {
            final session = context.watch<Session>();
            final cargos =
                (data.first['results'] as List).cast<Map<String, dynamic>>();
            final vehicles = session.isCarrier
                ? (data[1]['results'] as List).cast<Map<String, dynamic>>()
                : <Map<String, dynamic>>[];
            final vehicle = vehicles.isEmpty ? null : vehicles.first;
            return RefreshIndicator(
                onRefresh: () async {
                  refresh();
                  await future;
                },
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (session.isCarrier) ...[
                        Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                                color: canvas,
                                borderRadius: BorderRadius.circular(12)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('МОЯ МАШИНА',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blueGrey)),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    const Icon(Icons.local_shipping_rounded,
                                        size: 48, color: brandBlue),
                                    const SizedBox(width: 16),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(
                                              vehicle == null
                                                  ? 'Добавьте машину'
                                                  : '${vehicle['brand']} ${vehicle['model']}',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800)),
                                          const SizedBox(height: 4),
                                          Text(
                                              vehicle == null
                                                  ? 'Для отправки предложений'
                                                  : '${label(vehicle['body_type'] as String)} · ${vehicle['capacity_kg']} кг',
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.blueGrey)),
                                          if (vehicle != null)
                                            StatusChip(
                                                vehicle['status'] as String),
                                        ]))
                                  ]),
                                  Row(children: [
                                    const Icon(Icons.location_on_outlined,
                                        size: 16),
                                    const SizedBox(width: 4),
                                    Expanded(
                                        child: Text(vehicle?['current_city']
                                                as String? ??
                                            'Город не указан')),
                                    TextButton(
                                        onPressed: widget.openProfile,
                                        child: const Text('Изменить'))
                                  ]),
                                ])),
                        const SizedBox(height: 24),
                        const Text('Куда хотите ехать?',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                            onPressed: widget.openCargo,
                            icon: const Icon(Icons.search),
                            label: const Text('НАЙТИ ГРУЗ')),
                      ] else ...[
                        Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                                color: const Color(0xFFE8F3FF),
                                borderRadius: BorderRadius.circular(12)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Row(children: [
                                    Expanded(
                                        child: Text('Нужно перевезти груз?',
                                            style: TextStyle(
                                                fontSize: 19,
                                                fontWeight: FontWeight.w800))),
                                    Icon(Icons.inventory_2_rounded,
                                        size: 40, color: brandBlue)
                                  ]),
                                  const SizedBox(height: 8),
                                  const Text(
                                      'Разместите груз и получите предложения от перевозчиков.',
                                      style: TextStyle(color: Colors.blueGrey)),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                      onPressed: createCargo,
                                      icon: const Icon(Icons.add),
                                      label: const Text('РАЗМЕСТИТЬ ГРУЗ')),
                                ])),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(
                              child: _Metric(
                                  title: 'Мои грузы',
                                  value: '${data.first['count']}')),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _Metric(
                                  title: 'Перевозки',
                                  value: '${data.last['count']}'))
                        ]),
                      ],
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(
                            child: Text(
                                session.isCarrier
                                    ? 'Доступные грузы'
                                    : 'Мои грузы',
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800))),
                        TextButton(
                            onPressed: widget.openCargo,
                            child: const Text('Смотреть все'))
                      ]),
                      const SizedBox(height: 8),
                      if (cargos.isEmpty)
                        EmptyState(session.isCarrier
                            ? 'Доступных грузов пока нет'
                            : 'Здесь появятся ваши грузы'),
                      ...cargos.take(4).map((cargo) => CargoCard(
                          cargo: cargo,
                          onTap: () async {
                            await Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) =>
                                    CargoDetail(id: cargo['id'] as int)));
                            if (mounted) refresh();
                          })),
                    ]));
          }));
}

class _Metric extends StatelessWidget {
  const _Metric({required this.title, required this.value});
  final String title, value;
  @override
  Widget build(BuildContext context) => Card(
      margin: EdgeInsets.zero,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Text(title,
                style: const TextStyle(fontSize: 12, color: Colors.blueGrey)),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: brandBlue))
          ])));
}
