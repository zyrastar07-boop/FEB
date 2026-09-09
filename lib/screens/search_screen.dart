//search screen.dart
import 'dart:async';
import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/movie.dart';
import '../services/font_service.dart';
import '../services/tmdb_service.dart';
import '../utils/adaptive.dart';
import '../design/tokens.dart';
import '../design/motion.dart';
import '../widgets/app_button.dart';
import '../widgets/app_chip.dart';
import '../widgets/addons_rails.dart';
import '../widgets/poster_card.dart';
import '../widgets/responsive_layout.dart';
import 'detail_screen.dart';

const _gold = AppDesignTokens.gold;
const _bg = AppDesignTokens.backgroundCanvas;
const _card = AppDesignTokens.surfaceElevated;

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final TmdbService _tmdbService = TmdbService();

  Timer? _debounce;
  Timer? _historySaveTimer;

  int _searchRequestId = 0;
  int _categoryRequestId = 0;
  int _contentRequestId = 0;

  String _lastExecutedQuery = '';

  bool _isMounted = false;
  bool _isActive = true;
  bool _isSearching = false;
  bool _isLoadingContent = true;
  bool _hasError = false;
  bool _blockedAdultQuery = false;
  bool _showHistory = false;
  bool _isListening = false;
  bool _isOpeningDetail = false;

  String _selectedFilter = 'All';

  List<Movie> _searchResults = <Movie>[];
  List<Movie> _allResults = <Movie>[];
  List<Movie> _trendingNow = <Movie>[];
  List<Movie> _popularMovies = <Movie>[];

  final Map<int, String> _mediaTypes = <int, String>{};
  final Map<String, List<Movie>> _searchCache = <String, List<Movie>>{};
  final Map<String, List<Movie>> _categoryCache = <String, List<Movie>>{};
  static const int _maxSearchCacheEntries = 40;
  static const int _maxResultsShown = 60;

  final ScrollController _resultsScrollController = ScrollController();

  List<String> _dynamicSearchKeywords = <String>[];
  List<String> _searchHistory = <String>[];
  List<String> _suggestions = <String>[];

  stt.SpeechToText? _speech;

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  late final AnimationController _shimmerCtrl;

  static const String _historyKey = 'search_history';

  static const List<String> _filterOptions = <String>[
    'All',
    'Movies',
    'Series',
    'Anime',
  ];

  static const List<String> _adultBlockTerms = <String>[
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

  final List<Map<String, dynamic>> _categories =
      <Map<String, dynamic>>[
    {
      'label': 'Trending',
      'icon': Icons.local_fire_department_rounded,
      'type': 'trending',
    },
    {
      'label': 'Top Rated',
      'icon': Icons.star_rounded,
      'type': 'top_rated',
    },
    {
      'label': 'New',
      'icon': Icons.new_releases_rounded,
      'type': 'now_playing',
    },
    {
      'label': 'Action',
      'icon': Icons.flash_on_rounded,
      'type': 'action',
    },
    {
      'label': 'Sci-Fi',
      'icon': Icons.rocket_launch_rounded,
      'type': 'scifi',
    },
    {
      'label': 'Drama',
      'icon': Icons.theater_comedy_rounded,
      'type': 'drama',
    },
    {
      'label': 'Comedy',
      'icon': Icons.sentiment_very_satisfied_rounded,
      'type': 'comedy',
    },
    {
      'label': 'Horror',
      'icon': Icons.nightlight_round,
      'type': 'horror',
    },
    {
      'label': 'Anime',
      'icon': Icons.animation_rounded,
      'type': 'anime',
    },
    {
      'label': 'TV Series',
      'icon': Icons.tv_rounded,
      'type': 'tv',
    },
  ];

  @override
  void initState() {
    super.initState();

    _isMounted = true;
    WidgetsBinding.instance.addObserver(this);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.micro,
    );

    _fadeAnim = CurvedAnimation(
      parent: _fadeCtrl,
      curve: Curves.easeOut,
    );

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    );

    _speech = stt.SpeechToText();

    _searchController.addListener(_onControllerChanged);
    _searchFocus.addListener(_onFocusChanged);

    _fadeCtrl.forward();
    _loadInitialContent();

    // Scale animation durations to the device's refresh rate once the
    // inherited widgets (MediaQuery) are available — initState() runs
    // before that, so the call must happen after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rescaleAnimations();
    });
  }

  void _rescaleAnimations() {
    if (!mounted) return;
    _fadeCtrl.duration = AppMotion.scaled(context, AppMotion.micro);
    _shimmerCtrl.duration = AppMotion.scaled(context, AppMotion.slow);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rescaleAnimations();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isActive = state == AppLifecycleState.resumed;

    if (_isActive) {
      if (!_isLoadingContent && _isSearching == false) {
        _shimmerCtrl.stop();
      }
    } else {
      _shimmerCtrl.stop();
      _stopListening();
    }
  }

  @override
  void dispose() {
    _isMounted = false;
    WidgetsBinding.instance.removeObserver(this);

    _debounce?.cancel();
    _historySaveTimer?.cancel();

    _searchRequestId++;
    _categoryRequestId++;
    _contentRequestId++;

    try {
      _speech?.stop();
      _speech?.cancel();
    } catch (_) {}

    _speech = null;

    _searchController.removeListener(_onControllerChanged);
    _searchFocus.removeListener(_onFocusChanged);

    _searchController.dispose();
    _searchFocus.dispose();
    _resultsScrollController.dispose();

    _fadeCtrl.dispose();
    _shimmerCtrl.dispose();

    super.dispose();
  }

  void _safeSetState(VoidCallback callback) {
    if (!_isMounted || !mounted) return;
    setState(callback);
  }

  void _onControllerChanged() {
    if (!_isMounted) return;

    final text = _searchController.text.trim();
    final shouldShowHistory = _searchFocus.hasFocus && text.isEmpty;

    // Suggestions update is throttled inside _updateSuggestions (equality check).
    _updateSuggestions(text);

    // Only flip history visibility — avoid extra setState on every keystroke.
    if (_showHistory != shouldShowHistory) {
      _safeSetState(() => _showHistory = shouldShowHistory);
    }
  }

  void _onFocusChanged() {
    if (!_isMounted) return;

    final text = _searchController.text.trim();
    final shouldShowHistory = _searchFocus.hasFocus && text.isEmpty;

    // Keyboard / focus: stop shimmer animation so it doesn't compete with
    // IME inset animations for raster budget.
    if (_searchFocus.hasFocus) {
      _shimmerCtrl.stop();
    }

    if (_showHistory != shouldShowHistory) {
      _safeSetState(() => _showHistory = shouldShowHistory);
    }
  }

  Future<void> _loadInitialContent() async {
    await Future.wait<void>(<Future<void>>[
      _loadSearchHistory(),
      _loadDynamicKeywords(),
      _loadTrendingAndPopular(),
    ]);

    if (!_isMounted) return;

    _safeSetState(() => _isLoadingContent = false);
  }

  Future<void> _loadSearchHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = prefs.getStringList(_historyKey) ?? <String>[];

      if (!_isMounted) return;

      _safeSetState(() {
        _searchHistory = history
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .take(20)
            .toList();
      });
    } catch (_) {}
  }

  void _scheduleHistorySave() {
    _historySaveTimer?.cancel();

    _historySaveTimer = Timer(
      const Duration(milliseconds: 500),
      () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList(_historyKey, _searchHistory);
        } catch (_) {}
      },
    );
  }

  void _addSearchTerm(String value) {
    final term = value.trim();
    if (term.isEmpty || !_isMounted) return;

    final normalized = term.toLowerCase();

    final updated = <String>[
      term,
      ..._searchHistory.where(
        (item) => item.toLowerCase() != normalized,
      ),
    ].take(20).toList();

    _safeSetState(() => _searchHistory = updated);
    _scheduleHistorySave();
  }

  void _removeSearchTerm(String value) {
    final normalized = value.toLowerCase();

    _safeSetState(() {
      _searchHistory.removeWhere(
        (item) => item.toLowerCase() == normalized,
      );
    });

    _scheduleHistorySave();
  }

  void _clearSearchHistory() {
    _safeSetState(() => _searchHistory.clear());
    _scheduleHistorySave();
  }

  bool _isAdultQuery(String query) {
    final normalized = query.toLowerCase().trim();

    if (normalized.isEmpty) return false;

    return _adultBlockTerms.any(
      (term) =>
          normalized == term || normalized.contains(term),
    );
  }

  void _onSearchChanged(String rawQuery) {
    final query = rawQuery.trim();

    _updateSuggestions(query);

    _debounce?.cancel();

    if (query.isEmpty) {
      _searchRequestId++;

      _safeSetState(() {
        _searchResults = <Movie>[];
        _allResults = <Movie>[];
        _mediaTypes.clear();
        _isSearching = false;
        _hasError = false;
        _blockedAdultQuery = false;
        _showHistory = _searchFocus.hasFocus;
      });

      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 320),
      () {
        if (!_isMounted || query != _searchController.text.trim()) {
          return;
        }

        _performSearch(query);
      },
    );
  }

  void _updateSuggestions(String query) {
    final normalized = query.toLowerCase().trim();

    if (normalized.isEmpty) {
      if (_suggestions.isNotEmpty) {
        _safeSetState(() => _suggestions = <String>[]);
      }
      return;
    }

    final seen = <String>{};
    final output = <String>[];

    void consider(String value) {
      final text = value.trim();
      if (text.isEmpty) return;

      final lower = text.toLowerCase();

      final matches = lower.startsWith(normalized) ||
          lower.contains(' $normalized');

      if (!matches || lower == normalized) return;

      if (seen.add(lower)) {
        output.add(text);
      }
    }

    for (final item in _searchHistory) {
      consider(item);
    }

    for (final item in _dynamicSearchKeywords) {
      consider(item);
    }

    final next = output.take(6).toList();

    if (!_sameStrings(_suggestions, next)) {
      _safeSetState(() => _suggestions = next);
    }
  }

  bool _sameStrings(List<String> a, List<String> b) {
    if (a.length != b.length) return false;

    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }

    return true;
  }

  Future<void> _performSearch(String query) async {
    final normalized = query.toLowerCase().trim();

    if (normalized.isEmpty) return;

    if (_isAdultQuery(normalized)) {
      _searchRequestId++;

      _safeSetState(() {
        _isSearching = false;
        _hasError = false;
        _blockedAdultQuery = true;
        _searchResults = <Movie>[];
        _allResults = <Movie>[];
        _mediaTypes.clear();
        _showHistory = false;
      });

      return;
    }

    if (_lastExecutedQuery == normalized &&
        !_hasError &&
        _allResults.isNotEmpty) {
      return;
    }

    final requestId = ++_searchRequestId;
    _lastExecutedQuery = normalized;

    final cached = _searchCache[normalized];

    if (cached != null) {
      _applySearchResults(cached);
      return;
    }

    _safeSetState(() {
      _isSearching = true;
      _hasError = false;
      _blockedAdultQuery = false;
      _showHistory = false;
    });

    try {
      final results = await _tmdbService.searchMovies(query);

      if (!_isMounted || requestId != _searchRequestId) return;

      final copy = List<Movie>.unmodifiable(results);
      _putSearchCache(normalized, copy);

      _applySearchResults(copy);
      _addSearchTerm(query);
    } catch (_) {
      if (!_isMounted || requestId != _searchRequestId) return;

      _safeSetState(() {
        _isSearching = false;
        _hasError = true;
        _searchResults = <Movie>[];
        _allResults = <Movie>[];
        _mediaTypes.clear();
      });
    }
  }

  void _putSearchCache(String key, List<Movie> value) {
    if (_searchCache.length >= _maxSearchCacheEntries &&
        !_searchCache.containsKey(key)) {
      // Drop oldest insertion (Map preserves insertion order in Dart).
      _searchCache.remove(_searchCache.keys.first);
    }
    _searchCache[key] = value;
  }

  void _jumpResultsToTop() {
    if (_resultsScrollController.hasClients) {
      _resultsScrollController.jumpTo(0);
    }
  }

  void _applySearchResults(List<Movie> results) {
    if (!_isMounted) return;

    // Cap payload early so grids stay light on lower-end devices.
    final limited = results.length > _maxResultsShown
        ? results.take(_maxResultsShown).toList(growable: false)
        : results;

    final mediaTypes = <int, String>{};
    for (final movie in limited) {
      mediaTypes[movie.id] = _guessMediaType(movie);
    }

    final filtered = _applyFilter(limited);

    _safeSetState(() {
      _allResults = limited;
      _mediaTypes
        ..clear()
        ..addAll(mediaTypes);
      _searchResults = filtered;
      _isSearching = false;
      _hasError = false;
      _blockedAdultQuery = false;
      _showHistory = false;
    });

    // After the frame, snap results list to top so rapid queries don't leave
    // the user mid-scroll on stale content (a common glitch source).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isMounted) return;
      _jumpResultsToTop();
      _prefetchResultPosters(filtered);
    });
  }

  void _prefetchResultPosters(List<Movie> movies) {
    if (!mounted || movies.isEmpty) return;
    for (final movie in movies.take(12)) {
      final url = movie.posterUrl;
      if (url.isEmpty) continue;
      // Warm image cache so the first grid paint is near-instant.
      // ignore: discarded_futures
      precacheImage(CachedNetworkImageProvider(url), context);
    }
  }

  String _guessMediaType(Movie movie) {
    final explicit = movie.mediaType.toLowerCase();

    if (explicit == 'tv' || explicit == 'movie') {
      return explicit;
    }

    final title = movie.title.toLowerCase();

    if (title.contains('season') ||
        title.contains('episode') ||
        title.contains('series')) {
      return 'tv';
    }

    return 'movie';
  }

  List<Movie> _applyFilter(List<Movie> source) {
    switch (_selectedFilter) {
      case 'Movies':
        return source
            .where(
              (movie) =>
                  (_mediaTypes[movie.id] ??
                      _guessMediaType(movie)) ==
                  'movie',
            )
            .toList();

      case 'Series':
        return source
            .where(
              (movie) =>
                  (_mediaTypes[movie.id] ??
                      _guessMediaType(movie)) ==
                  'tv',
            )
            .toList();

      case 'Anime':
        return source.where(_looksLikeAnime).toList();

      case 'All':
      default:
        return source;
    }
  }

  bool _looksLikeAnime(Movie movie) {
    final title = movie.title.toLowerCase();
    final overview = (movie.overview ?? '').toLowerCase();

    return title.contains('anime') ||
        title.contains('naruto') ||
        title.contains('one piece') ||
        title.contains('ghibli') ||
        overview.contains('anime') ||
        overview.contains('japanese animation');
  }

  void _onFilterChanged(String? value) {
    if (value == null || value == _selectedFilter) return;

    HapticFeedback.selectionClick();

    _safeSetState(() {
      _selectedFilter = value;
      _searchResults = _applyFilter(_allResults);
    });
  }

  Future<void> _onCategoryTapped(
    Map<String, dynamic> category,
  ) async {
    final label = category['label'] as String;
    final type = category['type'] as String;

    final cached = _categoryCache[type];

    _searchController.value = TextEditingValue(
      text: label,
      selection: TextSelection.collapsed(offset: label.length),
    );

    _addSearchTerm(label);

    if (cached != null) {
      _applySearchResults(cached);
      return;
    }

    final requestId = ++_categoryRequestId;

    HapticFeedback.selectionClick();

    _safeSetState(() {
      _isSearching = true;
      _hasError = false;
      _blockedAdultQuery = false;
      _showHistory = false;
    });

    try {
      final results = await _loadCategory(type);

      if (!_isMounted || requestId != _categoryRequestId) return;

      final copy = List<Movie>.unmodifiable(results);
      if (_categoryCache.length >= 16 && !_categoryCache.containsKey(type)) {
        _categoryCache.remove(_categoryCache.keys.first);
      }
      _categoryCache[type] = copy;

      _applySearchResults(copy);
    } catch (_) {
      if (!_isMounted || requestId != _categoryRequestId) return;

      _safeSetState(() {
        _isSearching = false;
        _hasError = true;
        _searchResults = <Movie>[];
        _allResults = <Movie>[];
      });
    }
  }

  Future<List<Movie>> _loadCategory(String type) {
    switch (type) {
      case 'trending':
        return _tmdbService.getTrendingMovies();
      case 'top_rated':
        return _tmdbService.getTopRatedMovies();
      case 'now_playing':
        return _tmdbService.getNowPlayingMovies();
      case 'action':
        return _tmdbService.getActionMovies();
      case 'scifi':
        return _tmdbService.getSciFiMovies();
      case 'drama':
        return _tmdbService.getDramaMovies();
      case 'comedy':
        return _tmdbService.getComedyMovies();
      case 'horror':
        return _tmdbService.getHorrorMovies();
      case 'anime':
        return _tmdbService.getAnimeTvShows();
      case 'tv':
        return _tmdbService.getTrendingTvShows();
      default:
        return _tmdbService.searchMovies(type);
    }
  }

  Future<void> _loadDynamicKeywords() async {
    try {
      final results = await _tmdbService.getTrendingMovies();

      if (!_isMounted) return;

      final titles = results
          .map((movie) => movie.title.trim())
          .where((title) => title.isNotEmpty)
          .toSet()
          .toList();

      titles.shuffle(Random());

      _safeSetState(() {
        _dynamicSearchKeywords = titles.take(12).toList();
      });
    } catch (_) {
      if (!_isMounted) return;

      _safeSetState(() {
        _dynamicSearchKeywords = <String>[
          'Blade Runner',
          'Inception',
          'Interstellar',
          'Dune',
          'The Matrix',
          'Arrival',
          'Ex Machina',
          'Ghost in the Shell',
        ];
      });
    }
  }

  Future<void> _loadTrendingAndPopular() async {
    final requestId = ++_contentRequestId;

    try {
      final results = await Future.wait<List<Movie>>(
        <Future<List<Movie>>>[
          _tmdbService.getTrendingMovies(),
          _tmdbService.getTrendingTvShows(),
        ],
      );

      if (!_isMounted || requestId != _contentRequestId) return;

      final movies = results[0];
      final shows = results[1];

      _safeSetState(() {
        _trendingNow = movies.take(12).toList();
        _popularMovies = <Movie>[
          ...movies.skip(4).take(6),
          ...shows.take(6),
        ];
        _isLoadingContent = false;
      });
    } catch (_) {
      if (!_isMounted || requestId != _contentRequestId) return;

      _safeSetState(() {
        _isLoadingContent = false;
        _hasError = true;
      });
    }
  }

  Future<void> _initSpeech() async {
    final speech = _speech;

    if (!_isMounted || speech == null) return;

    if (_isListening) {
      _stopListening();
      return;
    }

    try {
      final available = await speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' && _isMounted) {
            _safeSetState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (_isMounted) {
            _safeSetState(() => _isListening = false);
          }
        },
      );

      if (!_isMounted || _speech != speech) return;

      if (!available) {
        _toast('Speech recognition not available');
        return;
      }

      _startListening();
    } catch (_) {
      _toast('Could not start voice search');
    }
  }

  void _startListening() {
    final speech = _speech;

    if (!_isMounted || speech == null) return;

    _safeSetState(() {
      _isListening = true;
    });

    speech.listen(
      listenOptions: stt.SpeechListenOptions(
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 2),
        cancelOnError: true,
      ),
      onResult: (result) {
        if (!_isMounted || _speech != speech) return;

        final words = result.recognizedWords.trim();

        if (result.finalResult && words.isNotEmpty) {
          _stopListening();

          _searchController.value = TextEditingValue(
            text: words,
            selection: TextSelection.collapsed(
              offset: words.length,
            ),
          );

          _addSearchTerm(words);
          _performSearch(words);
        }
      },
    );
  }

  void _stopListening() {
    try {
      _speech?.stop();
    } catch (_) {}

    if (_isMounted) {
      _safeSetState(() => _isListening = false);
    }
  }

  void _onKeywordTapped(String keyword) {
    HapticFeedback.selectionClick();

    _searchController.value = TextEditingValue(
      text: keyword,
      selection: TextSelection.collapsed(
        offset: keyword.length,
      ),
    );

    _searchFocus.requestFocus();
    _addSearchTerm(keyword);
    _performSearch(keyword);
  }

  void _clearSearch() {
    _searchRequestId++;
    _categoryRequestId++;

    _searchController.clear();

    _safeSetState(() {
      _searchResults = <Movie>[];
      _allResults = <Movie>[];
      _mediaTypes.clear();
      _isSearching = false;
      _hasError = false;
      _blockedAdultQuery = false;
      _showHistory = _searchFocus.hasFocus;
      _lastExecutedQuery = '';
    });
  }

  void _retry() {
    HapticFeedback.lightImpact();

    final query = _searchController.text.trim();

    if (query.isNotEmpty) {
      _lastExecutedQuery = '';
      _performSearch(query);
      return;
    }

    _loadDynamicKeywords();
    _loadTrendingAndPopular();
  }

  void _openDetail(Movie movie) {
    if (!_isMounted || _isOpeningDetail) return;

    _isOpeningDetail = true;
    HapticFeedback.lightImpact();

    final isTv = (_mediaTypes[movie.id] ??
            _guessMediaType(movie)) ==
        'tv';

    Navigator.push(
      context,
      PageRouteBuilder<void>(
        transitionDuration: AppMotion.scaled(context, AppMotion.fast),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (_, _, _) => DetailScreen(
          movie: movie,
          isTv: isTv,
        ),
        transitionsBuilder: (_, animation, _, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    ).whenComplete(() {
      _isOpeningDetail = false;
    });
  }

  void _exitSearchScreen() {
    if (!_isMounted) return;

    HapticFeedback.lightImpact();

    _debounce?.cancel();
    _stopListening();
    _searchRequestId++;
    _categoryRequestId++;
    _searchFocus.unfocus();

    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  void _toast(String message) {
    if (!_isMounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: const Color(0xFF1A1A1A),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
  }

  List<InlineSpan> _highlightPrefix(
    String full,
    String prefix,
  ) {
    if (prefix.isEmpty) {
      return <InlineSpan>[TextSpan(text: full)];
    }

    final fullLower = full.toLowerCase();
    final prefixLower = prefix.toLowerCase();
    final index = fullLower.indexOf(prefixLower);

    if (index < 0) {
      return <InlineSpan>[TextSpan(text: full)];
    }

    return <InlineSpan>[
      if (index > 0)
        TextSpan(text: full.substring(0, index)),
      TextSpan(
        text: full.substring(
          index,
          index + prefix.length,
        ),
        style: const TextStyle(
          color: _gold,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (index + prefix.length < full.length)
        TextSpan(
          text: full.substring(index + prefix.length),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final pagePadding = Adaptive.pagePadding(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitSearchScreen();
      },
      child: Scaffold(
        backgroundColor: _bg,
        // Keyboard must NOT resize the whole tree (lists + grids) — that was
        // the main source of frame drops when the soft keyboard opened.
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: pagePadding.left,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Search',
                        style: FontService.instance.display(
                          color: Colors.white,
                          fontSize:
                              Adaptive.of(context) == ScreenType.mobile
                                  ? 26
                                  : 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      _buildFilterPill(),
                      const SizedBox(width: 8),
                      AppButton(
                        onPressed: _exitSearchScreen,
                        variant: AppButtonVariant.ghost,
                        size: AppButtonSize.small,
                        padding: EdgeInsets.zero,
                        borderRadius: AppDesignTokens.radiusFull,
                        semanticLabel: 'Close search',
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: pagePadding.left,
                  ),
                  child: _buildSearchField(),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: AppDesignTokens.contentWidth(context),
                      ),
                      child: FocusTraversalGroup(
                        policy: OrderedTraversalPolicy(),
                        child: _buildBody(hasQuery),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: Colors.white.withValues(alpha: 0.4),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) {
                _debounce?.cancel();
                _performSearch(value.trim());
              },
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
              ),
              cursorColor: _gold,
              // Explicitly disable every border state — the global input
              // theme paints a gold underline on focus, which read as a
              // "white line" beneath the search field.
              decoration: InputDecoration(
                hintText: 'Movies, series, anime…',
                hintStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.35),
                  fontSize: 14.5,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (_searchController.text.isEmpty)
            AppButton(
              onPressed: _initSpeech,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              padding: EdgeInsets.zero,
              borderRadius: AppDesignTokens.radiusFull,
              semanticLabel: 'Voice search',
              child: AnimatedContainer(
                duration: AppMotion.standardScaled(context),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isListening
                      ? AppDesignTokens.gold.withValues(alpha: 0.20)
                      : Colors.transparent,
                ),
                child: Icon(
                  _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: _isListening
                      ? AppDesignTokens.gold
                      : Colors.white.withValues(alpha: 0.5),
                  size: 20,
                ),
              ),
            )
          else
            AppButton(
              onPressed: _clearSearch,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              padding: EdgeInsets.zero,
              borderRadius: AppDesignTokens.radiusFull,
              semanticLabel: 'Clear search',
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white54,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(bool hasQuery) {
    if (_blockedAdultQuery) {
      return _buildAdultBlockedState();
    }

    if (_isSearching) {
      return Column(
        children: [
          if (_suggestions.isNotEmpty) _buildSuggestionsStrip(),
          Expanded(child: _buildSkeletonGrid()),
        ],
      );
    }

    if (_hasError) {
      return _buildErrorState();
    }

    if (hasQuery) {
      if (_searchResults.isEmpty) {
        return Column(
          children: [
            if (_suggestions.isNotEmpty) _buildSuggestionsStrip(),
            Expanded(child: _buildEmptyResults()),
          ],
        );
      }

      return Column(
        children: [
          if (_suggestions.isNotEmpty) _buildSuggestionsStrip(),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Row(
              children: [
                Text(
                  '${_searchResults.length} result${_searchResults.length == 1 ? '' : 's'}',
                  style: FontService.instance.label(
                    color: Colors.white54,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                if (_selectedFilter != 'All')
                  Text(
                    _selectedFilter,
                    style: FontService.instance.label(
                      color: _gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PrimaryScrollController(
              controller: _resultsScrollController,
              child: _buildResultsGrid(),
            ),
          ),
        ],
      );
    }

    return _buildDiscovery();
  }

  Widget _buildSuggestionsStrip() {
    final padding = Adaptive.pagePadding(context);
    final query = _searchController.text.trim();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        padding.left,
        0,
        padding.right,
        8,
      ),
      child: Column(
        children: [
          for (final suggestion in _suggestions)
            AppButton(
              onPressed: () => _onKeywordTapped(suggestion),
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              padding: const EdgeInsets.symmetric(vertical: 5),
              borderRadius: AppDesignTokens.radiusSm,
              fullWidth: true,
              semanticLabel: suggestion,
              child: Row(
                children: [
                  Icon(
                    Icons.north_west_rounded,
                    size: 15,
                    color: Colors.white.withValues(alpha: 0.35),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: AppDesignTokens.bodyMedium().copyWith(
                          color: Colors.white70,
                          fontSize: 13.5,
                        ),
                        children: _highlightPrefix(
                          suggestion,
                          query,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDiscovery() {
    final padding = Adaptive.pagePadding(context);

    // Isolate discovery paint from search-bar / keyboard-driven rebuilds.
    return RepaintBoundary(
      child: SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        padding.left,
        0,
        padding.right,
        40,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_showHistory && _searchHistory.isNotEmpty)
            _buildHistory(),
          const SizedBox(height: 12),
          const AddonsSearchRail(),
          _buildCategories(),
          const SizedBox(height: 22),
          _buildKeywordPanel(),
          const SizedBox(height: 24),
          Text(
            'Trending now',
            style: FontService.instance.display(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildTrendingRow(),
          const SizedBox(height: 24),
          Text(
            'Popular right now',
            style: FontService.instance.display(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          _buildPopularGrid(),
        ],
      ),
      ),
    );
  }

  Widget _buildHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent searches',
              style: FontService.instance.label(
                color: Colors.white54,
                fontSize: 12,
                letterSpacing: 0.6,
              ),
            ),
            AppButton(
              onPressed: _clearSearchHistory,
              variant: AppButtonVariant.ghost,
              size: AppButtonSize.small,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              semanticLabel: 'Clear search history',
              child: Text(
                'Clear all',
                style: AppDesignTokens.labelSmall().copyWith(
                  color: AppDesignTokens.error.withValues(alpha: 0.8),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _searchHistory.map((term) {
            return AppChip(
              label: term,
              variant: AppChipVariant.secondary,
              size: AppChipSize.medium,
              onTap: () => _onKeywordTapped(term),
              onDeleted: () => _removeSearchTerm(term),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildCategories() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Browse by category',
          style: FontService.instance.label(
            color: Colors.white54,
            fontSize: 12,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final category = _categories[index];

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: AppChip(
                  label: category['label'] as String,
                  icon: Icon(category['icon'] as IconData, size: 14),
                  variant: AppChipVariant.secondary,
                  size: AppChipSize.small,
                  onTap: () => _onCategoryTapped(category),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildKeywordPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: AppDesignTokens.radiusLg,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Everyone searching',
            style: FontService.instance.label(
              color: Colors.white54,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (_dynamicSearchKeywords.isEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(
                6,
                (_) => _buildStaticPlaceholder(
                  width: 72,
                  height: 26,
                ),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _dynamicSearchKeywords.map((keyword) {
                return AppChip(
                  label: keyword,
                  variant: AppChipVariant.secondary,
                  size: AppChipSize.small,
                  onTap: () => _onKeywordTapped(keyword),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildTrendingRow() {
    if (_isLoadingContent) {
      return SizedBox(
        height: 200,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: 5,
          itemBuilder: (_, index) {
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SizedBox(
                width: Adaptive.cardWidth(context),
                child: _buildSkeletonItem(),
              ),
            );
          },
        ),
      );
    }

    return SizedBox(
      height: 200,
      child: ListView.builder(
        scrollCacheExtent: ScrollCacheExtent.pixels(600), key: const PageStorageKey<String>('trending-row'),
        scrollDirection: Axis.horizontal,
        itemCount: _trendingNow.length,
        itemBuilder: (context, index) {
          final movie = _trendingNow[index];

          return RepaintBoundary(
            key: ValueKey<int>(movie.id),
            child: SizedBox(
              width: Adaptive.cardWidth(context),
              child: PosterCard(
                movie: movie,
                size: PosterCardSize.medium,
                heroTagPrefix: 'search-trending',
                onTap: () => _openDetail(movie),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPopularGrid() {
    final count = min(_popularMovies.length, 9);

    return ResponsiveGrid(
      itemCount: count,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.62,
      mobileColumns: 3,
      tabletColumns: 4,
      desktopColumns: 6,
      wideColumns: 8,
      itemBuilder: (context, index) {
        final movie = _popularMovies[index];

        return RepaintBoundary(
          key: ValueKey<int>(movie.id),
          child: PosterCard(
            movie: movie,
            size: PosterCardSize.medium,
            heroTagPrefix: 'search-popular',
            showMetadata: true,
            onTap: () => _openDetail(movie),
          ),
        );
      },
    );
  }

  Widget _buildResultsGrid() {
    return ResponsiveGrid(
      itemCount: _searchResults.length,
      childAspectRatio: 0.64,
      mobileColumns: 2,
      tabletColumns: 4,
      desktopColumns: 6,
      wideColumns: 8,
      itemBuilder: (context, index) {
        final movie = _searchResults[index];

        return RepaintBoundary(
          key: ValueKey<int>(movie.id),
          child: PosterCard(
            movie: movie,
            size: PosterCardSize.medium,
            heroTagPrefix: 'search-results',
            onTap: () => _openDetail(movie),
            showQuickActions: false,
            showMetadata: true,
          ),
        );
      },
    );
  }

  Widget _buildSkeletonGrid() {
    return ResponsiveGrid(
      itemCount: 8,
      childAspectRatio: 0.64,
      mobileColumns: 2,
      tabletColumns: 4,
      desktopColumns: 6,
      itemBuilder: (_, _) => _buildSkeletonItem(),
    );
  }

  Widget _buildSkeletonItem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _buildStaticPlaceholder(
            width: double.infinity,
            height: double.infinity,
          ),
        ),
        const SizedBox(height: 6),
        _buildStaticPlaceholder(width: 120, height: 14),
        const SizedBox(height: 4),
        _buildStaticPlaceholder(width: 80, height: 12),
      ],
    );
  }

  Widget _buildStaticPlaceholder({
    required double width,
    required double height,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }

  Widget _buildEmptyResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off_rounded,
            color: Colors.white.withValues(alpha: 0.25),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'No results found',
            style: FontService.instance.display(
              color: Colors.white54,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a different title or category',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.35),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            color: Colors.white.withValues(alpha: 0.3),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Something went wrong',
            style: FontService.instance.display(
              color: Colors.white54,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          AppButton(
            onPressed: _retry,
            variant: AppButtonVariant.secondary,
            size: AppButtonSize.medium,
            borderRadius: AppDesignTokens.radiusXl,
            leadingIcon: const Icon(Icons.refresh_rounded, size: 18),
            child: const Text('Try again'),
          ),
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
            Icon(
              Icons.shield_rounded,
              color: Colors.white.withValues(alpha: 0.3),
              size: 52,
            ),
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
              'Adult or explicit searches are blocked so the experience stays safe and suitable for all ages.',
              textAlign: TextAlign.center,
              style: AppDesignTokens.bodyMedium().copyWith(
                color: Colors.white.withValues(alpha: 0.4),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            AppButton(
              onPressed: _clearSearch,
              variant: AppButtonVariant.secondary,
              size: AppButtonSize.medium,
              borderRadius: AppDesignTokens.radiusXl,
              child: const Text('Search something else'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterPill() {
    return AppButton(
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: const Color(0xFF1A1A1A),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(18),
            ),
          ),
          builder: (sheetContext) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _filterOptions.map((option) {
                  final selected = option == _selectedFilter;

                  return ListTile(
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _onFilterChanged(option);
                    },
                    title: Text(
                      option,
                      style: TextStyle(
                        color: selected ? AppDesignTokens.gold : Colors.white,
                      ),
                    ),
                    trailing: selected
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppDesignTokens.gold,
                          )
                        : null,
                  );
                }).toList(),
              ),
            );
          },
        );
      },
      variant: AppButtonVariant.secondary,
      size: AppButtonSize.small,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      borderRadius: AppDesignTokens.radiusFull,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _selectedFilter,
            style: AppDesignTokens.labelMedium().copyWith(
              color: Colors.white70,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 16,
            color: Colors.white54,
          ),
        ],
      ),
    );
  }
}