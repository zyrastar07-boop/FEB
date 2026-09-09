import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/movie.dart';
import '../services/watch_party_service.dart';
import '../services/font_service.dart';

import '../design/tokens.dart';

const _gold = AppDesignTokens.gold;

/// Create / join / share a social watch party.
class WatchPartySheet extends StatefulWidget {
  final Movie? movie;
  final String mediaType;
  final int? season;
  final int? episode;

  const WatchPartySheet({
    super.key,
    this.movie,
    this.mediaType = 'movie',
    this.season,
    this.episode,
  });

  static Future<WatchParty?> show(
    BuildContext context, {
    Movie? movie,
    String mediaType = 'movie',
    int? season,
    int? episode,
  }) {
    return showModalBottomSheet<WatchParty>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WatchPartySheet(
        movie: movie,
        mediaType: mediaType,
        season: season,
        episode: episode,
      ),
    );
  }

  @override
  State<WatchPartySheet> createState() => _WatchPartySheetState();
}

class _WatchPartySheetState extends State<WatchPartySheet> {
  final _joinCtrl = TextEditingController();
  bool _busy = false;
  WatchParty? _created;

  @override
  void initState() {
    super.initState();
    WatchPartyService.instance.ensureLoaded();
  }

  @override
  void dispose() {
    _joinCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (widget.movie == null) return;
    setState(() => _busy = true);
    final party = await WatchPartyService.instance.createParty(
      movie: widget.movie!,
      mediaType: widget.mediaType,
      season: widget.season,
      episode: widget.episode,
    );
    if (!mounted) return;
    setState(() {
      _created = party;
      _busy = false;
    });
    await Clipboard.setData(ClipboardData(text: party.inviteLine));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Invite copied — share the code with friends'),
        backgroundColor: Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _join() async {
    final code = _joinCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    final party = await WatchPartyService.instance.joinByCode(code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (party == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Party not found on this device. Ask the host to share the invite again.',
          ),
          backgroundColor: Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.pop(context, party);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF141414),
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Watch Party',
              style: FontService.instance.display(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Watch together with friends. Create a code or join one.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (widget.movie != null) ...[
              if (_created != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _gold.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: [
                      const Text('Your party code',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(
                        _created!.code,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _created!.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Clipboard.setData(
                                    ClipboardData(text: _created!.inviteLine));
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _gold,
                                side: const BorderSide(color: _gold),
                              ),
                              child: const Text('Copy invite'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.pop(context, _created),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _gold,
                                foregroundColor: Colors.black,
                              ),
                              child: const Text('Start watching'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _create,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.group_add_rounded),
                    label: Text(
                      'Create party for "${widget.movie!.title}"',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _gold,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),
            ],
            const Text('Join a party',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14)),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _joinCtrl,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(
                        color: Colors.white,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700),
                    decoration: InputDecoration(
                      hintText: 'Enter code',
                      hintStyle: const TextStyle(
                          color: Colors.white38, letterSpacing: 0),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _busy ? null : _join,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white12,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Join'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}