import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/tokens.dart';
import '../models/movie.dart';
import '../services/continue_watching_service.dart';
import '../services/download_service.dart';
import '../services/font_service.dart';
import '../services/user_library_service.dart';
import '../services/watch_analytics_service.dart';
import '../widgets/app_card.dart';
import '../widgets/cinematic_3d_backdrop.dart';

const _gold = AppDesignTokens.goldMuted;
const _bg = AppDesignTokens.backgroundCanvas;

class WatchAnalyticsScreen extends StatefulWidget {
  const WatchAnalyticsScreen({super.key});
  @override
  State<WatchAnalyticsScreen> createState() => _WatchAnalyticsScreenState();
}

class _WatchAnalyticsScreenState extends State<WatchAnalyticsScreen> {
  final _analytics = WatchAnalyticsService.instance;
  final _library = UserLibraryService.instance;
  List<Map<String, dynamic>> _continue = [];

  @override
  void initState() {
    super.initState();
    _analytics.addListener(_refresh);
    _library.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    _analytics.removeListener(_refresh);
    _library.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() { if (mounted) setState(() {}); }

  Future<void> _load() async {
    try { _continue = await ContinueWatchingService.getEntries(); } catch (_) {}
    if (mounted) setState(() {});
  }

  List<Movie> get _watched => _library.watched;
  List<Movie> get _watchlist => _library.watchlist;
  List<Map<String, dynamic>> get _watchEvents => _analytics.events.where((e) => e['type'] == 'watched').toList();
  int _year(Movie m) => int.tryParse(m.releaseYear) ?? 0;

  Map<String, int> _decades() {
    final map = <String, int>{};
    for (final m in _watched) {
      final y = _year(m); if (y < 1900) continue;
      final decade = '${(y ~/ 10) * 10}s'; map[decade] = (map[decade] ?? 0) + 1;
    }
    return map;
  }

  Map<String, int> _types() {
    var movies = 0, shows = 0;
    for (final m in _watched) { if (m.mediaType.toLowerCase() == 'tv') { shows++; } else { movies++; } }
    return {'Movies': movies, 'TV Shows': shows};
  }

  List<int> _weekdayCounts() {
    final counts = List<int>.filled(7, 0);
    for (final e in _watchEvents) {
      final t = DateTime.fromMillisecondsSinceEpoch((e['timestamp'] as num?)?.toInt() ?? 0);
      if (t.year > 1970) counts[t.weekday - 1]++;
    }
    return counts;
  }

  List<int> _monthCounts() {
    final now = DateTime.now(); final counts = List<int>.filled(12, 0);
    for (final e in _watchEvents) {
      final t = DateTime.fromMillisecondsSinceEpoch((e['timestamp'] as num?)?.toInt() ?? 0);
      final diff = (now.year - t.year) * 12 + now.month - t.month;
      if (diff >= 0 && diff < 12) counts[11 - diff]++;
    }
    return counts;
  }

  List<int> _watchlistGrowth() {
    final counts = List<int>.filled(12, 0); final now = DateTime.now();
    for (final e in _analytics.events.where((e) => e['type'] == 'watchlist_add')) {
      final t = DateTime.fromMillisecondsSinceEpoch((e['timestamp'] as num?)?.toInt() ?? 0);
      final diff = (now.year - t.year) * 12 + now.month - t.month;
      if (diff >= 0 && diff < 12) counts[11 - diff]++;
    }
    return counts;
  }

  List<String> _monthLabels() {
    final now = DateTime.now();
    const names = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return List.generate(12, (i) => names[DateTime(now.year, now.month - (11 - i), 1).month - 1]);
  }

  Map<String, int> _ratingsDistribution() {
    final map = {for (var i = 1; i <= 5; i++) '$i': 0};
    for (final value in _analytics.ratings.values) {
      final bucket = value.round().clamp(1, 5).toString(); map[bucket] = (map[bucket] ?? 0) + 1;
    }
    return map;
  }

  double get _averageRating {
    if (_analytics.ratings.isEmpty) return 0;
    return _analytics.ratings.values.reduce((a, b) => a + b) / _analytics.ratings.length;
  }

  @override
  Widget build(BuildContext context) {
    final decades = _decades(); final types = _types(); final weekdays = _weekdayCounts(); final months = _monthCounts();
    final ratings = _ratingsDistribution(); final total = math.max(1, _watched.length);
    return Cinematic3DBackdrop(
      intensity: 0.7,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: Colors.transparent, elevation: 0, titleSpacing: 18,
          title: Text('Your viewing analytics', style: FontService.instance.style(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
          leading: IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.arrow_back_rounded, color: Colors.white)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 36),
          children: [
            _heroSummary(),
            _section(icon: Icons.campaign_outlined, title: 'Directors you watch most', subtitle: 'Your library ranking', child: _EmptyState(text: _watched.isEmpty ? 'Watch titles to build this ranking.' : 'Director credits are not stored in the local Movie model yet, so FEB does not guess this data.')),
            _section(icon: Icons.movie_creation_outlined, title: 'What you watch', subtitle: 'By content type', child: _TypeBars(types: types, total: total)),
            _section(icon: Icons.local_movies_outlined, title: 'Across the decades', subtitle: 'Titles by release era', child: _DecadeChart(data: decades)),
            _section(icon: Icons.calendar_month_outlined, title: 'Your week', subtitle: 'Watched titles by weekday', child: _VerticalBars(values: weekdays, labels: const ['M','T','W','T','F','S','S'])),
            _section(icon: Icons.bookmark_border_rounded, title: 'Watchlist growth', subtitle: 'Titles saved · last 12 months', child: _VerticalBars(values: _watchlistGrowth(), labels: _monthLabels())),
            _section(icon: Icons.emoji_events_outlined, title: 'Milestones', subtitle: 'How far you have made it through your personal canon', child: _Milestones(watched: _watched.length)),
            _section(icon: Icons.star_outline_rounded, title: 'Your ratings', subtitle: 'How you score what you watch', child: _RatingsChart(average: _averageRating, ratings: ratings)),
            _section(icon: Icons.calendar_today_outlined, title: 'Your watching rhythm', subtitle: 'Titles watched · last 12 months', child: _VerticalBars(values: months, labels: _monthLabels())),
            _section(icon: Icons.auto_awesome_outlined, title: 'Genres · Countries · Languages', subtitle: 'Most watched across your library', child: _MetadataBreakdown(watched: _watched)),
            _section(icon: Icons.groups_2_outlined, title: 'Cast you watch most', subtitle: 'Repeated cast members', child: _EmptyState(text: _watched.isEmpty ? 'Watch titles to build this ranking.' : 'Cast credits are not stored locally yet, so FEB keeps this insight accurate instead of guessing.')),
            _section(icon: Icons.play_circle_outline_rounded, title: 'Currently watching', subtitle: 'Resume points saved on this device', child: _ContinueWatching(entries: _continue)),
            _section(icon: Icons.download_outlined, title: 'Downloads', subtitle: 'Offline library snapshot', child: _DownloadSummary()),
            AppCard(borderRadius: BorderRadius.circular(22), padding: const EdgeInsets.all(14), child: const Row(children: [Icon(Icons.insights_rounded, color: _gold, size: 20), SizedBox(width: 10), Expanded(child: Text('Analytics are calculated from your local FEB library. Watching history becomes more precise as you finish or rate titles.', style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4)))])),
          ],
        ),
      ),
    );
  }

  Widget _heroSummary() => AppCard(
    borderRadius: BorderRadius.circular(24), padding: const EdgeInsets.all(18), backgroundColor: Colors.white.withValues(alpha: 0.045),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: _gold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.insights_rounded, color: _gold)), const SizedBox(width: 12), Expanded(child: Text('Your watching profile', style: FontService.instance.style(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)))]),
      const SizedBox(height: 16), Row(children: [_miniStat('${_watched.length}', 'Watched'), _miniStat('${_watchlist.length}', 'Watchlist'), _miniStat('${_continue.length}', 'In progress'), _miniStat('${DownloadService.instance.items.length}', 'Downloads')]),
    ]),
  );

  Widget _miniStat(String value, String label) => Expanded(child: Column(children: [Text(value, style: const TextStyle(color: _gold, fontSize: 21, fontWeight: FontWeight.w800)), const SizedBox(height: 3), Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9))]));

  Widget _section({required IconData icon, required String title, required String subtitle, required Widget child}) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: AppCard(borderRadius: BorderRadius.circular(24), padding: const EdgeInsets.fromLTRB(16, 16, 16, 15), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: _gold.withValues(alpha: 0.11), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: _gold, size: 19)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(height: 2), Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 10))]))]),
      const SizedBox(height: 15), child,
    ])),
  );
}

class _TypeBars extends StatelessWidget { final Map<String,int> types; final int total; const _TypeBars({required this.types,required this.total}); @override Widget build(BuildContext context)=>Column(children:types.entries.map((e){final pct=e.value/total;return Padding(padding:const EdgeInsets.only(bottom:12),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(e.key,style:const TextStyle(color:Colors.white70,fontSize:13)),Text('${(pct*100).round()}% · ${e.value}',style:const TextStyle(color:Colors.white54,fontSize:12))]),const SizedBox(height:7),ClipRRect(borderRadius:BorderRadius.circular(8),child:LinearProgressIndicator(value:pct,minHeight:8,backgroundColor:Colors.white10,valueColor:const AlwaysStoppedAnimation(_gold))) ]));}).toList()); }

class _DecadeChart extends StatelessWidget { final Map<String,int> data; const _DecadeChart({required this.data}); @override Widget build(BuildContext context){if(data.isEmpty)return const _EmptyState(text:'Watch more titles to build your decade profile.');final entries=data.entries.toList()..sort((a,b)=>a.key.compareTo(b.key));final maxValue=entries.map((e)=>e.value).fold<int>(1,(a,b)=>a>b?a:b);return SizedBox(height:170,child:Column(children:[Expanded(child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:entries.map((e)=>Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[Text('${e.value}',style:const TextStyle(color:Colors.white54,fontSize:10)),const SizedBox(height:4),Container(height:105*e.value/maxValue,decoration:BoxDecoration(color:_gold.withValues(alpha:.75),borderRadius:const BorderRadius.vertical(top:Radius.circular(8))))])))).toList())),const SizedBox(height:7),Row(children:entries.map((e)=>Expanded(child:Text(e.key,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white38,fontSize:9)))).toList())]));}}

class _VerticalBars extends StatelessWidget { final List<int> values; final List<String> labels; const _VerticalBars({required this.values,required this.labels}); @override Widget build(BuildContext context){final maxValue=values.fold<int>(1,(a,b)=>a>b?a:b);return SizedBox(height:170,child:Column(children:[Expanded(child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:List.generate(values.length,(i)=>Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[Text('${values[i]}',style:const TextStyle(color:Colors.white38,fontSize:9)),const SizedBox(height:4),Container(height:105*values[i]/maxValue,decoration:BoxDecoration(color:values[i]==maxValue&&values[i]>0?_gold:Colors.white.withValues(alpha:.035),borderRadius:const BorderRadius.vertical(top:Radius.circular(7))))]))))),),const SizedBox(height:7),Row(children:List.generate(labels.length,(i)=>Expanded(child:Text(labels[i],textAlign:TextAlign.center,style:const TextStyle(color:Colors.white38,fontSize:8))))]));}}

class _Milestones extends StatelessWidget { final int watched; const _Milestones({required this.watched}); @override Widget build(BuildContext context){const goals=[25,50,100,150,250,500];return Wrap(spacing:10,runSpacing:14,children:goals.map((goal){final p=(watched/goal).clamp(0.0,1.0);return SizedBox(width:(MediaQuery.sizeOf(context).width-74)/2,child:Column(children:[SizedBox(width:82,height:82,child:Stack(alignment:Alignment.center,children:[CircularProgressIndicator(value:p,strokeWidth:6,backgroundColor:Colors.white10,valueColor:const AlwaysStoppedAnimation(_gold)),Text('${(p*100).round()}%',style:const TextStyle(color:Colors.white,fontWeight:FontWeight.w800))])),const SizedBox(height:6),Text('$goal titles',style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w700)),Text('$watched of $goal',style:const TextStyle(color:Colors.white38,fontSize:9))]));}).toList());}}

class _RatingsChart extends StatelessWidget { final double average; final Map<String,int> ratings; const _RatingsChart({required this.average,required this.ratings}); @override Widget build(BuildContext context)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Text(average==0?'—':average.toStringAsFixed(1),style:const TextStyle(color:_gold,fontSize:24,fontWeight:FontWeight.w900)),const SizedBox(width:8),Text('avg · ${ratings.values.fold<int>(0,(a,b)=>a+b)} ratings',style:const TextStyle(color:Colors.white54,fontSize:11))]),const SizedBox(height:12),SizedBox(height:110,child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:ratings.entries.map((e){final max=math.max(1,ratings.values.fold<int>(0,(a,b)=>a>b?a:b));final h=78*e.value/max;return Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:4),child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[Text('${e.value}',style:const TextStyle(color:Colors.white38,fontSize:8)),Container(height:h,decoration:BoxDecoration(color:_gold.withValues(alpha:.85),borderRadius:const BorderRadius.vertical(top:Radius.circular(6)))),const SizedBox(height:4),Text(e.key,style:const TextStyle(color:Colors.white38,fontSize:8))])));}).toList()))]); }
}

class _MetadataBreakdown extends StatelessWidget { final List<Movie> watched; const _MetadataBreakdown({required this.watched}); @override Widget build(BuildContext context){if(watched.isEmpty)return const _EmptyState(text:'Your genres, countries and languages will appear here as your library grows.');return const _EmptyState(text:'Detailed genres, countries and spoken languages require TMDB detail metadata. FEB keeps this panel accurate rather than guessing from incomplete local records.');}}

class _ContinueWatching extends StatelessWidget { final List<Map<String,dynamic>> entries; const _ContinueWatching({required this.entries}); @override Widget build(BuildContext context){if(entries.isEmpty)return const _EmptyState(text:'Nothing in progress right now.');return Column(children:entries.take(5).map((e){final m=ContinueWatchingService.movieFromEntry(e);if(m==null)return const SizedBox.shrink();final pos=(e['position'] as num?)?.toInt()??0;final dur=(e['duration'] as num?)?.toInt()??0;final p=dur>0?(pos/dur).clamp(0.0,1.0):0.0;return Padding(padding:const EdgeInsets.only(bottom:10),child:Row(children:[ClipRRect(borderRadius:BorderRadius.circular(8),child:Image.network(m.posterUrl,width:42,height:60,fit:BoxFit.cover,errorBuilder:(_,_,_)=>Container(width:42,height:60,color:Colors.white10))),const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(m.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white,fontSize:12,fontWeight:FontWeight.w700)),const SizedBox(height:7),LinearProgressIndicator(value:p,minHeight:5,backgroundColor:Colors.white10,valueColor:const AlwaysStoppedAnimation(_gold)),const SizedBox(height:4),Text('${(p*100).round()}% watched',style:const TextStyle(color:Colors.white38,fontSize:9))]))]));}).toList());}}

class _DownloadSummary extends StatelessWidget { @override Widget build(BuildContext context){final items=DownloadService.instance.items;return Row(children:[_stat('${items.length}','Saved'),_stat('${items.length}','Local'),_stat('${items.length}','Tracked')]);} Widget _stat(String v,String l)=>Expanded(child:Column(children:[Text(v,style:const TextStyle(color:_gold,fontSize:20,fontWeight:FontWeight.w800)),const SizedBox(height:3),Text(l,style:const TextStyle(color:Colors.white38,fontSize:9))]));}}

class _EmptyState extends StatelessWidget { final String text; const _EmptyState({required this.text}); @override Widget build(BuildContext context)=>Container(width:double.infinity,padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:Colors.white.withValues(alpha:.025),borderRadius:BorderRadius.circular(14)),child:Text(text,style:const TextStyle(color:Colors.white38,fontSize:10.5,height:1.4))); }
