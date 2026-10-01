import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/api_client.dart';

const ink = Color(0xFF101B3D);
const brandBlue = Color(0xFF0866FF);
const canvas = Color(0xFFF5F8FC);

String money(dynamic value) =>
    '${NumberFormat('#,##0', 'ru').format(double.tryParse('$value') ?? 0)} ₸';
String label(String value) =>
    const {
      'draft': 'Черновик',
      'active': 'Активен',
      'assigned': 'Перевозчик выбран',
      'in_transit': 'В пути',
      'completed': 'Завершён',
      'cancelled': 'Отменён',
      'carrier_selected': 'Перевозчик выбран',
      'heading_to_pickup': 'На пути к загрузке',
      'loading': 'На загрузке',
      'delivered': 'Доставлено',
      'pending': 'Ожидает решения',
      'accepted': 'Принято',
      'rejected': 'Отклонено',
      'available': 'Свободен',
      'busy': 'Занят',
      'inactive': 'Неактивен',
      'tent': 'Тент',
      'refrigerator': 'Рефрижератор',
      'van': 'Фургон',
      'flatbed': 'Бортовой',
      'unverified': 'Не проверена',
      'verified': 'Проверена',
    }[value] ??
    value;

void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(errorText(error)), backgroundColor: Colors.red.shade800));
}

class AsyncPanel<T> extends StatelessWidget {
  const AsyncPanel(
      {super.key,
      required this.future,
      required this.builder,
      required this.retry});
  final Future<T> future;
  final Widget Function(T) builder;
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.cloud_off_outlined, size: 48),
                      const SizedBox(height: 16),
                      Text(errorText(snapshot.error!),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      OutlinedButton(
                          onPressed: retry, child: const Text('Повторить'))
                    ])));
          }
          return builder(snapshot.data as T);
        },
      );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.all(36),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 52, color: brandBlue),
        const SizedBox(height: 16),
        Text(text, textAlign: TextAlign.center)
      ]));
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) => Chip(
      label: Text(label(status), style: const TextStyle(fontSize: 12)),
      backgroundColor: (['active', 'available', 'accepted', 'completed', 'verified'].contains(status) ? const Color(0xFF08A65A) : brandBlue).withValues(alpha: .10),
      side: BorderSide.none);
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Center(
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760), child: child));
}

class FormFieldInput extends StatelessWidget {
  const FormFieldInput(this.title, this.controller,
      {super.key,
      this.number = false,
      this.required = true,
      this.lines = 1,
      this.validator,
      this.obscure = false});
  final String title;
  final TextEditingController controller;
  final bool number, required, obscure;
  final int lines;
  final String? Function(String?)? validator;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
          controller: controller,
          obscureText: obscure,
          maxLines: lines,
          keyboardType: number
              ? const TextInputType.numberWithOptions(decimal: true)
              : TextInputType.text,
          decoration: InputDecoration(labelText: title),
          validator: validator ??
              (v) => required && (v == null || v.trim().isEmpty)
                  ? 'Заполните поле'
                  : null));
}
