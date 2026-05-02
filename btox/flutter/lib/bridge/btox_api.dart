// btox/flutter/lib/bridge/btox_api.dart
//
// flutter_rust_bridge tarafından üretilecek köprünün yerine geçici stub.
// Gerçek dosya `flutter_rust_bridge_codegen generate ...` komutuyla üretilir
// ve bu stub'ın yerini alır.

import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Rust dynamic library'sini yükler. Gerçek köprü kod üretildikten sonra
/// burada `BtoxApi.init(...)` çağrılır.
Future<void> initBridge() async {
  // TODO: flutter_rust_bridge_codegen üretildikten sonra:
  //   final dylib = _openDylib();
  //   api = BtoxApiImpl(dylib);
  api = _StubApi();
}

Future<String> bootstrapDataDir() async {
  final dir = await getApplicationDocumentsDirectory();
  final btoxDir = Directory('${dir.path}/btox');
  if (!await btoxDir.exists()) {
    await btoxDir.create(recursive: true);
  }
  return btoxDir.path;
}

// ---------------------------------------------------------------------------
// API yüzeyi — Rust tarafındaki public fonksiyonlarla bire bir aynıdır.
// Üretilen dosya bu sınıfı `freezed` benzeri otomatik kodlarla değiştirir.
// ---------------------------------------------------------------------------

abstract class BtoxApi {
  void initLogger();

  Future<String> start({required String dataDir, required String profileName});

  Stream<BtoxEvent> eventStream();

  Future<String> selfToxId();
  Future<void> setSelfName({required String name});

  Future<int> addFriend({required String toxId, required String message});
  Future<int> acceptFriendRequest({required String toxId});
  Future<List<Friend>> listFriends();

  Future<void> sendMessage({required int friendId, required String text});

  Future<void> pttStart({required int friendId});
  Future<void> pttPushFrame({required int friendId, required List<int> pcm});
  Future<void> pttStop({required int friendId});

  Future<int> sendFile({required int friendId, required String path});
  Future<void> cancelFile({required int friendId, required int fileId});
  Future<void> pauseFile({required int friendId, required int fileId});
  Future<void> resumeFile({required int friendId, required int fileId});
}

late BtoxApi api;

// ---------------------------------------------------------------------------
// DTO'lar
// ---------------------------------------------------------------------------

class Friend {
  final int id;
  final String toxId;
  final String name;
  final String statusMessage;
  final bool online;

  const Friend({
    required this.id,
    required this.toxId,
    required this.name,
    required this.statusMessage,
    required this.online,
  });
}

class ChatMessage {
  final int friendId;
  final String text;
  final bool outgoing;
  final int timestampMs;

  const ChatMessage({
    required this.friendId,
    required this.text,
    required this.outgoing,
    required this.timestampMs,
  });
}

sealed class BtoxEvent {
  const BtoxEvent();
}

class EvConnectionChanged extends BtoxEvent {
  final bool online;
  const EvConnectionChanged(this.online);
}

class EvFriendRequest extends BtoxEvent {
  final String toxId;
  final String message;
  const EvFriendRequest(this.toxId, this.message);
}

class EvFriendUpdated extends BtoxEvent {
  final Friend friend;
  const EvFriendUpdated(this.friend);
}

class EvMessage extends BtoxEvent {
  final ChatMessage message;
  const EvMessage(this.message);
}

class EvFileProgress extends BtoxEvent {
  final int friendId;
  final int fileId;
  final int transferred;
  final int total;
  const EvFileProgress({
    required this.friendId,
    required this.fileId,
    required this.transferred,
    required this.total,
  });
}

class EvVoiceFrame extends BtoxEvent {
  final int friendId;
  final List<int> pcm;
  const EvVoiceFrame({required this.friendId, required this.pcm});
}

// ---------------------------------------------------------------------------
// STUB — Rust henüz bağlanmadığında UI'ın yine de çalışmasını sağlar.
// ---------------------------------------------------------------------------

class _StubApi implements BtoxApi {
  final _events = StreamController<BtoxEvent>.broadcast();
  final List<Friend> _friends = [];
  int _nextId = 1;

  @override
  void initLogger() {}

  @override
  Future<String> start({required String dataDir, required String profileName}) async {
    Future.delayed(const Duration(milliseconds: 400),
        () => _events.add(const EvConnectionChanged(true)));
    return '0' * 76;
  }

  @override
  Stream<BtoxEvent> eventStream() => _events.stream;

  @override
  Future<String> selfToxId() async => '0' * 76;

  @override
  Future<void> setSelfName({required String name}) async {}

  @override
  Future<int> addFriend({required String toxId, required String message}) async {
    final id = _nextId++;
    final f = Friend(
      id: id,
      toxId: toxId,
      name: 'Friend $id',
      statusMessage: 'eklendi: $message',
      online: false,
    );
    _friends.add(f);
    _events.add(EvFriendUpdated(f));
    return id;
  }

  @override
  Future<int> acceptFriendRequest({required String toxId}) async =>
      addFriend(toxId: toxId, message: '');

  @override
  Future<List<Friend>> listFriends() async => List.unmodifiable(_friends);

  @override
  Future<void> sendMessage({required int friendId, required String text}) async {
    _events.add(EvMessage(ChatMessage(
      friendId: friendId,
      text: text,
      outgoing: true,
      timestampMs: DateTime.now().millisecondsSinceEpoch,
    )));
  }

  @override Future<void> pttStart({required int friendId}) async {}
  @override Future<void> pttPushFrame({required int friendId, required List<int> pcm}) async {}
  @override Future<void> pttStop({required int friendId}) async {}

  int _nextFileId = 1;
  @override
  Future<int> sendFile({required int friendId, required String path}) async {
    final fileId = _nextFileId++;
    // Sahte ilerleme yay
    Future(() async {
      const total = 10 * 1024 * 1024 * 1024; // 10 GB
      var sent = 0;
      while (sent < total) {
        sent = (sent + 64 * 1024 * 1024).clamp(0, total);
        _events.add(EvFileProgress(
          friendId: friendId, fileId: fileId, transferred: sent, total: total,
        ));
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
    return fileId;
  }

  @override Future<void> cancelFile({required int friendId, required int fileId}) async {}
  @override Future<void> pauseFile({required int friendId, required int fileId}) async {}
  @override Future<void> resumeFile({required int friendId, required int fileId}) async {}
}

