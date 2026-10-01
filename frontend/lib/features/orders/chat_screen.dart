import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/session.dart';
import '../../core/api_client.dart';
import '../../shared/ui.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.id});
  final int id;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final text = TextEditingController();
  Timer? timer;
  List<Map<String, dynamic>>? messages;
  String? error;
  bool busy = false, fetching = false;
  int page = 1;
  bool hasNext = false;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(const Duration(seconds: 8), (_) => load());
  }

  @override
  void dispose() {
    timer?.cancel();
    text.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (fetching) return;
    fetching = true;
    try {
      final api = context.read<Session>().api;
      final response = await api
          .get('/conversations/${widget.id}/messages', query: {'page': page});
      await api.post('/conversations/${widget.id}/read');
      if (mounted) {
        setState(() {
          messages = (response['results'] as List).cast<Map<String, dynamic>>();
          hasNext = response['next'] != null;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = errorText(e));
    } finally {
      fetching = false;
    }
  }

  Future<void> send() async {
    if (text.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      await context.read<Session>().api.post(
          '/conversations/${widget.id}/messages',
          {'type': 'text', 'text': text.text.trim()});
      text.clear();
      await load();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Чат перевозки'), actions: [
        IconButton(onPressed: load, icon: const Icon(Icons.refresh))
      ]),
      body: PageBody(
          child: Column(children: [
        if (error != null)
          MaterialBanner(content: Text(error!), actions: [
            TextButton(onPressed: load, child: const Text('Повторить'))
          ]),
        Expanded(
            child: messages == null
                ? const Center(child: CircularProgressIndicator())
                : messages!.isEmpty
                    ? const EmptyState(
                        'Начните разговор с участником перевозки.',
                        icon: Icons.chat_bubble_outline)
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: messages!.map((m) {
                          final own =
                              m['sender'] == context.read<Session>().userId;
                          return Align(
                              alignment: own
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                  constraints:
                                      const BoxConstraints(maxWidth: 480),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                      color: own ? green : Colors.white,
                                      borderRadius: BorderRadius.circular(16)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                            m['type'] == 'text'
                                                ? m['text'] as String
                                                : m['type'] == 'location'
                                                    ? 'Координаты: ${m['latitude']}, ${m['longitude']}'
                                                    : 'Вложение (${m['type']}). Открытие файлов будет добавлено позже.',
                                            style: TextStyle(
                                                color:
                                                    own ? Colors.white : ink)),
                                        const SizedBox(height: 6),
                                        Text(
                                            '${(m['created_at'] as String).substring(11, 16)}${own && m['read_at'] != null ? ' • Прочитано' : ''}',
                                            style: TextStyle(
                                                fontSize: 11,
                                                color: own
                                                    ? Colors.white70
                                                    : Colors.grey))
                                      ])));
                        }).toList())),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              onPressed: page <= 1
                  ? null
                  : () {
                      setState(() => page--);
                      load();
                    },
              icon: const Icon(Icons.chevron_left)),
          Text('Страница $page'),
          IconButton(
              onPressed: !hasNext
                  ? null
                  : () {
                      setState(() => page++);
                      load();
                    },
              icon: const Icon(Icons.chevron_right))
        ]),
        SafeArea(
            top: false,
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                      child: TextField(
                          controller: text,
                          minLines: 1,
                          maxLines: 4,
                          decoration:
                              const InputDecoration(hintText: 'Сообщение'),
                          onSubmitted: (_) => busy ? null : send())),
                  const SizedBox(width: 12),
                  IconButton.filled(
                      onPressed: busy ? null : send,
                      tooltip: 'Отправить',
                      icon: const Icon(Icons.send))
                ]))),
      ])));
}
