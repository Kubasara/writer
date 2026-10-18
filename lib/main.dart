import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const WriterApp());
}

// ============ 工具函数 ============

String two(int n) => n.toString().padLeft(2, '0');

String keyFor(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';

String todayKey() => keyFor(DateTime.now());

int nowMs() => DateTime.now().millisecondsSinceEpoch;

// ============ 数据模型 ============

class Session {
  final int start;
  final int minutes;
  final int words;

  Session({required this.start, required this.minutes, required this.words});

  Map<String, dynamic> toJson() =>
      {'start': start, 'minutes': minutes, 'words': words};

  static Session fromJson(Map<String, dynamic> j) => Session(
        start: (j['start'] as num?)?.toInt() ?? 0,
        minutes: (j['minutes'] as num?)?.toInt() ?? 0,
        words: (j['words'] as num?)?.toInt() ?? 0,
      );
}

class DayRecord {
  int words;
  int goal;
  List<Session> sessions;
  int updatedAt;

  DayRecord({
    this.words = 0,
    this.goal = 0,
    List<Session>? sessions,
    this.updatedAt = 0,
  }) : sessions = sessions ?? [];

  Map<String, dynamic> toJson() => {
        'words': words,
        'goal': goal,
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'updatedAt': updatedAt,
      };

  static DayRecord fromJson(Map<String, dynamic> j) => DayRecord(
        words: (j['words'] as num?)?.toInt() ?? 0,
        goal: (j['goal'] as num?)?.toInt() ?? 0,
        sessions: ((j['sessions'] as List?) ?? [])
            .map((e) => Session.fromJson(e as Map<String, dynamic>))
            .toList(),
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class Settings {
  int dailyGoal;
  int focusMinutes;
  String webdavUrl;
  String webdavUser;
  String webdavPass;
  bool syncEnabled;
  int updatedAt;

  Settings({
    this.dailyGoal = 4000,
    this.focusMinutes = 25,
    this.webdavUrl = 'https://dav.jianguoyun.com/dav/',
    this.webdavUser = '',
    this.webdavPass = '',
    this.syncEnabled = false,
    this.updatedAt = 0,
  });

  Map<String, dynamic> toJson() => {
        'dailyGoal': dailyGoal,
        'focusMinutes': focusMinutes,
        'webdavUrl': webdavUrl,
        'webdavUser': webdavUser,
        'webdavPass': webdavPass,
        'syncEnabled': syncEnabled,
        'updatedAt': updatedAt,
      };

  static Settings fromJson(Map<String, dynamic> j) => Settings(
        dailyGoal: (j['dailyGoal'] as num?)?.toInt() ?? 4000,
        focusMinutes: (j['focusMinutes'] as num?)?.toInt() ?? 25,
        webdavUrl:
            (j['webdavUrl'] as String?) ?? 'https://dav.jianguoyun.com/dav/',
        webdavUser: (j['webdavUser'] as String?) ?? '',
        webdavPass: (j['webdavPass'] as String?) ?? '',
        syncEnabled: (j['syncEnabled'] as bool?) ?? false,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class AppData {
  Settings settings;
  Map<String, DayRecord> days;
  Map<String, int> achievements;

  AppData({
    required this.settings,
    Map<String, DayRecord>? days,
    Map<String, int>? achievements,
  })  : days = days ?? {},
        achievements = achievements ?? {};

  static AppData empty() => AppData(settings: Settings());

  Map<String, dynamic> toJson() => {
        'settings': settings.toJson(),
        'days': days.map((k, v) => MapEntry(k, v.toJson())),
        'achievements': achievements,
      };

  static AppData fromJson(Map<String, dynamic> j) => AppData(
        settings: Settings.fromJson(
            (j['settings'] as Map<String, dynamic>?) ?? {}),
        days: ((j['days'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(k, DayRecord.fromJson(v as Map<String, dynamic>))),
        achievements: ((j['achievements'] as Map<String, dynamic>?) ?? {})
            .map((k, v) => MapEntry(k, (v as num).toInt())),
      );
}

// ============ 统计计算 ============

int totalWords(AppData d) =>
    d.days.values.fold(0, (sum, day) => sum + day.words);

int totalSessions(AppData d) =>
    d.days.values.fold(0, (sum, day) => sum + day.sessions.length);

int currentStreak(AppData d) {
  var day = DateTime.now();
  int streak = 0;
  if ((d.days[keyFor(day)]?.words ?? 0) <= 0) {
    day = day.subtract(const Duration(days: 1));
  }
  while ((d.days[keyFor(day)]?.words ?? 0) > 0) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  return streak;
}

int maxStreakEver(AppData d) {
  final keys = d.days.keys.toList()..sort();
  int best = 0;
  int run = 0;
  DateTime? prev;
  for (final k in keys) {
    final p = k.split('-');
    final dt = DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
    if ((d.days[k]?.words ?? 0) > 0) {
      if (prev != null && dt.difference(prev).inDays == 1) {
        run++;
      } else {
        run = 1;
      }
      prev = dt;
      if (run > best) best = run;
    } else {
      run = 0;
      prev = null;
    }
  }
  return best;
}

int bestStreak(AppData d) {
  final a = currentStreak(d);
  final b = maxStreakEver(d);
  return a > b ? a : b;
}

int xpNeededForLevel(int level) => 1000 * (level - 1) * level ~/ 2;

int levelFor(int xp) {
  int level = 1;
  while (xp >= xpNeededForLevel(level + 1)) {
    level++;
  }
  return level;
}

const Map<int, String> kTitles = {
  1: '萌新作者',
  3: '入门写手',
  5: '稳定日更',
  7: '小有名气',
  10: '爆更狂魔',
  15: '白金预备',
  20: '大神之姿',
  30: '一代宗师',
  50: '网文之神',
};

String titleFor(int level) {
  String t = '萌新作者';
  kTitles.forEach((k, v) {
    if (level >= k) t = v;
  });
  return t;
}

int bestDayWords(AppData d) {
  int best = 0;
  d.days.forEach((_, day) {
    if (day.words > best) best = day.words;
  });
  return best;
}

double avgWords(AppData d) {
  if (d.days.isEmpty) return 0;
  return totalWords(d) / d.days.length;
}

// ============ 成就 ============

class AchievementDef {
  final String id;
  final String name;
  final String desc;
  final String icon;
  final bool Function(AppData) condition;
  const AchievementDef(this.id, this.name, this.desc, this.icon, this.condition);
}

final List<AchievementDef> kAchievements = [
  AchievementDef('first_day', '首次打卡', '记录下第一个字的字数', '🐣',
      (d) => d.days.values.any((x) => x.words > 0)),
  AchievementDef('streak_3', '三日之约', '连续打卡 3 天', '🔥', (d) => bestStreak(d) >= 3),
  AchievementDef('streak_7', '七日成习', '连续打卡 7 天', '⚡', (d) => bestStreak(d) >= 7),
  AchievementDef('streak_14', '半月坚持', '连续打卡 14 天', '🌊', (d) => bestStreak(d) >= 14),
  AchievementDef('streak_30', '三十而立', '连续打卡 30 天', '🏔️', (d) => bestStreak(d) >= 30),
  AchievementDef('total_10k', '万字户', '累计码字 1 万', '✍️', (d) => totalWords(d) >= 10000),
  AchievementDef('total_100k', '十万字', '累计码字 10 万', '📖', (d) => totalWords(d) >= 100000),
  AchievementDef('total_1m', '百万成神', '累计码字 100 万', '👑', (d) => totalWords(d) >= 1000000),
  AchievementDef('day_10k', '日更过万', '单日码字突破 1 万', '💥', (d) => bestDayWords(d) >= 10000),
  AchievementDef('day_20k', '爆肝达人', '单日码字突破 2 万', '🚀', (d) => bestDayWords(d) >= 20000),
  AchievementDef('focus_1', '专注第一课', '完成 1 次专注计时', '🍅', (d) => totalSessions(d) >= 1),
  AchievementDef('focus_10', '专注十连', '完成 10 次专注计时', '⏰', (d) => totalSessions(d) >= 10),
  AchievementDef('focus_50', '专注成瘾', '完成 50 次专注计时', '🧘', (d) => totalSessions(d) >= 50),
];

// ============ 本地存储 ============

class LocalStore {
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}writer_data.json');
  }

  static Future<void> save(AppData data) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(data.toJson()));
    } catch (_) {}
  }

  static Future<AppData?> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final s = await f.readAsString();
      return AppData.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}

// ============ 坚果云 WebDAV 同步 ============

class WebDav {
  static Map<String, String> _headers(Settings s) => {
        'Authorization':
            'Basic ${base64Encode(utf8.encode('${s.webdavUser}:${s.webdavPass}'))}',
      };

  static String _base(Settings s) =>
      s.webdavUrl.endsWith('/') ? s.webdavUrl : '${s.webdavUrl}/';

  static String _fileUrl(Settings s) => '${_base(s)}writer/writer_data.json';

  static Future<void> _mkcol(Settings s) async {
    final client = http.Client();
    try {
      final req = http.Request('MKCOL', Uri.parse('${_base(s)}writer/'));
      req.headers.addAll(_headers(s));
      final res = await client.send(req);
      await res.stream.drain();
    } catch (_) {
    } finally {
      client.close();
    }
  }

  static Future<String?> download(Settings s) async {
    try {
      final resp = await http
          .get(Uri.parse(_fileUrl(s)), headers: _headers(s))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) return resp.body;
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> upload(Settings s, String content) async {
    try {
      await _mkcol(s);
      final resp = await http
          .put(Uri.parse(_fileUrl(s)),
              headers: {
                ..._headers(s),
                'Content-Type': 'application/json; charset=utf-8',
              },
              body: content)
          .timeout(const Duration(seconds: 15));
      return resp.statusCode >= 200 && resp.statusCode < 300;
    } catch (_) {
      return false;
    }
  }

  static Future<String> test(Settings s) async {
    if (s.webdavUser.isEmpty || s.webdavPass.isEmpty) {
      return '请先填写账号和应用密码';
    }
    try {
      final resp = await http
          .get(Uri.parse(_fileUrl(s)), headers: _headers(s))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return '账号或应用密码错误';
      }
      if (resp.statusCode == 200 || resp.statusCode == 404) {
        return '连接成功 ✓';
      }
      return '返回码 ${resp.statusCode}';
    } catch (_) {
      return '连接失败：请检查网络或地址';
    }
  }
}

// ============ 合并 ============

AppData mergeData(AppData a, AppData b) {
  final settings =
      a.settings.updatedAt >= b.settings.updatedAt ? a.settings : b.settings;
  final days = <String, DayRecord>{...a.days};
  b.days.forEach((k, v) {
    final cur = days[k];
    if (cur == null || cur.updatedAt < v.updatedAt) {
      days[k] = v;
    }
  });
  final achievements = <String, int>{...a.achievements};
  b.achievements.forEach((k, v) {
    final cur = achievements[k];
    if (cur == null || cur > v) {
      achievements[k] = v;
    }
  });
  return AppData(settings: settings, days: days, achievements: achievements);
}

// ============ 全局状态 ============

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState i = AppState._();

  AppData data = AppData.empty();
  bool loaded = false;
  String syncStatus = '未同步';
  Timer? _syncTimer;

  Future<void> init() async {
    final local = await LocalStore.load();
    if (local != null) data = local;
    loaded = true;
    notifyListeners();
    if (data.settings.syncEnabled) {
      await Future.delayed(const Duration(milliseconds: 600));
      await syncNow();
    }
  }

  DayRecord today() {
    final key = todayKey();
    final rec = data.days[key];
    if (rec == null) {
      final d = DayRecord(goal: data.settings.dailyGoal, updatedAt: nowMs());
      data.days[key] = d;
      return d;
    }
    return rec;
  }

  void addWords(int n) {
    if (n <= 0) return;
    final t = today();
    t.words += n;
    t.goal = data.settings.dailyGoal;
    t.updatedAt = nowMs();
    afterChange();
  }

  void addSession(int minutes, int words) {
    final t = today();
    t.sessions.add(Session(start: nowMs(), minutes: minutes, words: words));
    t.words += words;
    t.goal = data.settings.dailyGoal;
    t.updatedAt = nowMs();
    afterChange();
  }

  void saveSettings(Settings s) {
    s.updatedAt = nowMs();
    data.settings = s;
    afterChange();
  }

  void afterChange() {
    checkAchievements();
    LocalStore.save(data);
    notifyListeners();
    if (data.settings.syncEnabled) {
      _syncTimer?.cancel();
      _syncTimer = Timer(const Duration(seconds: 4), () {
        syncNow();
      });
    }
  }

  void checkAchievements() {
    final now = nowMs();
    for (final def in kAchievements) {
      if (!data.achievements.containsKey(def.id) && def.condition(data)) {
        data.achievements[def.id] = now;
      }
    }
  }

  Future<void> syncNow() async {
    final s = data.settings;
    if (!s.syncEnabled) {
      syncStatus = '未开启同步';
      notifyListeners();
      return;
    }
    if (s.webdavUser.isEmpty || s.webdavPass.isEmpty) {
      syncStatus = '请先在设置里填写坚果云账号和应用密码';
      notifyListeners();
      return;
    }
    syncStatus = '同步中…';
    notifyListeners();
    var local = data;
    final remoteStr = await WebDav.download(s);
    if (remoteStr != null && remoteStr.isNotEmpty) {
      try {
        final remote =
            AppData.fromJson(jsonDecode(remoteStr) as Map<String, dynamic>);
        local = mergeData(local, remote);
      } catch (_) {}
    }
    data = local;
    await LocalStore.save(data);
    final ok = await WebDav.upload(s, jsonEncode(data.toJson()));
    syncStatus =
        ok ? '同步完成 ${_timeStr()}' : '同步失败，请检查账号密码或网络';
    notifyListeners();
  }

  String _timeStr() {
    final now = DateTime.now();
    return '${two(now.hour)}:${two(now.minute)}';
  }
}

// ============ 界面 ============

class WriterApp extends StatelessWidget {
  const WriterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '码字打卡',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    AppState.i.init();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.i,
      builder: (context, _) {
        if (!AppState.i.loaded) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final xp = totalWords(AppState.i.data);
        return Scaffold(
          appBar: AppBar(
            title: Text('码字打卡 · Lv.${levelFor(xp)} ${titleFor(levelFor(xp))}'),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings),
                tooltip: '设置',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsPage()),
                  );
                },
              ),
            ],
          ),
          body: IndexedStack(
            index: _tab,
            children: const [TodayPage(), StatsPage(), AchievementsPage()],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            destinations: const [
              NavigationDestination(
                  icon: Icon(Icons.edit_outlined),
                  selectedIcon: Icon(Icons.edit),
                  label: '今日'),
              NavigationDestination(
                  icon: Icon(Icons.bar_chart_outlined),
                  selectedIcon: Icon(Icons.bar_chart),
                  label: '统计'),
              NavigationDestination(
                  icon: Icon(Icons.emoji_events_outlined),
                  selectedIcon: Icon(Icons.emoji_events),
                  label: '成就'),
            ],
          ),
        );
      },
    );
  }
}

class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  final TextEditingController _wordsCtrl = TextEditingController();
  Timer? _tick;
  DateTime? _focusStart;

  @override
  void dispose() {
    _tick?.cancel();
    _wordsCtrl.dispose();
    super.dispose();
  }

  void _startFocus() {
    setState(() => _focusStart = DateTime.now());
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final dur = Duration(minutes: AppState.i.data.settings.focusMinutes);
      final start = _focusStart;
      if (start != null && DateTime.now().difference(start) >= dur) {
        _tick?.cancel();
        setState(() => _focusStart = null);
        _askWords(AppState.i.data.settings.focusMinutes);
      }
    });
  }

  void _endFocus() {
    if (_focusStart == null) return;
    final dur = Duration(minutes: AppState.i.data.settings.focusMinutes);
    final elapsed = DateTime.now().difference(_focusStart!);
    final minutes =
        (elapsed.inSeconds / 60).round().clamp(1, dur.inMinutes).toInt();
    _tick?.cancel();
    setState(() => _focusStart = null);
    _askWords(minutes);
  }

  Future<void> _askWords(int minutes) async {
    final ctrl = TextEditingController();
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('这次专注结束啦！'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('这次码了多少字？'),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '例如 1500',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('跳过'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(ctrl.text.trim()) ?? 0;
              Navigator.of(ctx).pop(n);
            },
            child: const Text('记下'),
          ),
        ],
      ),
    );
    if (result != null && result > 0) {
      AppState.i.addSession(minutes, result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已记录 $result 字，+$result 经验 🎉')),
        );
      }
    }
  }

  void _quickAdd(int n) {
    AppState.i.addWords(n);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('+$n 字，继续加油！')),
      );
    }
  }

  void _manualAdd() {
    final n = int.tryParse(_wordsCtrl.text.trim()) ?? 0;
    if (n <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先输入字数哦')),
      );
      return;
    }
    _quickAdd(n);
    _wordsCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final data = AppState.i.data;
    final day = AppState.i.today();
    final goal = data.settings.dailyGoal;
    final words = day.words;
    final progress = goal > 0 ? (words / goal).clamp(0.0, 1.0).toDouble() : 0.0;
    final streak = currentStreak(data);
    final total = totalWords(data);
    final isFocusing = _focusStart != null;
    final focusMinutes = data.settings.focusMinutes;

    Duration remaining = Duration.zero;
    if (isFocusing) {
      final diff = DateTime.now().difference(_focusStart!);
      final target = Duration(minutes: focusMinutes);
      remaining = diff >= target ? Duration.zero : target - diff;
    }
    final remainingText =
        '${two(remaining.inMinutes)}:${two(remaining.inSeconds % 60)}';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _infoChip(Icons.local_fire_department, '连续 $streak 天', Colors.deepOrange),
            const SizedBox(width: 8),
            _infoChip(Icons.edit_note, '累计 $total 字', Colors.blueGrey),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(todayKey(), style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SizedBox(
                  width: 160,
                  height: 160,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 160,
                        height: 160,
                        child: CircularProgressIndicator(
                          value: progress,
                          strokeWidth: 12,
                          backgroundColor: Colors.grey.shade200,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$words',
                              style: const TextStyle(
                                  fontSize: 32, fontWeight: FontWeight.bold)),
                          Text('/ $goal 字',
                              style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  words >= goal ? '今日目标达成！🎉' : '还差 ${goal - words} 字，稳住',
                  style: TextStyle(
                      color: words >= goal ? Colors.green : Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.timer_outlined, color: Colors.redAccent),
                    const SizedBox(width: 8),
                    Text('专注计时',
                        style: Theme.of(context).textTheme.titleMedium),
                    const Spacer(),
                    Text('$focusMinutes 分钟',
                        style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
                const SizedBox(height: 12),
                if (isFocusing)
                  Column(
                    children: [
                      Text(remainingText,
                          style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.redAccent)),
                      const SizedBox(height: 8),
                      Text('专心码字中，写完回这里点「结束」',
                          style: TextStyle(color: Colors.grey.shade600)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _endFocus,
                        icon: const Icon(Icons.stop),
                        label: const Text('结束专注并记录字数'),
                      ),
                    ],
                  )
                else
                  FilledButton.icon(
                    onPressed: _startFocus,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('开始专注（去作家助手码字）'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('记录字数', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _wordsCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '输入今天码的字数',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(onPressed: _manualAdd, child: const Text('记录')),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [500, 1000, 2000].map((n) {
                    return OutlinedButton(
                      onPressed: () => _quickAdd(n),
                      child: Text('+$n'),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _infoChip(IconData icon, String text, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppState.i.data;
    final total = totalWords(data);
    final streak = currentStreak(data);
    final bestStreakV = bestStreak(data);
    final bestDay = bestDayWords(data);
    final avg = avgWords(data);
    final sessions = totalSessions(data);
    final xp = total;
    final level = levelFor(xp);
    final curXp = xp - xpNeededForLevel(level);
    final nextXp = xpNeededForLevel(level + 1) - xpNeededForLevel(level);

    final week =
        List.generate(7, (i) => DateTime.now().subtract(Duration(days: 6 - i)));
    int maxW = 0;
    for (final d in week) {
      final w = data.days[keyFor(d)]?.words ?? 0;
      if (w > maxW) maxW = w;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('Lv.$level',
                        style: const TextStyle(
                            fontSize: 28, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text(titleFor(level),
                        style: TextStyle(color: Colors.grey.shade600)),
                  ],
                ),
                const SizedBox(height: 8),
                const Text('总经验（1 字 = 1 经验）'),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: nextXp > 0 ? (curXp / nextXp).clamp(0.0, 1.0).toDouble() : 0,
                    minHeight: 10,
                  ),
                ),
                const SizedBox(height: 4),
                Text('总经验 $xp · 距下一级还差 ${nextXp - curXp}',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.7,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            _statCard('累计字数', '$total'),
            _statCard('连续天数', '$streak'),
            _statCard('最长连续', '$bestStreakV'),
            _statCard('单日最高', '$bestDay'),
            _statCard('日均字数', avg.toStringAsFixed(0)),
            _statCard('专注次数', '$sessions'),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('近 7 天字数', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SizedBox(
                  height: 140,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: week.map((d) {
                      final words = data.days[keyFor(d)]?.words ?? 0;
                      final h = maxW > 0
                          ? (words / maxW * 100).clamp(4.0, 100.0).toDouble()
                          : 4.0;
                      final isToday = keyFor(d) == todayKey();
                      return Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text('$words', style: const TextStyle(fontSize: 11)),
                            const SizedBox(height: 4),
                            Container(
                              height: h,
                              decoration: BoxDecoration(
                                color: isToday
                                    ? Colors.deepOrange
                                    : Colors.deepOrange.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('${d.month}/${d.day}',
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statCard(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class AchievementsPage extends StatelessWidget {
  const AchievementsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = AppState.i.data;
    final unlocked = data.achievements.keys.toSet();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('已解锁 ${unlocked.length} / ${kAchievements.length}',
            style: TextStyle(color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        ...kAchievements.map((a) {
          final isUnlocked = unlocked.contains(a.id);
          return Card(
            child: ListTile(
              leading: Text(a.icon, style: const TextStyle(fontSize: 28)),
              title: Text(a.name,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isUnlocked ? Colors.black : Colors.grey)),
              subtitle: Text(a.desc),
              trailing: isUnlocked
                  ? const Icon(Icons.check_circle, color: Colors.green)
                  : const Icon(Icons.lock_outline, color: Colors.grey),
              enabled: isUnlocked,
            ),
          );
        }).toList(),
      ],
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _goalCtrl = TextEditingController();
  final _focusCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _syncEnabled = false;
  String _testResult = '';

  @override
  void initState() {
    super.initState();
    final s = AppState.i.data.settings;
    _goalCtrl.text = '${s.dailyGoal}';
    _focusCtrl.text = '${s.focusMinutes}';
    _urlCtrl.text = s.webdavUrl;
    _userCtrl.text = s.webdavUser;
    _passCtrl.text = s.webdavPass;
    _syncEnabled = s.syncEnabled;
  }

  @override
  void dispose() {
    _goalCtrl.dispose();
    _focusCtrl.dispose();
    _urlCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final s = Settings(
      dailyGoal: (int.tryParse(_goalCtrl.text.trim()) ?? 4000)
          .clamp(1, 100000)
          .toInt(),
      focusMinutes: (int.tryParse(_focusCtrl.text.trim()) ?? 25)
          .clamp(1, 240)
          .toInt(),
      webdavUrl: _urlCtrl.text.trim().isEmpty
          ? 'https://dav.jianguoyun.com/dav/'
          : _urlCtrl.text.trim(),
      webdavUser: _userCtrl.text.trim(),
      webdavPass: _passCtrl.text.trim(),
      syncEnabled: _syncEnabled,
      updatedAt: nowMs(),
    );
    AppState.i.saveSettings(s);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已保存 ✓')),
    );
  }

  Future<void> _test() async {
    final s = Settings(
      webdavUrl: _urlCtrl.text.trim().isEmpty
          ? 'https://dav.jianguoyun.com/dav/'
          : _urlCtrl.text.trim(),
      webdavUser: _userCtrl.text.trim(),
      webdavPass: _passCtrl.text.trim(),
      syncEnabled: true,
    );
    setState(() => _testResult = '测试中…');
    final r = await WebDav.test(s);
    if (mounted) setState(() => _testResult = r);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('写作目标', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _field(_goalCtrl, '每日目标字数（如 4000）', TextInputType.number),
          const SizedBox(height: 16),
          _field(_focusCtrl, '每次专注分钟数（如 25）', TextInputType.number),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('坚果云同步', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Switch(
                  value: _syncEnabled,
                  onChanged: (v) => setState(() => _syncEnabled = v)),
            ],
          ),
          const SizedBox(height: 8),
          _field(_urlCtrl, 'WebDAV 地址', TextInputType.url),
          const SizedBox(height: 12),
          _field(_userCtrl, '坚果云账号（邮箱）', TextInputType.emailAddress),
          const SizedBox(height: 12),
          _field(_passCtrl, '坚果云应用密码', TextInputType.visiblePassword,
              obscure: true),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(onPressed: _test, child: const Text('测试连接')),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_testResult,
                    style:
                        TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              _save();
              AppState.i.syncNow();
            },
            icon: const Icon(Icons.sync),
            label: const Text('立即同步'),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: AppState.i,
            builder: (context, _) => Text(
              '同步状态：${AppState.i.syncStatus}',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton(onPressed: _save, child: const Text('保存设置')),
          const SizedBox(height: 24),
          Text(
            '提示：\n'
            '1. 应用密码在坚果云网页「账户信息 → 安全选项 → 第三方应用管理 → 添加应用密码」里生成（不是登录密码）。\n'
            '2. 开启同步后，电脑和手机登录同一个坚果云账号，数据自动互通。\n'
            '3. 正稿请在「作家助手」里手打，本 app 只做打卡记录，不碰稿子。',
            style: TextStyle(
                color: Colors.grey.shade600, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String hint, TextInputType type,
      {bool obscure = false}) {
    return TextField(
      controller: ctrl,
      keyboardType: type,
      obscureText: obscure,
      decoration: InputDecoration(
        border: const OutlineInputBorder(),
        labelText: hint,
        isDense: true,
      ),
    );
  }
}
