import 'dart:async';

import 'package:flutter/foundation.dart';

import 'core.dart';
import 'native_bridge.dart';

const providerNames = <String, String>{
  'anthropic': 'Claude',
  'openai-codex': 'Codex',
  'google-antigravity': 'Antigravity',
  'xai-oauth': 'Grok',
  'cursor': 'Cursor',
};

String providerName(String id) => providerNames[id] ?? id;

String ageText(DateTime? timestamp, DateTime now) {
  if (timestamp == null) return '更新時間未知';
  final age = now.difference(timestamp);
  if (age.isNegative) return '來源時間在未來';
  if (age.inMinutes == 0) return '不到 1 分鐘前';
  if (age.inHours == 0) return '${age.inMinutes} 分鐘前';
  if (age.inDays == 0) return '${age.inHours} 小時前';
  return '${age.inDays} 天前';
}

class UsageController extends ChangeNotifier {
  UsageController({AppStorage? storage, DesktopBridge? desktop})
    : storage = storage ?? AppStorage(),
      desktop = desktop ?? DesktopBridge() {
    this.desktop.onEvent = _onDesktopEvent;
  }

  final AppStorage storage;
  final DesktopBridge desktop;
  Preferences preferences = Preferences();
  UsageSnapshot? snapshot;
  bool initialized = false;
  bool loading = false;
  String? error;
  String? storageError;
  DateTime now = DateTime.now();
  DateTime? lastRequest;
  DateTime? nextRefresh;
  bool preferencesWritable = true;
  final Map<String, UsageSnapshot> _cache = {};
  final Map<String, UsageAccount> _lastKnownAccounts = {};
  AgentAdapter? _adapter;
  Timer? _pollTimer;
  Timer? _clockTimer;
  Future<void>? _inFlight;
  int _generation = 0;
  bool _disposed = false;

  List<String> get agentIds => const ['omp'];
  String get profile => _adapter?.profile ?? 'default';
  String? get executablePath =>
      _adapter is OmpAdapter ? (_adapter as OmpAdapter).executablePath : null;

  Future<void> initialize({bool open = false}) async {
    try {
      preferences = await storage.loadPreferences();
    } catch (_) {
      preferencesWritable = false;
      storageError = '無法讀取顯示設定。原檔案未覆寫；請修復檔案或明確重設設定。';
    }
    if (!agentIds.contains(preferences.selectedAgent)) {
      storageError = '此版本僅支援 OMP；儲存的 agent 目前不可用，未自動切換。';
      initialized = true;
      _changed();
      await desktop.ready(open: true);
      return;
    }
    _createAdapter();
    try {
      snapshot = await storage.loadSnapshot(preferences.selectedAgent);
      if (snapshot != null) _remember(snapshot!);
    } catch (_) {
      storageError = '無法讀取用量快取，將重新向 OMP 查詢；原始來源時間不會重設。';
    }
    initialized = true;
    _changed();
    await _publishMenu();
    await desktop.ready(open: open || preferences.pins.isEmpty);
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      now = DateTime.now();
      _changed();
      unawaited(_publishMenu());
    });
    unawaited(refresh());
  }

  void _createAdapter() {
    _adapter = OmpAdapter(
      executable: preferences.ompPath.trim().isEmpty
          ? null
          : preferences.ompPath.trim(),
    );
  }

  Future<void> _onDesktopEvent(String event) async {
    if (_disposed) return;
    if (event == 'desktop.terminating') {
      _generation++;
      _adapter?.cancel();
      _pollTimer?.cancel();
      _clockTimer?.cancel();
      final pending = _inFlight;
      if (pending != null) {
        await pending.timeout(const Duration(seconds: 1), onTimeout: () {});
      }
      dispose();
      return;
    }
    now = DateTime.now();
    if (event == 'desktop.wake' || event == 'desktop.refresh') {
      await refresh();
    }
    _changed();
  }

  void _remember(UsageSnapshot value) {
    _cache[preferences.selectedAgent] = value;
    for (final account in value.accounts) {
      _lastKnownAccounts[account.key] = account;
    }
  }

  Future<void> refresh() {
    if (_inFlight != null) return _inFlight!;
    if (_adapter == null || _disposed) return Future.value();
    final generation = _generation;
    final adapter = _adapter!;
    _pollTimer?.cancel();
    loading = true;
    lastRequest = DateTime.now();
    error = null;
    _changed();
    final work = _fetch(adapter, generation);
    _inFlight = work;
    return work;
  }

  Future<void> _fetch(AgentAdapter adapter, int generation) async {
    try {
      final value = await adapter.fetch();
      if (_disposed || generation != _generation) return;
      snapshot = value;
      now = DateTime.now();
      _remember(value);
      try {
        await storage.saveSnapshot(preferences.selectedAgent, value);
      } catch (_) {
        storageError = '最新用量已讀取，但無法儲存本機快取。';
      }
    } catch (failure) {
      if (_disposed || generation != _generation) return;
      error = _safeMessage(failure);
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _inFlight = null;
        nextRefresh = DateTime.now().add(const Duration(minutes: 5));
        _pollTimer = Timer(const Duration(minutes: 5), () {
          unawaited(refresh());
        });
        _changed();
        await _publishMenu();
      }
    }
  }

  String _safeMessage(Object failure) {
    final message = failure.toString();
    if (message.startsWith('Exception: ')) return message.substring(11);
    if (message.startsWith('FormatException: ')) return message.substring(17);
    return 'OMP 查詢失敗。請確認 CLI 路徑、網路與 OMP 內的登入狀態。';
  }

  Future<bool> applyPreferences(
    Preferences next, {
    bool resetUnreadable = false,
  }) async {
    if (!preferencesWritable && !resetUnreadable) {
      storageError = '原設定無法讀取，請先明確重設；未覆寫原檔案。';
      _changed();
      return false;
    }
    if (!agentIds.contains(next.selectedAgent)) {
      error = '此版本僅支援 OMP。';
      _changed();
      return false;
    }
    try {
      if (resetUnreadable) {
        await storage.resetPreferences(next);
      } else {
        await storage.savePreferences(next);
      }
    } catch (_) {
      storageError = '顯示設定儲存失敗，變更未套用。請確認 Application Support 的權限。';
      _changed();
      return false;
    }
    final sourceChanged =
        next.selectedAgent != preferences.selectedAgent ||
        next.ompPath != preferences.ompPath;
    preferences = next;
    preferencesWritable = true;
    storageError = null;
    if (sourceChanged) {
      _generation++;
      _adapter?.cancel();
      _pollTimer?.cancel();
      _inFlight = null;
      loading = false;
      snapshot = _cache[next.selectedAgent];
      error = null;
      _createAdapter();
    }
    _changed();
    await _publishMenu();
    if (sourceChanged) unawaited(refresh());
    return true;
  }

  Future<bool> resetUnreadablePreferences() =>
      applyPreferences(Preferences(), resetUnreadable: true);

  UsageAccount? findAccount(String key) {
    for (final account in snapshot?.accounts ?? const <UsageAccount>[]) {
      if (account.key == key) return account;
    }
    return null;
  }

  String accountLabel(UsageAccount account, {Preferences? settings}) {
    final prefs = settings ?? preferences;
    final alias = prefs.accountPreferences[account.key]?.alias.trim() ?? '';
    final email = account.email;
    if (email != null && email.isNotEmpty) {
      return alias.isEmpty ? email : '$alias · $email';
    }
    if (alias.isNotEmpty) return alias;
    if (account.accountId?.isNotEmpty ?? false) return account.accountId!;
    return account.identityKnown ? '已登入帳號' : '無法辨識的帳號';
  }

  bool _observationStale(DateTime? fetchedAt) =>
      fetchedAt == null ||
      now.difference(fetchedAt).inMinutes >= 10 ||
      now.isBefore(fetchedAt);

  bool accountStale(UsageAccount account) =>
      _observationStale(account.fetchedAt);

  String limitStatus(UsageAccount account, UsageLimit? limit) {
    if (account.disabled || account.issue != null || error != null) {
      return 'error';
    }
    if (limit == null) return 'missing';
    if (_observationStale(limit.fetchedAt ?? account.fetchedAt) ||
        limit.resetState(now) == ResetState.due) {
      return 'stale';
    }
    return limit.status == 'ok' ? 'ok' : 'error';
  }

  List<UsageAccount> orderedAccounts({Preferences? settings}) {
    final prefs = settings ?? preferences;
    final accounts = List<UsageAccount>.of(snapshot?.accounts ?? const []);
    final order = {
      for (var i = 0; i < prefs.accountOrder.length; i++)
        prefs.accountOrder[i]: i,
    };
    final sourceOrder = {
      for (var i = 0; i < accounts.length; i++) accounts[i].key: i,
    };
    accounts.sort((a, b) {
      final aIndex = order[a.key];
      final bIndex = order[b.key];
      if (aIndex != null || bIndex != null) {
        return (aIndex ?? 1 << 30).compareTo(bIndex ?? 1 << 30);
      }
      return sourceOrder[a.key]!.compareTo(sourceOrder[b.key]!);
    });
    return accounts;
  }

  Map<String, Object?> pinView(PinPreference pin, {Preferences? settings}) {
    final prefs = settings ?? preferences;
    final account = findAccount(pin.accountKey);
    final known = account ?? _lastKnownAccounts[pin.accountKey];
    final title = known == null
        ? '目前找不到帳號'
        : accountLabel(known, settings: prefs);
    final layers = <Map<String, Object?>>[];
    final tooltip = <String>[
      title,
      if (known != null) providerName(known.provider),
    ];
    UsageLimit? findLimit(PinMetric? metric) {
      if (metric == null) return null;
      for (final limit in account?.limits ?? const <UsageLimit>[]) {
        if (limit.id == metric.limitId) return limit;
      }
      return null;
    }

    String channelStatus(UsageLimit? limit, bool hasValue) {
      if (account == null) return 'missing';
      final status = limitStatus(account, limit);
      return status == 'ok' && !hasValue ? 'missing' : status;
    }

    void describe(
      String row,
      String channel,
      PinMetric metric,
      UsageLimit? limit,
      String value,
      String status,
    ) {
      final mode = switch (metric.mode) {
        LayerMode.remaining => '剩餘配額',
        LayerMode.used => '已用配額',
        LayerMode.reset => '重置倒數',
      };
      tooltip.add(
        '$row · $channel · ${limit?.label ?? '原窗口不可用'} · $mode：'
        '$value${status == 'ok' ? '' : ' · $status'}'
        ' · ${ageText(limit?.fetchedAt ?? account?.fetchedAt, now)}',
      );
    }

    final rows = [pin.top, pin.bottom];
    for (var index = 0; index < rows.length; index++) {
      final layer = rows[index];
      if (layer == null || layer.isEmpty) continue;
      final row = index == 0 ? '上層' : '下層';
      String? text;
      double? fraction;
      var status = 'ok';
      final textMetric = layer.text;
      if (textMetric != null) {
        final limit = findLimit(textMetric);
        text =
            limit?.valueText(textMetric.mode, now, raw: prefs.rawValues) ??
            '無資料';
        status = channelStatus(
          limit,
          textMetric.mode == LayerMode.reset
              ? limit?.resetsAt != null
              : text != '無資料',
        );
        describe(row, '文字', textMetric, limit, text, status);
      }
      final barMetric = layer.bar;
      if (barMetric != null) {
        final limit = findLimit(barMetric);
        fraction = limit?.barFraction(barMetric.mode, now);
        final barStatus = channelStatus(limit, fraction != null);
        // One healthy channel must not conceal another channel's missing data.
        if (barStatus != 'ok') {
          if (barStatus == 'error' ||
              status == 'ok' ||
              (barStatus == 'stale' && status == 'missing')) {
            status = barStatus;
          }
        }
        final value = fraction == null
            ? barMetric.mode == LayerMode.reset
                  ? '未知比例（缺少重置時間或窗口長度）'
                  : '無可用配額比例'
            : '${(fraction.clamp(0, 1) * 100).toStringAsFixed(1)}%'
                  ' · ${limit!.valueText(barMetric.mode, now, raw: prefs.rawValues)}';
        describe(row, '條狀', barMetric, limit, value, barStatus);
      }
      layers.add({
        'text': text,
        'showBar': barMetric != null,
        'fraction': fraction,
        'status': status,
      });
    }
    if (account == null) tooltip.add('目前清單找不到這個帳號，pin 未自動改綁。');
    if (known != null) tooltip.add('來源更新：${ageText(known.fetchedAt, now)}');
    if (error != null) tooltip.add('查詢失敗，保留上次已知資料。');
    return {
      'id': pin.id,
      'provider': known?.provider ?? 'unknown',
      'status': account == null
          ? 'missing'
          : account.disabled || account.issue != null || error != null
          ? 'error'
          : accountStale(account)
          ? 'stale'
          : 'ok',
      'title': title,
      'tooltip': tooltip.join('\n'),
      'showIcon': pin.showIcon,
      'label': pin.label,
      'labelWidth': pin.labelWidth,
      'color': pin.color,
      'layers': layers,
    };
  }

  Map<String, Object?> panelView() {
    final pinnedKeys = preferences.pins.map((pin) => pin.accountKey).toSet();
    return {
      'initialized': initialized,
      'loading': loading,
      'theme': preferences.theme.name,
      'layout': preferences.layout.name,
      'dense': preferences.dense,
      'footer': loading
          ? '向 OMP 查詢中…'
          : snapshot == null
          ? '等待來源資料 · 每 5 分鐘更新'
          : '快照 ${ageText(snapshot!.generatedAt, now)} · 每 5 分鐘更新',
      'notices': [
        if (error != null)
          '$error${snapshot == null ? '' : '\n保留上次已知資料；來源更新時間未重設。'}',
        ?storageError,
      ],
      'emptyMessage': !initialized || loading && snapshot == null
          ? '正在讀取 OMP 的訂閱用量…'
          : snapshot == null
          ? '目前沒有可顯示的 OMP 用量。請先在 OMP 登入訂閱，或到設定確認 CLI 路徑。'
          : 'OMP 未回報可查詢的帳號；不代表所有登入的 provider 都沒有配額。',
      'accounts': [
        for (final account in orderedAccounts())
          _panelAccount(account, pinnedKeys),
      ],
    };
  }

  Map<String, Object?> _panelAccount(
    UsageAccount account,
    Set<String> pinnedKeys,
  ) {
    final hidden =
        preferences.accountPreferences[account.key]?.hiddenLimitIds.toSet() ??
        const <String>{};
    final warnings = [
      if (account.issue != null) account.issue!,
      if (account.disabled && account.issue == null) 'OMP 已停用此憑證；請到 OMP 處理登入。',
      if (!account.identityKnown) '來源缺少可靠身份，不能建立持久 pin。',
    ];
    final limits = <Map<String, Object?>>[];
    var needsAttention =
        warnings.isNotEmpty || accountStale(account) || error != null;
    for (final limit in account.limits) {
      final value = limit.valueText(
        LayerMode.remaining,
        now,
        raw: preferences.rawValues,
      );
      final sourceStatus = limitStatus(account, limit);
      final status = sourceStatus == 'ok' && value == '無資料'
          ? 'missing'
          : sourceStatus;
      if (status != 'ok') needsAttention = true;
      if (hidden.contains(limit.id) && status == 'ok') continue;
      limits.add({
        'id': limit.id,
        'label': '${limit.label}${limit.shared ? ' · 共用' : ''}',
        'value': value,
        'reset': switch (limit.resetState(now)) {
          ResetState.unknown => '無重置時間',
          ResetState.due => '重置期限已到 · 待來源更新',
          ResetState.upcoming => '${limit.valueText(LayerMode.reset, now)}後重置',
        },
        'fraction': limit.fraction(LayerMode.remaining),
        'status': status,
        'warning': limit.status != 'ok'
            ? '來源狀態：${limit.status}'
            : status == 'stale'
            ? '舊資料 · 待來源更新'
            : status == 'error'
            ? '查詢異常 · 保留已知資料'
            : status == 'missing'
            ? '缺少配額數值'
            : null,
      });
    }
    return {
      'id': account.key,
      'provider': account.provider,
      'name': providerName(account.provider),
      'label': accountLabel(account),
      'plan': account.plan,
      'organization': account.orgName,
      'age':
          '${accountStale(account) ? '舊資料 · ' : ''}${ageText(account.fetchedAt, now)}',
      'pinned': pinnedKeys.contains(account.key),
      'warning': warnings.isEmpty ? null : warnings.join('\n'),
      'needsAttention': needsAttention || account.limits.isEmpty,
      'emptyMessage': account.limits.isEmpty
          ? '沒有可用的配額資料；不代表 0% 或無限制。'
          : '此帳號的一般窗口已在顯示設定隱藏。',
      'limits': limits,
    };
  }

  Future<void> _publishPanel() async {
    if (_disposed) return;
    try {
      await desktop.updatePanel(panelView());
    } on Object {
      error = 'macOS 用量面板更新失敗。請重新啟動 app。';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _publishMenu() async {
    if (_disposed) return;
    try {
      await desktop.updatePins([
        for (final pin in preferences.pins) pinView(pin),
      ]);
    } on Object {
      error = 'macOS 選單列更新失敗。請重新啟動 app。';
      _changed();
    }
  }

  void _changed() {
    if (_disposed) return;
    notifyListeners();
    unawaited(_publishPanel());
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _adapter?.cancel();
    _pollTimer?.cancel();
    _clockTimer?.cancel();
    desktop.onEvent = null;
    super.dispose();
  }
}
