// btox/flutter/lib/screens/chat_screen.dart

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../bridge/btox_api.dart';
import '../widgets/push_to_talk_button.dart';

class ChatScreen extends StatefulWidget {
  final Friend friend;
  const ChatScreen({super.key, required this.friend});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final List<ChatMessage> _messages = [];
  late StreamSubscription<BtoxEvent> _sub;

  /// friend_id -> (transferred, total)
  final Map<int, (int, int)> _transfers = {};

  @override
  void initState() {
    super.initState();
    _sub = api.eventStream().listen((ev) {
      if (ev is EvMessage && ev.message.friendId == widget.friend.id) {
        setState(() => _messages.add(ev.message));
        _scrollToBottom();
      } else if (ev is EvFileProgress && ev.friendId == widget.friend.id) {
        setState(() => _transfers[ev.fileId] = (ev.transferred, ev.total));
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await api.sendMessage(friendId: widget.friend.id, text: text);
  }

  Future<void> _attachFile() async {
    final picked = await FilePicker.platform.pickFiles();
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) return;
    final size = await File(path).length();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Gönderiliyor: ${(size / 1e9).toStringAsFixed(2)} GB')),
    );
    await api.sendFile(friendId: widget.friend.id, path: path);
  }

  @override
  void dispose() {
    _sub.cancel();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.friend.name.isEmpty
            ? 'Arkadaş ${widget.friend.id}'
            : widget.friend.name),
        subtitle: null,
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(8),
              itemCount: _messages.length,
              itemBuilder: (_, i) => _MessageBubble(_messages[i]),
            ),
          ),
          if (_transfers.isNotEmpty) _TransferBar(transfers: _transfers),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: 'Dosya gönder',
                    onPressed: _attachFile,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: 'Mesaj yaz…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Mesaj boşsa PTT, doluysa Gönder
                  ValueListenableBuilder(
                    valueListenable: _input,
                    builder: (_, value, __) {
                      if (value.text.trim().isEmpty) {
                        return PushToTalkButton(friendId: widget.friend.id);
                      }
                      return IconButton.filled(
                        icon: const Icon(Icons.send),
                        onPressed: _send,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

extension on AppBar {}

class _MessageBubble extends StatelessWidget {
  final ChatMessage m;
  const _MessageBubble(this.m);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final align = m.outgoing ? Alignment.centerRight : Alignment.centerLeft;
    final bg = m.outgoing
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(m.text),
      ),
    );
  }
}

class _TransferBar extends StatelessWidget {
  final Map<int, (int, int)> transfers;
  const _TransferBar({required this.transfers});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          children: transfers.entries.map((e) {
            final (sent, total) = e.value;
            final pct = total == 0 ? 0.0 : sent / total;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Text('Dosya #${e.key}'),
                  const SizedBox(width: 8),
                  Expanded(child: LinearProgressIndicator(value: pct)),
                  const SizedBox(width: 8),
                  Text('${(sent / 1e9).toStringAsFixed(2)}/${(total / 1e9).toStringAsFixed(2)} GB'),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

