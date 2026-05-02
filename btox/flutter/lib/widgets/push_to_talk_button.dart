// btox/flutter/lib/widgets/push_to_talk_button.dart
//
// Bas-bırak ses butonu.
// Basıldığında 48 kHz mono PCM yakalamaya başlar; her 20 ms'lik çerçeve
// (960 örnek) Rust tarafına `pttPushFrame` ile gönderilir.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../bridge/btox_api.dart';

class PushToTalkButton extends StatefulWidget {
  final int friendId;
  const PushToTalkButton({super.key, required this.friendId});

  @override
  State<PushToTalkButton> createState() => _PushToTalkButtonState();
}

class _PushToTalkButtonState extends State<PushToTalkButton> {
  bool _recording = false;
  Timer? _frameTimer;

  Future<bool> _ensureMic() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> _start() async {
    if (_recording) return;
    if (!await _ensureMic()) return;
    HapticFeedback.mediumImpact();
    setState(() => _recording = true);
    await api.pttStart(friendId: widget.friendId);

    // TODO: gerçek mikrofon yakalama (record paketi ile PCM stream).
    // Şimdilik 20 ms periyotla boş kare gönderiyoruz ki pipeline test edilebilsin.
    _frameTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      api.pttPushFrame(
        friendId: widget.friendId,
        pcm: List<int>.filled(960, 0),
      );
    });
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _frameTimer?.cancel();
    _frameTimer = null;
    setState(() => _recording = false);
    HapticFeedback.lightImpact();
    await api.pttStop(friendId: widget.friendId);
  }

  @override
  void dispose() {
    _frameTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _recording
        ? Colors.redAccent
        : Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: _recording
              ? [BoxShadow(color: color.withOpacity(0.6), blurRadius: 16, spreadRadius: 4)]
              : null,
        ),
        child: const Icon(Icons.mic, color: Colors.white),
      ),
    );
  }
}

