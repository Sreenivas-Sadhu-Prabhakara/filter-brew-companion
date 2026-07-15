import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const BrewCompanionApp());
}

class BrewCompanionApp extends StatefulWidget {
  const BrewCompanionApp({super.key});

  @override
  State<BrewCompanionApp> createState() => _BrewCompanionAppState();
}

class _BrewCompanionAppState extends State<BrewCompanionApp> {
  ThemeMode _themeMode = ThemeMode.system;

  void _setThemeMode(ThemeMode value) {
    setState(() => _themeMode = value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Giri Brew Companion',
      themeMode: _themeMode,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: BrewHomePage(onThemeModeChanged: _setThemeMode),
    );
  }

  ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1E6E5A),
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.light
          ? const Color(0xFFF7F3EA)
          : null,
      sliderTheme: const SliderThemeData(
        showValueIndicator: ShowValueIndicator.onDrag,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class BrewHomePage extends StatefulWidget {
  const BrewHomePage({super.key, required this.onThemeModeChanged});

  final ValueChanged<ThemeMode> onThemeModeChanged;

  @override
  State<BrewHomePage> createState() => _BrewHomePageState();
}

class _BrewHomePageState extends State<BrewHomePage> {
  final BrewStore _store = BrewStore();
  final Stopwatch _stopwatch = Stopwatch();

  Timer? _ticker;
  BrewSettings _settings = BrewSettings.defaults();
  List<BrewLogEntry> _logs = [];
  int _tab = 0;
  int _methodIndex = 0;
  bool _solveWater = true;
  double _coffeeG = 18;
  double _waterG = 280;
  int _stageIndex = 0;
  int _elapsed = 0;
  bool _loaded = false;

  BrewMethod get _method => brewMethods[_methodIndex];

  double get _effectiveRatio => _method.ratio * _settings.strength;

  int get _targetWaterG =>
      _solveWater ? (_coffeeG * _effectiveRatio).round() : _waterG.round();

  double get _targetCoffeeG =>
      _solveWater ? _coffeeG : (_waterG / _effectiveRatio);

  int get _totalSeconds =>
      _method.stages.fold<int>(0, (sum, stage) => sum + stage.seconds);

  int get _stageElapsed {
    var before = 0;
    for (var i = 0; i < _stageIndex; i += 1) {
      before += _method.stages[i].seconds;
    }
    return math.max(0, _elapsed - before);
  }

  int get _stageRemaining =>
      math.max(0, _method.stages[_stageIndex].seconds - _stageElapsed);

  double get _progress => _totalSeconds == 0 ? 0 : _elapsed / _totalSeconds;

  int get _cups => math.max(1, (_targetWaterG / _settings.cupSizeMl).round());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _store.loadSettings();
    final logs = await _store.loadLogs();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _logs = logs;
      _methodIndex = brewMethods.indexWhere(
        (m) => m.id == settings.defaultMethod,
      );
      if (_methodIndex < 0) _methodIndex = 0;
      _loaded = true;
    });
    widget.onThemeModeChanged(settings.themeMode);
  }

  Future<void> _saveSettings(BrewSettings settings) async {
    await _store.saveSettings(settings);
    if (!mounted) return;
    setState(() => _settings = settings);
    widget.onThemeModeChanged(settings.themeMode);
  }

  Future<void> _saveLogs(List<BrewLogEntry> logs) async {
    await _store.saveLogs(logs);
    if (!mounted) return;
    setState(() => _logs = logs);
  }

  void _setMethod(int index) {
    _resetTimer();
    setState(() {
      _methodIndex = index;
      if (_solveWater) {
        _waterG = _coffeeG * _effectiveRatio;
      } else {
        _coffeeG = _waterG / _effectiveRatio;
      }
    });
  }

  void _toggleTimer() {
    if (_stopwatch.isRunning) {
      _stopwatch.stop();
      _ticker?.cancel();
      setState(() {});
      return;
    }

    _stopwatch.start();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final nextElapsed = math.min(_stopwatch.elapsed.inSeconds, _totalSeconds);
      final nextStage = _stageForElapsed(nextElapsed);
      if (nextStage != _stageIndex) {
        HapticFeedback.mediumImpact();
      }
      setState(() {
        _elapsed = nextElapsed;
        _stageIndex = nextStage;
      });
      if (_elapsed >= _totalSeconds) {
        HapticFeedback.heavyImpact();
        _stopwatch.stop();
        _ticker?.cancel();
      }
    });
    setState(() {});
  }

  void _skipStage() {
    final next = math.min(_stageIndex + 1, _method.stages.length - 1);
    final elapsed = _elapsedAtStage(next);
    _stopwatch
      ..reset()
      ..start();
    HapticFeedback.selectionClick();
    setState(() {
      _stageIndex = next;
      _elapsed = elapsed;
    });
  }

  void _resetTimer() {
    _ticker?.cancel();
    _stopwatch
      ..stop()
      ..reset();
    setState(() {
      _elapsed = 0;
      _stageIndex = 0;
    });
  }

  int _stageForElapsed(int elapsed) {
    var cursor = 0;
    for (var i = 0; i < _method.stages.length; i += 1) {
      cursor += _method.stages[i].seconds;
      if (elapsed < cursor) return i;
    }
    return _method.stages.length - 1;
  }

  int _elapsedAtStage(int index) {
    var elapsed = 0;
    for (var i = 0; i < index; i += 1) {
      elapsed += _method.stages[i].seconds;
    }
    return elapsed;
  }

  Future<void> _openLogSheet({BrewLogEntry? existing}) async {
    final saved = await showModalBottomSheet<BrewLogEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => BrewLogSheet(
        method: _method,
        doseG: _targetCoffeeG,
        yieldG: _targetWaterG.toDouble(),
        existing: existing,
      ),
    );
    if (saved == null) return;

    final next = [..._logs];
    final index = next.indexWhere((entry) => entry.id == saved.id);
    if (index >= 0) {
      next[index] = saved;
    } else {
      next.insert(0, saved);
    }
    await _saveLogs(next);
  }

  Future<void> _deleteLog(BrewLogEntry entry) async {
    await _saveLogs(_logs.where((log) => log.id != entry.id).toList());
  }

  Future<void> _clearData() async {
    await _saveLogs([]);
    await _saveSettings(BrewSettings.defaults());
    if (!mounted) return;
    setState(() {
      _methodIndex = 0;
      _coffeeG = 18;
      _waterG = 280;
      _solveWater = true;
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Giri Brew Companion'),
        actions: [
          IconButton(
            tooltip: 'Reset timer',
            onPressed: _resetTimer,
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _buildBrewTab(),
          BrewLogTab(
            logs: _logs,
            onEdit: (entry) => _openLogSheet(existing: entry),
            onDelete: _deleteLog,
          ),
          SettingsTab(
            settings: _settings,
            onChanged: _saveSettings,
            onClearData: _clearData,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.coffee), label: 'Brew'),
          NavigationDestination(icon: Icon(Icons.history), label: 'Log'),
          NavigationDestination(icon: Icon(Icons.tune), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildBrewTab() {
    final stage = _method.stages[_stageIndex];
    final nextStage = _stageIndex + 1 < _method.stages.length
        ? _method.stages[_stageIndex + 1]
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        HeroBrewCard(
          method: _method,
          stage: stage,
          nextStage: nextStage,
          elapsed: _elapsed,
          totalSeconds: _totalSeconds,
          stageRemaining: _stageRemaining,
          progress: _progress,
          running: _stopwatch.isRunning,
          onToggle: _toggleTimer,
          onSkip: _skipStage,
          onReset: _resetTimer,
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Ratio calculator',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<int>(
                segments: [
                  for (var i = 0; i < brewMethods.length; i += 1)
                    ButtonSegment<int>(
                      value: i,
                      label: Text(brewMethods[i].name),
                      icon: const Icon(Icons.coffee_maker),
                    ),
                ],
                selected: {_methodIndex},
                onSelectionChanged: (value) => _setMethod(value.first),
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    label: Text('Dose to water'),
                    icon: Icon(Icons.scale),
                  ),
                  ButtonSegment(
                    value: false,
                    label: Text('Water to dose'),
                    icon: Icon(Icons.opacity),
                  ),
                ],
                selected: {_solveWater},
                onSelectionChanged: (value) {
                  setState(() => _solveWater = value.first);
                },
              ),
              const SizedBox(height: 14),
              if (_solveWater)
                SliderLine(
                  icon: Icons.scale,
                  label: 'Coffee dose',
                  valueLabel: '${_coffeeG.toStringAsFixed(0)} g',
                  child: Slider(
                    min: 10,
                    max: 40,
                    divisions: 30,
                    value: _coffeeG,
                    label: '${_coffeeG.round()} g',
                    onChanged: (value) => setState(() => _coffeeG = value),
                  ),
                )
              else
                SliderLine(
                  icon: Icons.opacity,
                  label: 'Water target',
                  valueLabel: '${_waterG.toStringAsFixed(0)} g',
                  child: Slider(
                    min: 120,
                    max: 650,
                    divisions: 53,
                    value: _waterG,
                    label: '${_waterG.round()} g',
                    onChanged: (value) => setState(() => _waterG = value),
                  ),
                ),
              SliderLine(
                icon: Icons.local_fire_department,
                label: 'Strength trim',
                valueLabel: '${(_settings.strength * 100).round()}%',
                child: Slider(
                  min: .85,
                  max: 1.2,
                  divisions: 7,
                  value: _settings.strength,
                  label: '${(_settings.strength * 100).round()}%',
                  onChanged: (value) {
                    _saveSettings(_settings.copyWith(strength: value));
                  },
                ),
              ),
              const SizedBox(height: 8),
              MetricGrid(
                metrics: [
                  BrewMetric(
                    'Coffee',
                    '${_targetCoffeeG.toStringAsFixed(1)} g',
                    Icons.scale,
                  ),
                  BrewMetric('Water', '$_targetWaterG g', Icons.opacity),
                  BrewMetric(
                    'Ratio',
                    '1:${_effectiveRatio.toStringAsFixed(1)}',
                    Icons.percent,
                  ),
                  BrewMetric(
                    'Cups',
                    '$_cups x ${_settings.cupSizeMl} ml',
                    Icons.local_cafe,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Recipe stages',
          child: Column(
            children: [
              for (var i = 0; i < _method.stages.length; i += 1)
                StageTile(
                  stage: _method.stages[i],
                  active: i == _stageIndex && _elapsed < _totalSeconds,
                  completed: i < _stageIndex || _elapsed >= _totalSeconds,
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _openLogSheet(),
          icon: const Icon(Icons.add),
          label: const Text('Log this brew'),
        ),
      ],
    );
  }
}

class HeroBrewCard extends StatelessWidget {
  const HeroBrewCard({
    super.key,
    required this.method,
    required this.stage,
    required this.nextStage,
    required this.elapsed,
    required this.totalSeconds,
    required this.stageRemaining,
    required this.progress,
    required this.running,
    required this.onToggle,
    required this.onSkip,
    required this.onReset,
  });

  final BrewMethod method;
  final BrewStage stage;
  final BrewStage? nextStage;
  final int elapsed;
  final int totalSeconds;
  final int stageRemaining;
  final double progress;
  final bool running;
  final VoidCallback onToggle;
  final VoidCallback onSkip;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF163D34),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      method.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${method.grind} grind | ${method.tempC} deg C',
                      style: const TextStyle(
                        color: Color(0xFFBFD8CC),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              TimerBadge(elapsed: elapsed, total: totalSeconds),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 12,
              value: progress.clamp(0, 1),
              backgroundColor: const Color(0xFF2B5B50),
              valueColor: AlwaysStoppedAnimation<Color>(scheme.tertiary),
            ),
          ),
          const SizedBox(height: 16),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x26FFFFFF)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.timer, color: Color(0xFFFFD89B)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${stage.label} | ${fmt(stageRemaining)} left',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${stage.hint}${nextStage == null ? '' : ' Next: ${nextStage!.label}.'}',
                          style: const TextStyle(
                            color: Color(0xFFE7F1EC),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onToggle,
                  icon: Icon(running ? Icons.pause : Icons.play_arrow),
                  label: Text(running ? 'Pause' : 'Start'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Skip stage',
                onPressed: onSkip,
                icon: const Icon(Icons.skip_next),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Reset',
                onPressed: onReset,
                icon: const Icon(Icons.replay),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class BrewLogTab extends StatelessWidget {
  const BrewLogTab({
    super.key,
    required this.logs,
    required this.onEdit,
    required this.onDelete,
  });

  final List<BrewLogEntry> logs;
  final ValueChanged<BrewLogEntry> onEdit;
  final ValueChanged<BrewLogEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    final average = logs.isEmpty
        ? 0.0
        : logs.fold<double>(0, (sum, log) => sum + log.rating) / logs.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        MetricGrid(
          metrics: [
            BrewMetric('Brews', '${logs.length}', Icons.coffee),
            BrewMetric('Avg rating', average.toStringAsFixed(1), Icons.star),
          ],
        ),
        const SizedBox(height: 16),
        if (logs.isEmpty)
          const EmptyState()
        else
          for (final log in logs)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  title: Text(
                    log.bean.isEmpty ? log.methodName : log.bean,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    '${log.methodName} | ${log.doseG.toStringAsFixed(1)} g to ${log.yieldG.toStringAsFixed(0)} g | 1:${log.ratio.toStringAsFixed(1)}\n${log.tags.join(', ')}',
                  ),
                  isThreeLine: true,
                  leading: CircleAvatar(
                    child: Text(log.rating.toStringAsFixed(0)),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') onEdit(log);
                      if (value == 'delete') onDelete(log);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                  onTap: () => onEdit(log),
                ),
              ),
            ),
      ],
    );
  }
}

class SettingsTab extends StatelessWidget {
  const SettingsTab({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onClearData,
  });

  final BrewSettings settings;
  final ValueChanged<BrewSettings> onChanged;
  final Future<void> Function() onClearData;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        SectionCard(
          title: 'Defaults',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: [
                  for (final method in brewMethods)
                    ButtonSegment(
                      value: method.id,
                      label: Text(method.name),
                      icon: const Icon(Icons.coffee_maker),
                    ),
                ],
                selected: {settings.defaultMethod},
                onSelectionChanged: (value) {
                  onChanged(settings.copyWith(defaultMethod: value.first));
                },
              ),
              const SizedBox(height: 14),
              SliderLine(
                icon: Icons.local_fire_department,
                label: 'Default strength',
                valueLabel: '${(settings.strength * 100).round()}%',
                child: Slider(
                  min: .85,
                  max: 1.2,
                  divisions: 7,
                  value: settings.strength,
                  label: '${(settings.strength * 100).round()}%',
                  onChanged: (value) {
                    onChanged(settings.copyWith(strength: value));
                  },
                ),
              ),
              SliderLine(
                icon: Icons.local_cafe,
                label: 'Cup size',
                valueLabel: '${settings.cupSizeMl} ml',
                child: Slider(
                  min: 80,
                  max: 240,
                  divisions: 16,
                  value: settings.cupSizeMl.toDouble(),
                  label: '${settings.cupSizeMl} ml',
                  onChanged: (value) {
                    onChanged(settings.copyWith(cupSizeMl: value.round()));
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Theme',
          child: SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text('System'),
                icon: Icon(Icons.brightness_auto),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text('Light'),
                icon: Icon(Icons.light_mode),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text('Dark'),
                icon: Icon(Icons.dark_mode),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (value) {
              onChanged(settings.copyWith(themeMode: value.first));
            },
          ),
        ),
        const SizedBox(height: 16),
        SectionCard(
          title: 'Privacy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Brew logs and settings are stored on this device only. The app has no account, analytics SDK, backend, or network permission.',
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Clear all data?'),
                      content: const Text(
                        'This removes local brew logs and resets defaults.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Clear'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) await onClearData();
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Clear all data'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class BrewLogSheet extends StatefulWidget {
  const BrewLogSheet({
    super.key,
    required this.method,
    required this.doseG,
    required this.yieldG,
    this.existing,
  });

  final BrewMethod method;
  final double doseG;
  final double yieldG;
  final BrewLogEntry? existing;

  @override
  State<BrewLogSheet> createState() => _BrewLogSheetState();
}

class _BrewLogSheetState extends State<BrewLogSheet> {
  late final TextEditingController _bean;
  late final TextEditingController _grind;
  late final TextEditingController _notes;
  late String _roast;
  late double _rating;
  late Set<String> _tags;

  static const _tagOptions = [
    'Sweet',
    'Clean',
    'Chocolate',
    'Citrus',
    'Nutty',
    'Bitter',
    'Sour',
  ];

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _bean = TextEditingController(text: existing?.bean ?? '');
    _grind = TextEditingController(
      text: existing?.grind ?? widget.method.grind,
    );
    _notes = TextEditingController(text: existing?.notes ?? '');
    _roast = existing?.roast ?? 'Medium';
    _rating = existing?.rating ?? 4;
    _tags = {...?existing?.tags};
  }

  @override
  void dispose() {
    _bean.dispose();
    _grind.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottom + 16),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(
            widget.existing == null ? 'Log brew' : 'Edit brew',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _bean,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Bean or blend',
              prefixIcon: Icon(Icons.coffee),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _roast,
            decoration: const InputDecoration(
              labelText: 'Roast',
              prefixIcon: Icon(Icons.local_fire_department),
            ),
            items: const [
              DropdownMenuItem(value: 'Light', child: Text('Light')),
              DropdownMenuItem(value: 'Medium', child: Text('Medium')),
              DropdownMenuItem(value: 'Dark', child: Text('Dark')),
            ],
            onChanged: (value) => setState(() => _roast = value ?? _roast),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _grind,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Grind',
              prefixIcon: Icon(Icons.grain),
            ),
          ),
          const SizedBox(height: 12),
          SliderLine(
            icon: Icons.star,
            label: 'Rating',
            valueLabel: _rating.toStringAsFixed(1),
            child: Slider(
              min: 0,
              max: 5,
              divisions: 10,
              value: _rating,
              label: _rating.toStringAsFixed(1),
              onChanged: (value) => setState(() => _rating = value),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in _tagOptions)
                FilterChip(
                  label: Text(tag),
                  selected: _tags.contains(tag),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _tags.add(tag);
                      } else {
                        _tags.remove(tag);
                      }
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notes',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: () {
              final existing = widget.existing;
              Navigator.pop(
                context,
                BrewLogEntry(
                  id:
                      existing?.id ??
                      DateTime.now().microsecondsSinceEpoch.toString(),
                  brewedAt: existing?.brewedAt ?? DateTime.now(),
                  methodName: existing?.methodName ?? widget.method.name,
                  bean: _bean.text.trim(),
                  roast: _roast,
                  grind: _grind.text.trim(),
                  doseG: existing?.doseG ?? widget.doseG,
                  yieldG: existing?.yieldG ?? widget.yieldG,
                  rating: _rating,
                  tags: _tags.toList()..sort(),
                  notes: _notes.text.trim(),
                ),
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('Save brew'),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class SliderLine extends StatelessWidget {
  const SliderLine({
    super.key,
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.child,
  });

  final IconData icon;
  final String label;
  final String valueLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              valueLabel,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
        child,
      ],
    );
  }
}

class MetricGrid extends StatelessWidget {
  const MetricGrid({super.key, required this.metrics});

  final List<BrewMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.65,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(metric.icon, color: Theme.of(context).colorScheme.primary),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      metric.label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class StageTile extends StatelessWidget {
  const StageTile({
    super.key,
    required this.stage,
    required this.active,
    required this.completed,
  });

  final BrewStage stage;
  final bool active;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              fmt(stage.seconds),
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stage.label,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  stage.hint,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(
            completed ? Icons.check_circle : Icons.radio_button_unchecked,
            color: completed ? scheme.primary : scheme.outline,
          ),
        ],
      ),
    );
  }
}

class TimerBadge extends StatelessWidget {
  const TimerBadge({super.key, required this.elapsed, required this.total});

  final int elapsed;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 86,
      height: 86,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFF4C981),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            fmt(elapsed),
            style: const TextStyle(
              color: Color(0xFF163D34),
              fontSize: 23,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            'of ${fmt(total)}',
            style: const TextStyle(
              color: Color(0xB3163D34),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'No brews yet',
      child: Row(
        children: [
          Icon(Icons.local_cafe, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Log a brew from the Brew tab to build your tasting history.',
            ),
          ),
        ],
      ),
    );
  }
}

class BrewMetric {
  const BrewMetric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class BrewMethod {
  const BrewMethod({
    required this.id,
    required this.name,
    required this.ratio,
    required this.grind,
    required this.tempC,
    required this.stages,
  });

  final String id;
  final String name;
  final double ratio;
  final String grind;
  final int tempC;
  final List<BrewStage> stages;
}

class BrewStage {
  const BrewStage(this.label, this.seconds, this.hint);

  final String label;
  final int seconds;
  final String hint;
}

const brewMethods = [
  BrewMethod(
    id: 'v60',
    name: 'V60',
    ratio: 15.5,
    grind: 'Medium fine',
    tempC: 92,
    stages: [
      BrewStage('Bloom', 40, 'Wet every dry patch and swirl once.'),
      BrewStage('First pour', 45, 'Spiral to the middle of the bed.'),
      BrewStage('Second pour', 45, 'Raise the slurry with a center pour.'),
      BrewStage('Drawdown', 80, 'Let it drain cleanly without stirring.'),
    ],
  ),
  BrewMethod(
    id: 'kalita',
    name: 'Kalita',
    ratio: 16,
    grind: 'Medium',
    tempC: 91,
    stages: [
      BrewStage('Bloom', 35, 'Saturate the flat bed evenly.'),
      BrewStage('Pulse one', 40, 'Pour in small circles.'),
      BrewStage('Pulse two', 40, 'Keep the bed level.'),
      BrewStage('Drawdown', 80, 'Wait for a slow, even finish.'),
    ],
  ),
  BrewMethod(
    id: 'south-filter',
    name: 'South Filter',
    ratio: 8,
    grind: 'Fine',
    tempC: 94,
    stages: [
      BrewStage('Load', 90, 'Add first water and let the bed swell.'),
      BrewStage('Top up', 150, 'Top up without disturbing the puck.'),
      BrewStage('Drip', 240, 'Cover and let the decoction collect.'),
    ],
  ),
];

class BrewSettings {
  const BrewSettings({
    required this.defaultMethod,
    required this.strength,
    required this.cupSizeMl,
    required this.themeMode,
  });

  factory BrewSettings.defaults() => const BrewSettings(
    defaultMethod: 'v60',
    strength: 1,
    cupSizeMl: 160,
    themeMode: ThemeMode.system,
  );

  factory BrewSettings.fromJson(Map<String, dynamic> json) {
    return BrewSettings(
      defaultMethod: json['defaultMethod'] as String? ?? 'v60',
      strength: (json['strength'] as num?)?.toDouble() ?? 1,
      cupSizeMl: (json['cupSizeMl'] as num?)?.round() ?? 160,
      themeMode: switch (json['themeMode'] as String?) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
    );
  }

  final String defaultMethod;
  final double strength;
  final int cupSizeMl;
  final ThemeMode themeMode;

  BrewSettings copyWith({
    String? defaultMethod,
    double? strength,
    int? cupSizeMl,
    ThemeMode? themeMode,
  }) {
    return BrewSettings(
      defaultMethod: defaultMethod ?? this.defaultMethod,
      strength: strength ?? this.strength,
      cupSizeMl: cupSizeMl ?? this.cupSizeMl,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  Map<String, dynamic> toJson() => {
    'defaultMethod': defaultMethod,
    'strength': strength,
    'cupSizeMl': cupSizeMl,
    'themeMode': themeMode.name,
  };
}

class BrewLogEntry {
  const BrewLogEntry({
    required this.id,
    required this.brewedAt,
    required this.methodName,
    required this.bean,
    required this.roast,
    required this.grind,
    required this.doseG,
    required this.yieldG,
    required this.rating,
    required this.tags,
    required this.notes,
  });

  factory BrewLogEntry.fromJson(Map<String, dynamic> json) {
    return BrewLogEntry(
      id: json['id'] as String,
      brewedAt: DateTime.parse(json['brewedAt'] as String),
      methodName: json['methodName'] as String,
      bean: json['bean'] as String? ?? '',
      roast: json['roast'] as String? ?? 'Medium',
      grind: json['grind'] as String? ?? '',
      doseG: (json['doseG'] as num).toDouble(),
      yieldG: (json['yieldG'] as num).toDouble(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
      notes: json['notes'] as String? ?? '',
    );
  }

  final String id;
  final DateTime brewedAt;
  final String methodName;
  final String bean;
  final String roast;
  final String grind;
  final double doseG;
  final double yieldG;
  final double rating;
  final List<String> tags;
  final String notes;

  double get ratio => yieldG / doseG;

  Map<String, dynamic> toJson() => {
    'id': id,
    'brewedAt': brewedAt.toIso8601String(),
    'methodName': methodName,
    'bean': bean,
    'roast': roast,
    'grind': grind,
    'doseG': doseG,
    'yieldG': yieldG,
    'rating': rating,
    'tags': tags,
    'notes': notes,
  };
}

class BrewStore {
  static const _settingsKey = 'settings.v1';
  static const _logsKey = 'logs.v1';

  Future<BrewSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_settingsKey);
    if (raw == null) return BrewSettings.defaults();
    return BrewSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveSettings(BrewSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_settingsKey, jsonEncode(settings.toJson()));
  }

  Future<List<BrewLogEntry>> loadLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_logsKey) ?? [];
    return raw
        .map(
          (entry) =>
              BrewLogEntry.fromJson(jsonDecode(entry) as Map<String, dynamic>),
        )
        .toList()
      ..sort((a, b) => b.brewedAt.compareTo(a.brewedAt));
  }

  Future<void> saveLogs(List<BrewLogEntry> logs) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _logsKey,
      logs.map((entry) => jsonEncode(entry.toJson())).toList(),
    );
  }
}

String fmt(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}
