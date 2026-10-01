import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../core/api_client.dart';
import '../../shared/ui.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      phone = TextEditingController();
  bool register = false, busy = false;
  String role = 'shipper';
  String? error;
  @override
  void dispose() {
    for (final c in [email, password, name, phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final session = context.read<Session>();
      if (register) {
        await session.register({
          'email': email.text.trim(),
          'password': password.text,
          'first_name': name.text.trim(),
          'last_name': '',
          'phone': phone.text.trim(),
          'role': role
        });
      } else {
        await session.login(email.text, password.text);
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = errorText(e));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      body: SafeArea(
          child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: Form(
                          key: form,
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Icon(Icons.local_shipping_rounded,
                                    color: brandBlue, size: 54),
                                const SizedBox(height: 12),
                                const Text('JOL Cargo',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w900,
                                        color: brandBlue)),
                                const SizedBox(height: 8),
                                const Text(
                                    'Находите грузы и перевозчиков\nпо всему Казахстану.',
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 36),
                                Text(
                                    register
                                        ? 'Создать аккаунт'
                                        : 'Перевозки без лишних звонков',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                const SizedBox(height: 8),
                                Text(register
                                    ? 'Выберите, как будете пользоваться JOL Cargo.'
                                    : 'Войдите, чтобы продолжить работу.'),
                                const SizedBox(height: 24),
                                if (register) ...[
                                  ...[
                                    (
                                      'carrier',
                                      'Перевожу',
                                      'Ищу грузы для своего транспорта',
                                      Icons.local_shipping_rounded
                                    ),
                                    (
                                      'shipper',
                                      'Отправляю груз',
                                      'Ищу транспорт для перевозки груза',
                                      Icons.inventory_2_rounded
                                    )
                                  ].map((item) => Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 12),
                                        child: Material(
                                          color: role == item.$1
                                              ? const Color(0xFFF0F6FF)
                                              : Colors.white,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              side: BorderSide(
                                                  color: role == item.$1
                                                      ? brandBlue
                                                      : const Color(
                                                          0xFFE1E8F2))),
                                          child: ListTile(
                                              contentPadding:
                                                  const EdgeInsets.all(12),
                                              leading: Icon(item.$4,
                                                  color: brandBlue, size: 32),
                                              title: Text(item.$2,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                              subtitle: Text(item.$3,
                                                  style: const TextStyle(
                                                      fontSize: 12)),
                                              trailing: Icon(
                                                  role == item.$1
                                                      ? Icons.check_circle
                                                      : Icons.chevron_right,
                                                  color: brandBlue),
                                              onTap: busy
                                                  ? null
                                                  : () => setState(
                                                      () => role = item.$1)),
                                        ),
                                      )),
                                  const SizedBox(height: 20),
                                  FormFieldInput('Имя', name),
                                  FormFieldInput(
                                      'Телефон, например +77001234567', phone,
                                      validator: (v) => RegExp(
                                                  r'^\+[1-9]\d{7,14}$')
                                              .hasMatch(v ?? '')
                                          ? null
                                          : 'Введите номер в международном формате'),
                                ],
                                FormFieldInput('Email', email,
                                    validator: (v) => (v ?? '').contains('@')
                                        ? null
                                        : 'Введите email'),
                                FormFieldInput('Пароль', password,
                                    obscure: true,
                                    validator: (v) => (v ?? '').length >= 8
                                        ? null
                                        : 'Минимум 8 символов'),
                                if (error != null)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Text(error!,
                                          style: TextStyle(
                                              color: Colors.red.shade800))),
                                FilledButton(
                                    onPressed: busy ? null : submit,
                                    child: Text(busy
                                        ? 'Подождите…'
                                        : register
                                            ? 'Зарегистрироваться'
                                            : 'Войти')),
                                const SizedBox(height: 12),
                                TextButton(
                                    onPressed: busy
                                        ? null
                                        : () => setState(() {
                                              register = !register;
                                              error = null;
                                            }),
                                    child: Text(register
                                        ? 'Уже есть аккаунт? Войти'
                                        : 'Нет аккаунта? Регистрация')),
                              ])))))));
}
