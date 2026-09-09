import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../models/movie.dart';
import '../services/api_config.dart';
import '../services/font_service.dart';
import '../design/motion.dart';
import '../services/tmdb_details_service.dart';
import '../navigation/app_navigator.dart';

const _actorBg = Color(0xFF08090D);
const _actorSurface = Color(0xFF11151C);
const _actorSurface2 = Color(0xFF171C26);
const _actorGold = Color(0xFFF0BE62);
const _actorBlue = Color(0xFF6EA8FF);

/// Actor / person detail screen.
///
/// This screen intentionally uses the same Cloudflare TMDB proxy as the rest
/// of the app. The previous implementation tried to call methods that are not
/// exposed by the current TmdbDetailsService and also expected a different
/// response shape than getActorDetails() actually returns.
class ActorDetailScreen extends StatefulWidget {
  const ActorDetailScreen({
    super.key,
    required this.actorId,
  });

  final int actorId;

  @override
  State<ActorDetailScreen> createState() => _ActorDetailScreenState();
}

class _ActorDetailScreenState extends State<ActorDetailScreen> {
  final TmdbDetailsService _details = TmdbDetailsService();
  final http.Client _client = http.Client();

  bool _loading = true;
  String? _error;
  bool _bioExpanded = false;
  _CreditFilter _filter = _CreditFilter.all;

  String _name = '';
  String _biography = '';
  String? _profilePath;
  String? _knownForDepartment;
  String? _birthday;
  String? _placeOfBirth;
  List<Movie> _credits = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Uri _personUri() {
    final base = Uri.parse(ApiConfig.tmdb('/person/${widget.actorId}'));
    return base.replace(
      queryParameters: {
        ...base.queryParameters,
        'include_adult': 'false',
      },
    );
  }

  Future<Map<String, dynamic>?> _fetchPersonProfile() async {
    try {
      final response = await _client.get(_personUri());
      if (response.statusCode != 200) return null;
      final decoded = json.decode(response.body);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      if (map['adult'] == true) return null;
      return map;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // getActorDetails() already uses the app's proxy and gives us the
      // filtered filmography. We fetch the raw person profile only because
      // the existing service intentionally reduces the person payload to a
      // CastMember, while this screen also needs biography/birthday/place of birth.
      final results = await Future.wait<dynamic>([
        _details.getActorDetails(widget.actorId),
        _fetchPersonProfile(),
      ]);

      if (!mounted) return;

      final payload = results[0];
      final person = results[1] as Map<String, dynamic>?;

      if (payload is! Map) {
        setState(() {
          _loading = false;
          _error = 'Could not load this person.';
        });
        return;
      }

      final actor = payload['actor'];
      final moviesRaw = payload['movies'];

      final movies = <Movie>[];
      if (moviesRaw is List) {
        for (final item in moviesRaw) {
          if (item is Movie && item.id > 0) movies.add(item);
        }
      }

      // The service normally gives us a CastMember. The raw profile is the
      // authoritative source for person-specific metadata.
      final resolvedName = _stringValue(person?['name']) ??
          _stringValue(actor?.name) ??
          '';

      final profile = _stringValue(person?['profile_path']) ??
          _stringValue(actor?.profilePath);

      setState(() {
        _name = resolvedName.isNotEmpty ? resolvedName : 'Unknown person';
        _biography = _stringValue(person?['biography']) ?? '';
        _profilePath = profile;
        _knownForDepartment = _stringValue(person?['known_for_department']);
        _birthday = _stringValue(person?['birthday']);
        _placeOfBirth = _stringValue(person?['place_of_birth']);
        _credits = movies;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load this person. Please check your connection and retry.';
      });
    }
  }

  String? _stringValue(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    return text;
  }

  String get _profileUrl {
    final path = _profilePath;
    if (path == null || path.isEmpty || path == 'null') return '';
    if (path.startsWith('http')) return path;
    return 'https://image.tmdb.org/t/p/h632$path';
  }

  List<Movie> get _filteredCredits {
    switch (_filter) {
      case _CreditFilter.all:
        return _credits;
      case _CreditFilter.movie:
        return _credits.where((m) => m.mediaType != 'tv').toList();
      case _CreditFilter.tv:
        return _credits.where((m) => m.mediaType == 'tv').toList();
    }
  }

  String _yearFor(Movie movie) {
    final date = movie.releaseDate.trim();
    return date.length >= 4 ? date.substring(0, 4) : '';
  }

  String _typeLabel(Movie movie) => movie.mediaType == 'tv' ? 'Series' : 'Film';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: _actorBg,
      body: _loading
          ? const _ActorLoadingView()
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  color: _actorGold,
                  backgroundColor: _actorSurface,
                  onRefresh: _load,
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    slivers: [
                      _buildHeroAppBar(),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                        sliver: SliverList(
                          delegate: SliverChildListDelegate([
                            _buildIdentityCard(),
                            if (_biography.isNotEmpty) ...[
                              const SizedBox(height: 18),
                              _buildBiography(),
                            ],
                            const SizedBox(height: 24),
                            _buildFilmographyHeader(),
                          ]),
                        ),
                      ),
                      if (_filteredCredits.isNotEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 110),
                          sliver: SliverLayoutBuilder(
                            builder: (context, constraints) {
                              final width = constraints.crossAxisExtent;
                              final columns = width >= 1100
                                  ? 7
                                  : width >= 860
                                      ? 6
                                      : width >= 680
                                          ? 5
                                          : width >= 500
                                              ? 4
                                              : 3;
                              return SliverGrid(
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 16,
                                  mainAxisExtent: width >= 700 ? 294 : 270,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final movie = _filteredCredits[index];
                                    return _FilmographyCard(
                                      movie: movie,
                                      year: _yearFor(movie),
                                      typeLabel: _typeLabel(movie),
                                      onTap: () {
                                        HapticFeedback.selectionClick();
                                        AppNavigator.openDetail(
                                          context,
                                          movie,
                                          isTv: movie.mediaType == 'tv',
                                        );
                                      },
                                    );
                                  },
                                  childCount: _filteredCredits.length,
                                ),
                              );
                            },
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 6, 18, 110),
                          sliver: SliverToBoxAdapter(
                            child: _buildEmptyFilmography(theme),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeroAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 270,
      backgroundColor: _actorBg,
      elevation: 0,
      leading: Padding(
        padding: const EdgeInsets.only(left: 8, top: 4),
        child: _CircleIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      titleSpacing: 0,
      title: const SizedBox.shrink(),
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: _buildHeroArtwork(),
      ),
    );
  }

  Widget _buildHeroArtwork() {
    final mood = _moodColorForDepartment(_knownForDepartment);
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          fit: StackFit.expand,
          children: [
            // Mood background — soft radial gradient instead of network photo
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.4, -0.6),
                  radius: 1.4,
                  colors: [
                      mood,
                      mood.withValues(alpha: 0.55),
                      _actorBg,
                    ],
                    stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
            // Soft secondary blob for depth (Apple-style "materials")
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.8, 0.9),
                  radius: 1.1,
                  colors: [
                      Colors.white.withValues(alpha: 0.06),
                      Colors.transparent,
                    ],
                ),
              ),
            ),
            // Top-to-bottom fade so chrome and text stay readable
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.32),
                    Colors.black.withValues(alpha: 0.08),
                    _actorBg.withValues(alpha: 0.72),
                    _actorBg,
                  ],
                  stops: const [0, 0.30, 0.78, 1],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildHeroPortrait(),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_knownForDepartment != null &&
                              _knownForDepartment!.isNotEmpty)
                            _Pill(
                              icon: Icons.auto_awesome_rounded,
                              text: _knownForDepartment!,
                            ),
                          const SizedBox(height: 9),
                          Text(
                            _name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: FontService.instance.display(
                              color: Colors.white,
                              fontSize: 29,
                              fontWeight: FontWeight.w900,
                              height: 1.02,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${_credits.length} ${_credits.length == 1 ? 'title' : 'titles'}',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHeroPortrait() {
    return Container(
      width: 96,
      height: 132,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _actorGold.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _profileUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: _profileUrl,
              fit: BoxFit.cover,
              memCacheWidth: 220,
              errorWidget: (_, _, _) => _personPlaceholder(),
            )
          : _personPlaceholder(),
    );
  }

  Widget _personPlaceholder() {
    return Container(
      color: _actorSurface2,
      alignment: Alignment.center,
      child: const Icon(Icons.person_rounded, color: Colors.white24, size: 44),
    );
  }

  Widget _buildIdentityCard() {
    final details = <Widget>[];
    if (_birthday != null) {
      details.add(_MetadataItem(
        icon: Icons.cake_outlined,
        label: 'Born',
        value: _formatDisplayDate(_birthday!),
      ));
    }
    if (_placeOfBirth != null) {
      details.add(_MetadataItem(
        icon: Icons.place_outlined,
        label: 'Birthplace',
        value: _placeOfBirth!,
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: _actorSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: details.isEmpty
          ? Row(
              children: [
                const Icon(Icons.person_outline_rounded,
                    color: _actorGold, size: 20),
                const SizedBox(width: 10),
                Text(
                  _knownForDepartment ?? 'Actor / performer',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Wrap(
              spacing: 18,
              runSpacing: 14,
              children: details,
            ),
    );
  }

  Widget _buildBiography() {
    final clipped = !_bioExpanded && _biography.length > 340;
    final text = clipped ? '${_biography.substring(0, 340).trim()}…' : _biography;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_actorSurface2, _actorSurface],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _actorBlue.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _actorBlue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.notes_rounded,
                  color: _actorBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Biography',
                style: FontService.instance.display(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.58,
            ),
          ),
          if (_biography.length > 340) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => setState(() => _bioExpanded = !_bioExpanded),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
                child: Text(
                  _bioExpanded ? 'Show less' : 'Read more',
                  style: const TextStyle(
                    color: _actorGold,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilmographyHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filmography',
                style: FontService.instance.display(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${_filteredCredits.length} shown',
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: _actorSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Row(
            children: _CreditFilter.values.map((filter) {
              final selected = _filter == filter;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _filter = filter);
                },
                child: AnimatedContainer(
                  duration: AppMotion.scaled(context, AppMotion.micro),
                  curve: const Cubic(0.23, 1, 0.32, 1), // strong ease-out
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: selected ? _actorGold : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    filter.label,
                    style: TextStyle(
                      color: selected ? Colors.black : Colors.white60,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyFilmography(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _actorSurface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
      ),
      child: Column(
        children: [
          const Icon(Icons.movie_filter_outlined,
              color: Colors.white24, size: 40),
          const SizedBox(height: 10),
          const Text(
            'No titles in this filter',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Try another category or refresh the profile.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }

  String _formatDisplayDate(String iso) {
    try {
      final date = DateTime.parse(iso);
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return iso;
    }
  }

  /// Derives a blurred mood gradient color from the actor's department.
  /// Used as the hero backdrop so each profile gets a unique ambient hue
  /// without fetching a network photo.
  Color _moodColorForDepartment(String? department) {
    final d = (department ?? '').toLowerCase().trim();
    if (d.contains('direct')) return const Color(0xFFD4A24C);
    if (d.contains('writ')) return const Color(0xFF5E8FD6);
    if (d.contains('produc')) return const Color(0xFFD45E5E);
    if (d.contains('compos') || d.contains('music') || d.contains('sound')) {
      return const Color(0xFF7A5ED6);
    }
    if (d.contains('cinemat') || d.contains('camera')) {
      return const Color(0xFF4E9CC4);
    }
    if (d.contains('edit')) return const Color(0xFF6E9C7A);
    if (d.contains('art') || d.contains('design')) {
      return const Color(0xFFC77A4E);
    }
    if (d.contains('visual') || d.contains('effect')) {
      return const Color(0xFF4EC7B5);
    }
    if (d.contains('costum')) return const Color(0xFFC74E9C);
    if (d.contains('actor') || d.contains('actress') || d.isEmpty) {
      return const Color(0xFFB8860B);
    }
    return const Color(0xFF6B6B6B);
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _actorGold.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.person_off_outlined,
                color: _actorGold,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Couldn’t load this person',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _load,
              style: FilledButton.styleFrom(
                backgroundColor: _actorGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Retry',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

enum _CreditFilter { all, movie, tv }

extension on _CreditFilter {
  String get label {
    switch (this) {
      case _CreditFilter.all:
        return 'All';
      case _CreditFilter.movie:
        return 'Films';
      case _CreditFilter.tv:
        return 'Series';
    }
  }
}

class _FilmographyCard extends StatelessWidget {
  const _FilmographyCard({
    required this.movie,
    required this.year,
    required this.typeLabel,
    required this.onTap,
  });

  final Movie movie;
  final String year;
  final String typeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        splashColor: _actorGold.withValues(alpha: 0.12),
        highlightColor: _actorGold.withValues(alpha: 0.06),
        child: Container(
          decoration: BoxDecoration(
            color: _actorSurface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: movie.posterUrl,
                      fit: BoxFit.cover,
                      memCacheWidth: 360,
                      fadeInDuration: AppMotion.scaled(context, AppMotion.fast),
                      placeholder: (_, _) => const ColoredBox(color: _actorSurface2),
                      errorWidget: (_, _, _) => const ColoredBox(
                        color: _actorSurface2,
                        child: Icon(Icons.movie_outlined,
                            color: Colors.white24, size: 34),
                      ),
                    ),
                    Positioned(
                      top: 9,
                      left: 9,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.60),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.10)),
                        ),
                        child: Text(
                          typeLabel.toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        height: 78,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.82),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Row(
                        children: [
                          const Icon(Icons.star_rounded,
                              size: 13, color: _actorGold),
                          const SizedBox(width: 4),
                          Text(
                            movie.voteAverage > 0
                                ? movie.voteAverage.toStringAsFixed(1)
                                : '—',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (year.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              year,
                              style: const TextStyle(
                                color: Colors.white60,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
                child: Text(
                  movie.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetadataItem extends StatelessWidget {
  const _MetadataItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 320),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.055),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _actorGold, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.32),
                    fontSize: 8.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12.5,
                    height: 1.25,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _actorGold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _actorGold.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _actorGold, size: 12),
          const SizedBox(width: 5),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _actorGold,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        splashColor: Colors.white.withValues(alpha: 0.18),
        highlightColor: Colors.white.withValues(alpha: 0.08),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

class _ActorLoadingView extends StatelessWidget {
  const _ActorLoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 26,
        height: 26,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: _actorGold,
        ),
      ),
    );
  }
}
