import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../shared/ui.dart';

class CargoForm extends StatefulWidget {
  const CargoForm({super.key});
  @override
  State<CargoForm> createState() => _CargoFormState();
}

class _CargoFormState extends State<CargoForm> {
  final forms = List.generate(3, (_) => GlobalKey<FormState>());
  final fields = {
    for (final key in [
      'from_city',
      'to_city',
      'from_address',
      'to_address',
      'cargo_name',
      'weight_kg',
      'volume_m3',
      'price',
      'description'
    ])
      key: TextEditingController()
  };
  DateTime date =
      DateUtils.dateOnly(DateTime.now()).add(const Duration(days: 1));
  String body = 'tent', payment = 'bank_transfer';
  int step = 0;
  bool busy = false;
  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  String? positive(String? value, {bool zero = false}) {
    final n = double.tryParse((value ?? '').replaceAll(',', '.'));
    return n != null && n.isFinite && (zero ? n >= 0 : n > 0)
        ? null
        : zero
            ? 'Введите число от 0'
            : 'Введите число больше 0';
  }

  Widget input(String key, String title,
          {bool number = false, bool optional = false}) =>
      FormFieldInput(title, fields[key]!,
          number: number,
          required: !optional,
          lines: key == 'description' ? 3 : 1,
          validator:
              number ? (v) => positive(v, zero: key == 'volume_m3') : null);
  Future<void> publish() async {
    for (var i = 0; i < forms.length; i++) {
      if (!forms[i].currentState!.validate()) {
        setState(() => step = i);
        return;
      }
    }
    if (fields['from_city']!.text.trim().toLowerCase() ==
        fields['to_city']!.text.trim().toLowerCase()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Города отправления и назначения должны отличаться')));
      return;
    }
    setState(() => busy = true);
    try {
      await context.read<Session>().api.post('/cargo', {
        for (final entry in fields.entries)
          entry.key: ['weight_kg', 'volume_m3', 'price'].contains(entry.key)
              ? entry.value.text.trim().replaceAll(',', '.')
              : entry.value.text.trim(),
        'cargo_type': 'general',
        'body_type': body,
        'payment_type': payment,
        'loading_date': date.toIso8601String().split('T').first,
        'status': 'active',
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Разместить груз')),
      body: PageBody(
          child: Stepper(
              currentStep: step,
              onStepTapped: busy ? null : (i) => setState(() => step = i),
              onStepContinue: busy
                  ? null
                  : () {
                      if (!forms[step].currentState!.validate()) return;
                      if (step < 2) {
                        setState(() => step++);
                      } else {
                        publish();
                      }
                    },
              onStepCancel:
                  busy || step == 0 ? null : () => setState(() => step--),
              controlsBuilder: (context, details) => Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(children: [
                    FilledButton(
                        onPressed: details.onStepContinue,
                        child: Text(busy
                            ? 'Публикуем…'
                            : step == 2
                                ? 'Опубликовать'
                                : 'Далее')),
                    const SizedBox(width: 12),
                    if (step > 0)
                      TextButton(
                          onPressed: details.onStepCancel,
                          child: const Text('Назад'))
                  ])),
              steps: [
            Step(
                title: const Text('Маршрут'),
                isActive: step >= 0,
                content: Form(
                    key: forms[0],
                    child: Column(children: [
                      input('from_city', 'Город отправления'),
                      input('to_city', 'Город назначения'),
                      input('from_address', 'Адрес загрузки'),
                      input('to_address', 'Адрес разгрузки'),
                      ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.calendar_month),
                          title: const Text('Дата загрузки'),
                          subtitle:
                              Text(date.toIso8601String().split('T').first),
                          onTap: () async {
                            final now = DateUtils.dateOnly(DateTime.now());
                            final picked = await showDatePicker(
                                context: context,
                                initialDate: date.isBefore(now) ? now : date,
                                firstDate: now,
                                lastDate: now.add(const Duration(days: 365)));
                            if (picked != null) setState(() => date = picked);
                          })
                    ]))),
            Step(
                title: const Text('Груз'),
                isActive: step >= 1,
                content: Form(
                    key: forms[1],
                    child: Column(children: [
                      input('cargo_name', 'Название груза'),
                      input('weight_kg', 'Вес, кг', number: true),
                      input('volume_m3', 'Объём, м³', number: true),
                      DropdownButtonFormField<String>(
                          initialValue: body,
                          decoration:
                              const InputDecoration(labelText: 'Тип кузова'),
                          items: ['tent', 'refrigerator', 'van', 'flatbed']
                              .map((v) => DropdownMenuItem(
                                  value: v, child: Text(label(v))))
                              .toList(),
                          onChanged: (v) => setState(() => body = v!))
                    ]))),
            Step(
                title: const Text('Условия'),
                isActive: step >= 2,
                content: Form(
                    key: forms[2],
                    child: Column(children: [
                      input('price', 'Цена, ₸', number: true),
                      DropdownButtonFormField<String>(
                          initialValue: payment,
                          decoration:
                              const InputDecoration(labelText: 'Способ оплаты'),
                          items: const [
                            DropdownMenuItem(
                                value: 'bank_transfer',
                                child: Text('Банковский перевод')),
                            DropdownMenuItem(
                                value: 'cash', child: Text('Наличные'))
                          ],
                          onChanged: (v) => setState(() => payment = v!)),
                      const SizedBox(height: 16),
                      input('description', 'Комментарий', optional: true)
                    ]))),
          ])));
}
