// btox/flutter/lib/screens/home_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../bridge/btox_api.dart';
import 'add_friend_screen.dart';
import 'chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late StreamSubscription<BtoxEvent> _sub;
  List<Friend> _friends = [];
  bool _online = false;
  String _toxId = '';

  @override
  void initState() {
    super.initState();
    _refresh();
    _sub = api.eventStream().listen((ev) {
      if (ev is EvConnectionChanged) {
        setState(() => _online = ev.online);
      } else if (ev is EvFriendUpdated) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    final id = await api.selfToxId();
    final list = await api.listFriends();
    setState(() {
      _toxId = id;
      _friends = list;
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BTOX'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Center(
              child: Row(
                children: [
                  Icon(
                    Icons.circle,
                    size: 12,
                    color: _online ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 6),
                  Text(_online ? 'Çevrimiçi' : 'Bağlanıyor…'),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(12),
            child: ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Tox ID'),
              subtitle: SelectableText(
                _toxId,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                maxLines: 2,
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _friends.isEmpty
                ? const Center(child: Text('Henüz arkadaşın yok.\nSağ alttan birini ekle.', textAlign: TextAlign.center))
                : ListView.builder(
                    itemCount: _friends.length,
                    itemBuilder: (_, i) {
                      final f = _friends[i];
                      return ListTile(
                        leading: CircleAvatar(child: Text(f.name.isEmpty ? '?' : f.name[0])),
                        title: Text(f.name.isEmpty ? 'Arkadaş ${f.id}' : f.name),
                        subtitle: Text(f.statusMessage),
                        trailing: Icon(Icons.circle,
                            size: 10, color: f.online ? Colors.green : Colors.grey),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => ChatScreen(friend: f)),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.person_add),
        label: const Text('Arkadaş Ekle'),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddFriendScreen()),
          );
          _refresh();
        },
      ),
    );
  }
}

