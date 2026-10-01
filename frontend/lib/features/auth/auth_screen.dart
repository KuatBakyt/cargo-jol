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
  final email = TextEditingController(), password = TextEditingController(), name = TextEditingController(), phone = TextEditingController();
  bool register = false, busy = false;
  String role = 'shipper';
  String? error;
  @override
  void dispose() { for (final c in [email, password, name, phone]) { c.dispose(); } super.dispose(); }
  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() { busy = true; error = null; });
    try {
      final session = context.read<Session>();
      if (register) {
        await session.register({'email': email.text.trim(), 'password': password.text, 'first_name': name.text.trim(), 'last_name': '', 'phone': phone.text.trim(), 'role': role});
      } else { await session.login(email.text, password.text); }
    } catch (e) {
      if (mounted) { setState(() => error = errorText(e)); }
    } finally { if (mounted) { setState(() => busy = false); } }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 460), child: Form(key: form, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    const Icon(Icons.local_shipping_rounded, color: green, size: 54), const SizedBox(height: 12),
    const Text('JOL CARGO', textAlign: TextAlign.center, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: 2)),
    const SizedBox(height: 8), const Text('Грузы и перевозчики. На одной дороге.', textAlign: TextAlign.center), const SizedBox(height: 36),
    Text(register ? 'Создать аккаунт' : 'С возвращением', style: Theme.of(context).textTheme.headlineSmall), const SizedBox(height: 8),
    Text(register ? 'Выберите, как будете пользоваться JOL Cargo.' : 'Войдите, чтобы продолжить работу.'), const SizedBox(height: 24),
    if (register) ...[
      SegmentedButton<String>(segments: const [ButtonSegment(value: 'shipper', label: Text('Отправляю груз'), icon: Icon(Icons.inventory_2_outlined)), ButtonSegment(value: 'carrier', label: Text('Перевожу'), icon: Icon(Icons.local_shipping_outlined))], selected: {role}, onSelectionChanged: busy ? null : (v) => setState(() => role = v.first)),
      const SizedBox(height: 20), FormFieldInput('Имя', name),
      FormFieldInput('Телефон, например +77001234567', phone, validator: (v) => RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(v ?? '') ? null : 'Введите номер в международном формате'),
    ],
    FormFieldInput('Email', email, validator: (v) => (v ?? '').contains('@') ? null : 'Введите email'),
    FormFieldInput('Пароль', password, obscure: true, validator: (v) => (v ?? '').length >= 8 ? null : 'Минимум 8 символов'),
    if (error != null) Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(error!, style: TextStyle(color: Colors.red.shade800))),
    FilledButton(onPressed: busy ? null : submit, child: Text(busy ? 'Подождите…' : register ? 'Зарегистрироваться' : 'Войти')),
    const SizedBox(height: 12), TextButton(onPressed: busy ? null : () => setState(() { register = !register; error = null; }), child: Text(register ? 'Уже есть аккаунт? Войти' : 'Нет аккаунта? Регистрация')),
  ])))))));
}
