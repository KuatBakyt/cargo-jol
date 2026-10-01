import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';
import 'cargo_detail.dart';
import 'cargo_form.dart';

class CargoList extends StatefulWidget {
  const CargoList({super.key, this.favorites = false});
  final bool favorites;
  @override
  State<CargoList> createState() => _CargoListState();
}

class _CargoListState extends State<CargoList> {
  final from = TextEditingController(), to = TextEditingController();
  late Future<Map<String, dynamic>> future;
  int page = 1;
  String ordering = '-created_at';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void didUpdateWidget(CargoList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favorites != widget.favorites) {
      page = 1;
      load();
    }
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  void load() {
    final session = context.read<Session>();
    future =
        session.api.get(widget.favorites ? '/favorites' : '/cargo', query: {
      'page': page,
      if (!widget.favorites) ...{
        'ordering': ordering,
        if (!session.isCarrier) 'mine': 'true',
        if (from.text.trim().isNotEmpty) 'from': from.text.trim(),
        if (to.text.trim().isNotEmpty) 'to': to.text.trim()
      },
    });
  }

  void refresh() => setState(load);
  Future<void> create() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CargoForm()));
    if (mounted) refresh();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return PageBody(
        child: Column(children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                widget.favorites
                    ? 'Сохранённые грузы'
                    : session.isCarrier ? 'Найти груз' : 'Мои грузы',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(widget.favorites
                ? 'Грузы, к которым вы хотите вернуться.'
                : session.isCarrier
                    ? 'Найдите груз для следующего рейса.'
                    : 'Ваши грузы, предложения и перевозки.'),
            const SizedBox(height: 20),
            if (!widget.favorites && !session.isCarrier)
              FilledButton.icon(
                  onPressed: create,
                  icon: const Icon(Icons.add),
                  label: const Text('Разместить груз')),
            if (!widget.favorites) ...[
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: from,
                        decoration: const InputDecoration(
                            labelText: 'Откуда',
                            prefixIcon: Icon(Icons.trip_origin)))),
                const SizedBox(width: 12),
                Expanded(
                    child: TextField(
                        controller: to,
                        decoration: const InputDecoration(
                            labelText: 'Куда',
                            prefixIcon: Icon(Icons.location_on_outlined))))
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: DropdownButtonFormField<String>(
                        initialValue: ordering,
                        decoration:
                            const InputDecoration(labelText: 'Сортировка'),
                        items: const [
                          DropdownMenuItem(
                              value: '-created_at',
                              child: Text('Сначала новые')),
                          DropdownMenuItem(
                              value: 'price',
                              child: Text('Цена по возрастанию')),
                          DropdownMenuItem(
                              value: '-price', child: Text('Цена по убыванию'))
                        ],
                        onChanged: (v) {
                          setState(() {
                            ordering = v!;
                            page = 1;
                            load();
                          });
                        })),
                const SizedBox(width: 12),
                FilledButton(
                    onPressed: () {
                      setState(() {
                        page = 1;
                        load();
                      });
                    },
                    child: const Text('Найти'))
              ]),
            ],
          ])),
      Expanded(
          child: AsyncPanel(
              future: future,
              retry: refresh,
              builder: (data) {
                final rows =
                    (data['results'] as List).cast<Map<String, dynamic>>();
                if (rows.isEmpty) {
                  return RefreshIndicator(
                      onRefresh: () async {
                        refresh();
                        await future;
                      },
                      child: ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            EmptyState(widget.favorites
                                ? 'Здесь появятся сохранённые грузы.'
                                : session.isCarrier
                                    ? 'Грузов по этому маршруту пока нет.'
                                    : 'Разместите первый груз, чтобы получить предложения.')
                          ]));
                }
                return RefreshIndicator(
                    onRefresh: () async {
                      refresh();
                      await future;
                    },
                    child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        children: [
                          ...rows.map((row) {
                            final cargo = widget.favorites
                                ? Map<String, dynamic>.from(row['cargo'] as Map)
                                : row;
                            return CargoCard(
                                cargo: cargo,
                                onTap: () async {
                                  await Navigator.of(context).push(
                                      MaterialPageRoute(
                                          builder: (_) => CargoDetail(
                                              id: cargo['id'] as int)));
                                  if (mounted) refresh();
                                });
                          }),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                    onPressed: data['previous'] == null
                                        ? null
                                        : () {
                                            setState(() {
                                              page--;
                                              load();
                                            });
                                          },
                                    icon: const Icon(Icons.chevron_left)),
                                Text('Страница $page'),
                                IconButton(
                                    onPressed: data['next'] == null
                                        ? null
                                        : () {
                                            setState(() {
                                              page++;
                                              load();
                                            });
                                          },
                                    icon: const Icon(Icons.chevron_right))
                              ]),
                          const SizedBox(height: 20),
                        ]));
              })),
    ]));
  }
}

class CargoCard extends StatelessWidget {
  const CargoCard({super.key, required this.cargo, required this.onTap});
  final Map<String, dynamic> cargo;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.route, color: brandBlue),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(
                              '${cargo['from_city']} → ${cargo['to_city']}',
                              style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w800)))
                    ]),
                    const SizedBox(height: 14),
                    Text(
                        '${cargo['cargo_name']} · ${cargo['weight_kg']} кг · ${label(cargo['body_type'] as String)}'),
                    const SizedBox(height: 6),
                    Text(
                        '${label(cargo['body_type'] as String)} • Загрузка ${cargo['loading_date']}'),
                    const SizedBox(height: 14),
                    Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(money(cargo['price']),
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                  color: ink)),
                          StatusChip(cargo['status'] as String),
                          Text('${cargo['offers_count']} предложений', style: const TextStyle(color: brandBlue, fontSize: 12))
                        ]),
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: FilledButton.tonal(onPressed: onTap, child: const Text('Подробнее'))),
                  ]))));
}
