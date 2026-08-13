import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cached_network_image/cached_network_image.dart';
import '../models/movie.dart';
import '../services/tmdb_service.dart';
import '../services/font_service.dart';
import 'detail_screen.dart';

const _gold = Color(0xFFFFB800);
const _bg = Color(0xFF0A0A0A);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final TmdbService _tmdbService = TmdbService();
  final FocusNode _searchFocus = FocusNode();
  Timer? _debounce;

  List<Movie> _searchResults = [];
  List<Movie> _allResults = [];
  final Map<int, String> _mediaTypes = {};
  
  bool _isSearching = false;
  bool _hasError = false;
  bool _isLoadingKeywords = true;
  bool _isLoadingTrending = true;
  bool _blockedAdultQuery = false;
  
  List<String> _dynamicSearchKeywords = [];
  List<Movie> _trendingNow = [];
  List<Movie> _popularMovies = [];

  static const List<String> _adultBlockTerms = [
    'porn',
    'porno',
    'xxx',
    'xvideos',
    'xhamster',
    'onlyfans',
    'nsfw',
    'hentai',
    'rule34',
    'erotica',
    'erotic',
    'adult film',
    'adult movie',
    'sex tape',
    'nude scene',
    'hardcore',
  ];

  final List<String> _filterOptions = ['All', 'Movies', 'Series', 'Anime'];
  String _selectedFilter = 'All';

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  final List<Map<String, dynamic>> _categories = [
    {'label': 'Trending', 'icon': Icons.local_fire_department_rounded, 'type': 'trending'},
    {'label': 'Top Rated', 'icon': Icons.star_rounded, 'type': 'top_rated'},
    {'label': 'New', 'icon': Icons.new_releases_rounded, 'type': 'now_playing'},
    {'label': 'Action', 'icon': Icons.flash_on_rounded, 'type': 'action'},
    {'label': 'Sci-Fi', 'icon': Icons.rocket_launch_rounded, 'type': 'scifi'},
    {'label': 'Drama', 'icon': Icons.theater_comedy_rounded, 'type': 'drama'},
    {'label': 'Comedy', 'icon': Icons.sentiment_very_satisfied_rounded, 'type': 'comedy'},
    {'label': 'Horror', 'icon': Icons.nightlight_round, 'type': 'horror'},
    {'label': 'Anime', 'icon': Icons.animation_rounded, 'type': 'anime'},
    {'label': 'TV Series', 'icon': Icons.tv_rounded, 'type': 'tv'},
  ];

  // Speech recognition
  late stt.SpeechToText _speech;
  bool _isListening = false;
  String _lastWords = '';

  // Search history
  static const String _historyKey = 'search_history';
  List<String> _searchHistory = [];
  bool _showHistory = false;

  // Shimmer animation
  late AnimationController _shimmerCtrl;
  late Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _shimmerAnim = Tween<double>(begin: -1.0, end: 1.0).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );

    _speech = stt.SpeechToText();
    _loadSearchHistory();
    _loadDynamicKeywords();
    _loadTrendingAndPopular();

    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus && _searchController.text.isEmpty) {
        setState(() => _showHistory = true);
      } else {
        setState(() => _showHistory = false);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final history = prefs.getStringList(_historyKey) ?? [];
    setState(() {
      _searchHistory = history;
    });
  }

  Future<void> _saveSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyKey, _searchHistory);
  }

  void _addSearchTerm(String term) {
    if (term.trim().isEmpty) return;
    setState(() {
      _searchHistory.remove(term);
      _searchHistory.insert(0, term);
      if (_searchHistory.length > 15) _searchHistory.removeLast();
    });
    _saveSearchHistory();
  }

  void _removeSearchTerm(String term) {
    setState(() {
      _searchHistory.remove(term);
    });
    _saveSearchHistory();
  }

  void _clearSearchHistory() {
    setState(() {
      _searchHistory.clear();
    });
    _saveSearchHistory();
  }

  Future<void> _initSpeech() async {
    if (!_isListening) {
      final available = await _speech.initialize(
        onStatus: (status) => debugPrint('Speech status: $status'),
        onError: (error) {
          debugPrint('Speech error: $error');
          setState(() => _isListening = false);
        },
      );
      if (available) {
        _startListening();
      } else {
        _toast('Speech recognition not available');
      }
    } else {
      _stopListening();
    }
  }

  void _startListening() {
    setState(() => _isListening = true);
    _speech.listen(
      onResult: (result) {
        setState(() {
          _lastWords = result.recognizedWords;
          if (result.finalResult) {
            _stopListening();
            _searchController.text = _lastWords;
            _addSearchTerm(_lastWords);
            _performSearch(_lastWords);
          }
        });
      },
      listenFor: const Duration(seconds: 5),
      pauseFor: const Duration(seconds: 2),
      cancelOnError: true,
    );
  }

  void _stopListening() {
    _speech.stop();
    setState(() => _isListening = false);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF1A1A1A),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  bool _isAdultQuery(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return false;
    for (final term in _adultBlockTerms) {
      if (q == term || q.contains(term)) return true;
    }
    return false;
  }

  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      if (query.trim().isNotEmpty) {
        _performSearch(query);
      } else {
        setState(() {
          _searchResults.clear();
          _allResults.clear();
          _mediaTypes.clear();
          _isSearching = false;
          _hasError = false;
          _blockedAdultQuery = false;
          _showHistory = _searchFocus.hasFocus;
        });
      }
    });
  }

  Future<void> _performSearch(String query) async {
    if (_isAdultQuery(query)) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _hasError = false;
        _blockedAdultQuery = true;
        _searchResults = [];
        _allResults = [];
        _mediaTypes.clear();
        _showHistory = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _hasError = false;
      _blockedAdultQuery = false;
    });

    try {
      final results = await _tmdbService.searchMovies(query);
      if (!mounted) return;

      final types = <int, String>{};
      for (final m in results) {
        types[m.id] = _guessMediaType(m);
      }

      setState(() {
        _allResults = results;
        _mediaTypes
          ..clear()
          ..addAll(types);
        _searchResults = _applyFilter(results);
        _isSearching = false;
        _hasError = false;
        _showHistory = false;
        _blockedAdultQuery = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _hasError = true;
          _searchResults = [];
          _allResults = [];
          _mediaTypes.clear();
          _blockedAdultQuery = false;
        });
      }
    }
  }

  String _guessMediaType(Movie m) {
    final t = m.title.toLowerCase();
    if (t.contains('season') ||
        t.contains('episode') ||
        t.contains('(tv)') ||
        t.contains('series')) {
      return 'tv';
    }
    return 'movie';
  }

  List<Movie> _applyFilter(List<Movie> source) {
    if (_selectedFilter == 'All') return List.from(source);
    if (_selectedFilter == 'Movies') {
      return source.where((m) {
        final type = _mediaTypes[m.id] ?? _guessMediaType(m);
        return type == 'movie';
      }).toList();
    }
    if (_selectedFilter == 'Series') {
      return source.where((m) {
        final type = _mediaTypes[m.id] ?? _guessMediaType(m);
        return type == 'tv';
      }).toList();
    }
    return source.where((m) {
      final t = m.title.toLowerCase();
      final overview = (m.overview ?? '').toLowerCase();
      return t.contains('anime') ||
          t.contains('ghibli') ||
          overview.contains('anime') ||
          overview.contains('animation') ||
          (t.contains('studio') || t.contains('naruto') || t.contains('one piece'));
    }).toList();
  }

  void _onFilterChanged(String? value) {
    if (value == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedFilter = value;
      if (_allResults.isNotEmpty) {
        _searchResults = _applyFilter(_allResults);
      }
    });
  }

  void _onKeywordTapped(String keyword) {
    HapticFeedback.selectionClick();
    _searchController.text = keyword;
    _addSearchTerm(keyword);
    _searchFocus.requestFocus();
    _performSearch(keyword);
  }

  Future<void> _onCategoryTapped(Map<String, dynamic> cat) async {
    HapticFeedback.selectionClick();
    final label = cat['label'] as String;
    final type = cat['type'] as String? ?? label.toLowerCase();

    _searchController.text = label;
    _addSearchTerm(label);
    setState(() {
      _isSearching = true;
      _hasError = false;
    });

    try {
      List<Movie> results;
      switch (type) {
        case 'trending':
          results = await _tmdbService.getTrendingMovies();
          break;
        case 'top_rated':
          results = await _tmdbService.getTopRatedMovies();
          break;
        case 'now_playing':
          results = await _tmdbService.getNowPlayingMovies();
          break;
        case 'action':
          results = await _tmdbService.getActionMovies();
          break;
        case 'scifi':
          results = await _tmdbService.getSciFiMovies();
          break;
        case 'drama':
          results = await _tmdbService.getDramaMovies();
          break;
        case 'comedy':
          results = await _tmdbService.getComedyMovies();
          break;
        case 'horror':
          results = await _tmdbService.getHorrorMovies();
          break;
        case 'anime':
          results = await _tmdbService.getAnimeTvShows();
          for (final m in results) {
            _mediaTypes[m.id] = 'tv';
          }
          break;
        case 'tv':
          results = await _tmdbService.getTrendingTvShows();
          for (final m in results) {
            _mediaTypes[m.id] = 'tv';
          }
          break;
        default:
          results = await _tmdbService.searchMovies(label);
      }

      if (!mounted) return;
      setState(() {
        _allResults = results;
        for (final m in results) {
          _mediaTypes.putIfAbsent(m.id, () => _guessMediaType(m));
        }
        _searchResults = _applyFilter(results);
        _isSearching = false;
        _hasError = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _hasError = true;
          _searchResults = [];
          _allResults = [];
        });
      }
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchResults.clear();
      _allResults.clear();
      _mediaTypes.clear();
      _isSearching = false;
      _hasError = false;
      _blockedAdultQuery = false;
      _showHistory = _searchFocus.hasFocus;
    });
  }

  void _openDetail(Movie movie) {
    HapticFeedback.lightImpact();
    final isTv = (_mediaTypes[movie.id] ?? _guessMediaType(movie)) == 'tv';
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 340),
        pageBuilder: (_, _, _) => DetailScreen(movie: movie, isTv: isTv),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.03, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          );
        },
      ),
    );
  }

  Future<void> _loadDynamicKeywords() async {
    setState(() => _isLoadingKeywords = true);
    try {
      final trending = await _tmdbService.getTrendingMovies();
      final titles = trending
          .map((m) => m.title)
          .where((t) => t.trim().isNotEmpty)
          .toList();
      titles.shuffle(Random());
      if (mounted) {
        setState(() {
          _dynamicSearchKeywords = titles.take(10).toList();
          _isLoadingKeywords = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _dynamicSearchKeywords = [
            'Blade Runner',
            'Inception',
            'Interstellar',
            'Dune',
            'The Matrix',
            'Arrival',
            'Ex Machina',
            'Ghost in the Shell',
          ];
          _isLoadingKeywords = false;
        });
      }
    }
  }

  Future<void> _loadTrendingAndPopular() async {
    setState(() => _isLoadingTrending = true);
    try {
      final results = await Future.wait([
        _tmdbService.getTrendingMovies(),
        _tmdbService.getTrendingTvShows(),
      ]);
      final movies = results[0];
      final shows = results[1];
      if (mounted) {
        setState(() {
          _trendingNow = movies.take(12).toList();
          _popularMovies = [
            ...movies.skip(4).take(6),
            ...shows.take(6),
          ];
          _isLoadingTrending = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingTrending = false);
    }
  }

  Widget _buildSkeletonGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.64,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
      ),
      itemCount: 8,
      itemBuilder: (context, index) {
        return _buildSkeletonItem();
      },
    );
  }

  Widget _buildSkeletonItem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _ShimmerPlaceholder(
            shimmerAnim: _shimmerAnim,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        _ShimmerPlaceholder(
          shimmerAnim: _shimmerAnim,
          child: Container(
            height: 14,
            width: 120,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 4),
        _ShimmerPlaceholder(
          shimmerAnim: _shimmerAnim,
          child: Container(
            height: 12,
            width: 80,
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: _bg,
      resizeToAvoidBottomInset: false, // <-- Fix applied here
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Search',
                      style: FontService.instance.display(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    _buildFilterPill(),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded,
                          color: Colors.white.withValues(alpha: 0.4), size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocus,
                          onChanged: _onSearchChanged,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15),
                          cursorColor: _gold,
                          decoration: InputDecoration(
                            hintText: 'Movies, series, anime…',
                            hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 14.5),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if (_searchController.text.isEmpty)
                        GestureDetector(
                          onTap: _initSpeech,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isListening
                                  ? _gold.withValues(alpha: 0.2)
                                  : Colors.transparent,
                            ),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Icon(
                                  _isListening
                                      ? Icons.mic_rounded
                                      : Icons.mic_none_rounded,
                                  color: _isListening
                                      ? _gold
                                      : Colors.white.withValues(alpha: 0.5),
                                  size: 20,
                                ),
                                if (_isListening)
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: _gold.withValues(alpha: 0.6),
                                        width: 2,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: _clearSearch,
                          child: Icon(Icons.close_rounded,
                              color: Colors.white.withValues(alpha: 0.5),
                              size: 18),
                        ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isSearching
                    ? _buildSkeletonGrid()
                    : _hasError
                        ? _buildServerErrorState()
                        : _blockedAdultQuery
                            ? _buildAdultBlockedState()
                            : hasQuery && _searchResults.isNotEmpty
                                ? _buildResultsGrid()
                                : hasQuery && _searchResults.isEmpty
                                    ? _buildEmptyResults()
                                    : _buildDiscovery(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill() {
    return Container(
      height: 32,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedFilter,
          dropdownColor: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white70, size: 16),
          style: FontService.instance.label(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
          items: _filterOptions
              .map((v) => DropdownMenuItem(value: v, child: Text(v)))
              .toList(),
          onChanged: _onFilterChanged,
        ),
      ),
    );
  }

  Widget _buildServerErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wifi_off_rounded,
                color: Colors.white.withValues(alpha: 0.3), size: 52),
            const SizedBox(height: 14),
            Text(
              'Could not reach server',
              textAlign: TextAlign.center,
              style: FontService.instance.display(
                color: Colors.white70,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Check your connection and try again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                final text = _searchController.text.trim();
                if (text.isNotEmpty) {
                  _performSearch(text);
                } else {
                  _loadDynamicKeywords();
                  _loadTrendingAndPopular();
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _gold.withValues(alpha: 0.45)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.refresh_rounded, color: _gold, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Try again',
                      style: TextStyle(
                        color: _gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscovery() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showHistory && _searchHistory.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent searches',
                    style: FontService.instance.label(
                        color: Colors.white54, fontSize: 12, letterSpacing: 0.6)),
                GestureDetector(
                  onTap: _clearSearchHistory,
                  child: Text('Clear all',
                      style: TextStyle(
                          color: Colors.redAccent.withValues(alpha: 0.8),
                          fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _searchHistory.map((term) {
                return GestureDetector(
                  onTap: () => _onKeywordTapped(term),
                  child: Chip(
                    label: Text(term,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                    backgroundColor: Colors.white.withValues(alpha: 0.07),
                    deleteIcon: const Icon(Icons.close_rounded,
                        color: Colors.white38, size: 16),
                    onDeleted: () => _removeSearchTerm(term),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.09))),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
          ],

          Text('Browse by category',
              style: FontService.instance.label(
                  color: Colors.white54, fontSize: 12, letterSpacing: 0.6)),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: Duration(milliseconds: 280 + index * 40),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                          offset: Offset(12 * (1 - value), 0), child: child),
                    );
                  },
                  child: GestureDetector(
                    onTap: () => _onCategoryTapped(cat),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          Icon(cat['icon'] as IconData,
                              color: _gold, size: 15),
                          const SizedBox(width: 6),
                          Text(cat['label'] as String,
                              style: FontService.instance.label(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: const Color(0xFF161616).withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(18),
              border:
                  Border.all(color: Colors.white.withValues(alpha: 0.07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Everyone searching',
                    style: FontService.instance.label(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3)),
                const SizedBox(height: 12),
                if (_isLoadingKeywords)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: _gold, strokeWidth: 2))),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _dynamicSearchKeywords.asMap().entries.map((e) {
                      final i = e.key;
                      final keyword = e.value;
                      return TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0.0, end: 1.0),
                        duration: Duration(milliseconds: 250 + i * 35),
                        curve: Curves.easeOutCubic,
                        builder: (context, value, child) {
                          return Opacity(
                              opacity: value,
                              child: Transform.scale(
                                  scale: 0.85 + 0.15 * value, child: child));
                        },
                        child: GestureDetector(
                          onTap: () => _onKeywordTapped(keyword),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 13, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.09)),
                            ),
                            child: Text(keyword,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500)),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Trending now',
              style: FontService.instance.display(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (_isLoadingTrending)
            const SizedBox(
                height: 160,
                child: Center(
                    child: CircularProgressIndicator(
                        color: _gold, strokeWidth: 2)))
          else
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: _trendingNow.length,
                itemBuilder: (context, index) {
                  final movie = _trendingNow[index];
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 300 + index * 40),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) {
                      return Opacity(
                          opacity: value,
                          child: Transform.translate(
                              offset: Offset(18 * (1 - value), 0),
                              child: child));
                    },
                    child: GestureDetector(
                      onTap: () => _openDetail(movie),
                      child: Container(
                        width: 118,
                        margin: const EdgeInsets.only(right: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    CachedNetworkImage(
                                      imageUrl: movie.posterUrl,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.topCenter,
                                      memCacheWidth: 240,
                                      placeholder: (_, _) =>
                                          Container(color: const Color(0xFF1A1A1A)),
                                      errorWidget: (_, _, _) =>
                                          Container(color: Colors.grey[900]),
                                    ),
                                    Positioned(
                                      left: 5,
                                      bottom: 5,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.7),
                                            borderRadius:
                                                BorderRadius.circular(6)),
                                        child: Row(children: [
                                          const Icon(Icons.star_rounded,
                                              color: _gold, size: 10),
                                          const SizedBox(width: 2),
                                          Text(
                                              movie.voteAverage
                                                  .toStringAsFixed(1),
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 10)),
                                        ]),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(movie.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: FontService.instance.style(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 24),
          Text('Popular right now',
              style: FontService.instance.display(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              childAspectRatio: 0.62,
              crossAxisSpacing: 10,
              mainAxisSpacing: 12,
            ),
            itemCount: _popularMovies.length.clamp(0, 9),
            itemBuilder: (context, index) {
              final movie = _popularMovies[index];
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 280 + (index % 6) * 45),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                      opacity: value,
                      child: Transform.translate(
                          offset: Offset(0, 14 * (1 - value)), child: child));
                },
                child: GestureDetector(
                  onTap: () => _openDetail(movie),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: movie.posterUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            alignment: Alignment.topCenter,
                            memCacheWidth: 240,
                            placeholder: (_, _) =>
                                Container(color: const Color(0xFF1A1A1A)),
                            errorWidget: (_, _, _) =>
                                Container(color: Colors.grey[900]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(movie.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: FontService.instance.style(
                              color: Colors.white,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded,
              color: Colors.white.withValues(alpha: 0.25), size: 48),
          const SizedBox(height: 12),
          Text('No results found',
              style: FontService.instance.display(
                  color: Colors.white54,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('Try a different title or category',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35), fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildAdultBlockedState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.shield_rounded,
                color: Colors.white.withValues(alpha: 0.3), size: 52),
            const SizedBox(height: 14),
            Text(
              'This search isn’t allowed',
              textAlign: TextAlign.center,
              style: FontService.instance.display(
                color: Colors.white70,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'PhonoFilm is for everyone. Adult or explicit searches are blocked so the experience stays safe and suitable for all ages.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _clearSearch();
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: _gold.withValues(alpha: 0.45)),
                ),
                child: const Text(
                  'Search something else',
                  style: TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsGrid() {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.64,
        crossAxisSpacing: 12,
        mainAxisSpacing: 14,
      ),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final movie = _searchResults[index];
        final isTv =
            (_mediaTypes[movie.id] ?? _guessMediaType(movie)) == 'tv';
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 260 + (index % 8) * 35),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
                opacity: value,
                child: Transform.translate(
                    offset: Offset(0, 16 * (1 - value)), child: child));
          },
          child: GestureDetector(
            onTap: () => _openDetail(movie),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: movie.posterUrl,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          memCacheWidth: 300,
                          placeholder: (_, _) =>
                              Container(color: const Color(0xFF1A1A1A)),
                          errorWidget: (_, _, _) =>
                              Container(color: Colors.grey[900]),
                        ),
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color:
                                      Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(7)),
                              child: Row(children: [
                                const Icon(Icons.star_rounded,
                                    color: _gold, size: 11),
                                const SizedBox(width: 2),
                                Text(movie.voteAverage.toStringAsFixed(1),
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600)),
                              ]),
                            ),
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                  color:
                                      Colors.black.withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(7)),
                              child: Text(movie.releaseYear,
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 11)),
                            ),
                            if (isTv) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                    color: _gold.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(7)),
                                child: const Text('TV',
                                    style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(movie.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: FontService.instance.style(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShimmerPlaceholder extends StatelessWidget {
  final Animation<double> shimmerAnim;
  final Widget child;

  const _ShimmerPlaceholder({
    required this.shimmerAnim,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerAnim,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                const Color(0xFF1E1E1E),
                const Color(0xFF2A2A2A),
                const Color(0xFF1E1E1E),
              ],
              stops: [
                shimmerAnim.value * -0.5 + 0.0,
                shimmerAnim.value * 0.5 + 0.5,
                shimmerAnim.value * 0.5 + 1.0,
              ],
            ).createShader(bounds);
          },
          child: child,
        );
      },
    );
  }
}