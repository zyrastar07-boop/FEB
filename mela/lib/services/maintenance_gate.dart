import 'package:flutter/material.dart';
import 'remote_app_config.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);

/// Full-screen, non-bypassable gate when remote kill-switch is off.
class MaintenanceGate extends StatelessWidget {
  final Widget child;

  const MaintenanceGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RemoteAppConfig.instance,
      builder: (context, _) {
        final cfg = RemoteAppConfig.instance;
        if (!cfg.isLoaded || cfg.isAppActive) {
          return child;
        }
        return const _MaintenanceScreen();
      },
    );
  }
}

class _MaintenanceScreen extends StatelessWidget {
  const _MaintenanceScreen();

  @override
  Widget build(BuildContext context) {
    final msg = RemoteAppConfig.instance.maintenanceMessage;
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: _gold.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.cloud_off_rounded,
                      color: _gold, size: 36),
                ),
                const SizedBox(height: 22),
                const Text(
                  'Service Unavailable',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  msg,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 14.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Please check back later.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35),
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}