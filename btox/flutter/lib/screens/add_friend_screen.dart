// btox/flutter/lib/screens/add_friend_screen.dart

import 'package:flutter/material.dart';

import '../bridge/btox_api.dart';

class AddFriendScreen extends StatefulWidget {
  const AddFriendScreen({super.key});

  @override
  State<AddFriendScreen> createState() => _AddFriendScreenState();
}

class _AddFriendScreenState extends State<AddFriendScreen> {
  final _idCtrl = TextEditingController();
  final _msgCtrl = TextEditingController(text: 'BTOX üzerinden arkadaş olalım?');
  bool _busy = false;
  String? _error;

  bool get _valid {
    final s = _idCtrl.text.trim().toUpperCase();
    return s.length == 76 && RegExp(r'^[0-9A-F]+$').hasMatch(s);
  }

  Future<void> _submit() async {
    if (!_valid) {
      setState(() => _error = 'Tox ID 76 hex karakter olmalı.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await api.addFriend(
        toxId: _idCtrl.text.trim().toUpperCase(),
        message: _msgCtrl.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Arkadaş Ekle')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _idCtrl,
              maxLength: 76,
              decoration: InputDecoration(
                labelText: 'Tox ID (76 hex)',
                border: const OutlineInputBorder(),
                helperText: 'qTox: Profil → Tox ID kısmından kopyalat.',
                errorText: _error,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'QR kodu tara',
                  onPressed: () {
                    // TODO: mobile_scanner ile QR okuyucu sayfa aç.
                  },
                ),
              ),
              style: const TextStyle(fontFamily: 'monospace'),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _msgCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'İstek mesajı',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(_busy ? 'Gönderiliyor…' : 'İstek Gönder'),
              onPressed: _busy ? null : _submit,
            ),
          ],
        ),
      ),
    );
  }
}

