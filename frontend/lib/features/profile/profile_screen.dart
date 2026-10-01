import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    return PageBody(
        child: ListView(padding: const EdgeInsets.all(24), children: [
      Row(children: [
        const CircleAvatar(
            radius: 32,
            backgroundColor: green,
            child: Icon(Icons.person, color: Colors.white, size: 34)),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(session.name, style: Theme.of(context).textTheme.headlineSmall),
          Text(session.isCarrier ? 'Перевозчик' : 'Грузовладелец')
        ]))
      ]),
      const SizedBox(height: 24),
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.mail_outline),
          title: Text(session.user!['email'] as String)),
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.phone_outlined),
          title: Text(session.user!['phone'] as String)),
      const Divider(height: 32),
      if (session.isCarrier) const VehiclesPanel(),
      const SizedBox(height: 24),
      const CompanyPanel(),
      const SizedBox(height: 32),
      OutlinedButton.icon(
          onPressed: session.logout,
          icon: const Icon(Icons.logout),
          label: const Text('Выйти из аккаунта')),
    ]));
  }
}

class VehiclesPanel extends StatefulWidget {
  const VehiclesPanel({super.key});
  @override
  State<VehiclesPanel> createState() => _VehiclesPanelState();
}

class _VehiclesPanelState extends State<VehiclesPanel> {
  late Future<Map<String, dynamic>> future;
  int page = 1;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future =
        context.read<Session>().api.get('/vehicles', query: {'page': page});
  }

  Future<void> add() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const VehicleForm()));
    if (mounted) setState(load);
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Text('Мой транспорт',
                  style: Theme.of(context).textTheme.titleLarge)),
          TextButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: const Text('Добавить'))
        ]),
        AsyncPanel(
            future: future,
            retry: () => setState(load),
            builder: (data) {
              final rows =
                  (data['results'] as List).cast<Map<String, dynamic>>();
              return Column(children: [
                if (rows.isEmpty)
                  const EmptyState(
                      'Добавьте машину, чтобы предлагать перевозку.'),
                ...rows.map((v) => Card(
                    elevation: 0,
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${v['brand']} ${v['model']} • ${v['plate_number']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800)),
                              Text(
                                  '${label(v['body_type'] as String)} • ${v['capacity_kg']} кг • ${v['volume_m3']} м³'),
                              Text(v['current_city'] as String),
                              StatusChip(v['status'] as String)
                            ])))),
                if (data['next'] != null || page > 1)
                  Row(children: [
                    IconButton(
                        onPressed: page <= 1
                            ? null
                            : () => setState(() {
                                  page--;
                                  load();
                                }),
                        icon: const Icon(Icons.chevron_left)),
                    Text('$page'),
                    IconButton(
                        onPressed: data['next'] == null
                            ? null
                            : () => setState(() {
                                  page++;
                                  load();
                                }),
                        icon: const Icon(Icons.chevron_right))
                  ])
              ]);
            })
      ]);
}

class VehicleForm extends StatefulWidget {
  const VehicleForm({super.key});
  @override
  State<VehicleForm> createState() => _VehicleFormState();
}

class _VehicleFormState extends State<VehicleForm> {
  final form = GlobalKey<FormState>();
  final fields = {
    for (final k in [
      'brand',
      'model',
      'plate_number',
      'capacity_kg',
      'volume_m3',
      'current_city'
    ])
      k: TextEditingController()
  };
  String body = 'tent';
  bool busy = false;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await context.read<Session>().api.post('/vehicles', {
        for (final e in fields.entries)
          e.key: e.value.text.trim().replaceAll(
              ',', ['capacity_kg', 'volume_m3'].contains(e.key) ? '.' : ','),
        'body_type': body,
        'status': 'available'
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Добавить машину')),
      body: PageBody(
          child: ListView(padding: const EdgeInsets.all(24), children: [
        Form(
            key: form,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormFieldInput('Марка', fields['brand']!),
                  FormFieldInput('Модель', fields['model']!),
                  FormFieldInput('Госномер', fields['plate_number']!),
                  FormFieldInput('Текущий город', fields['current_city']!),
                  ...['capacity_kg', 'volume_m3'].map((k) => FormFieldInput(
                          k == 'capacity_kg'
                              ? 'Грузоподъёмность, кг'
                              : 'Объём, м³',
                          fields[k]!,
                          number: true, validator: (v) {
                        final n =
                            double.tryParse((v ?? '').replaceAll(',', '.'));
                        return n != null &&
                                n.isFinite &&
                                (k == 'capacity_kg' ? n > 0 : n >= 0)
                            ? null
                            : 'Введите допустимое число';
                      })),
                  DropdownButtonFormField<String>(
                      initialValue: body,
                      decoration:
                          const InputDecoration(labelText: 'Тип кузова'),
                      items: ['tent', 'refrigerator', 'van', 'flatbed']
                          .map((v) =>
                              DropdownMenuItem(value: v, child: Text(label(v))))
                          .toList(),
                      onChanged: (v) => setState(() => body = v!)),
                  const SizedBox(height: 24),
                  FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(busy ? 'Сохраняем…' : 'Добавить машину')),
                ]))
      ])));
}

class CompanyPanel extends StatefulWidget {
  const CompanyPanel({super.key});
  @override
  State<CompanyPanel> createState() => _CompanyPanelState();
}

class _CompanyPanelState extends State<CompanyPanel> {
  late Future<Map<String, dynamic>> future;
  @override
  void initState() {
    super.initState();
    load();
  }

  void load() {
    future = context.read<Session>().api.get('/companies');
  }

  Future<void> add() async {
    await Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CompanyForm()));
    if (mounted) setState(load);
  }

  @override
  Widget build(BuildContext context) => AsyncPanel(
      future: future,
      retry: () => setState(load),
      builder: (data) {
        final rows = data['results'] as List;
        if (rows.isEmpty) {
          return OutlinedButton.icon(
              onPressed: add,
              icon: const Icon(Icons.business_outlined),
              label: const Text('Добавить компанию'));
        }
        final company = rows.first as Map;
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Компания', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(company['name'] as String,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text('БИН ${company['bin']}'),
              Text(
                  'Рейтинг ${company['rating']} • ${company['completed_orders']} завершённых перевозок'),
              StatusChip(company['verification_status'] as String),
              if (['unverified', 'rejected']
                  .contains(company['verification_status']))
                OutlinedButton(
                    onPressed: () async {
                      try {
                        await context.read<Session>().api.post(
                            '/companies/${company['id']}/request-verification');
                        if (mounted) setState(load);
                      } catch (e) {
                        if (context.mounted) showError(context, e);
                      }
                    },
                    child: const Text('Отправить на проверку'))
            ]);
      });
}

class CompanyForm extends StatefulWidget {
  const CompanyForm({super.key});
  @override
  State<CompanyForm> createState() => _CompanyFormState();
}

class _CompanyFormState extends State<CompanyForm> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      bin = TextEditingController(),
      address = TextEditingController();
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    bin.dispose();
    address.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await context.read<Session>().api.post('/companies', {
        'name': name.text.trim(),
        'bin': bin.text.trim(),
        'address': address.text.trim()
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Компания')),
      body: PageBody(
          child: ListView(padding: const EdgeInsets.all(24), children: [
        Form(
            key: form,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormFieldInput('Название', name),
                  FormFieldInput('БИН', bin,
                      validator: (v) => RegExp(r'^\d{12}$').hasMatch(v ?? '')
                          ? null
                          : 'БИН должен содержать 12 цифр'),
                  FormFieldInput('Адрес', address, required: false),
                  FilledButton(
                      onPressed: busy ? null : submit,
                      child: Text(busy ? 'Сохраняем…' : 'Добавить компанию'))
                ]))
      ])));
}
