import 'dart:async';
import 'dart:convert';
import 'dart:io';

enum LayerMode { remaining, used, reset }

enum ResetState { unknown, notStarted, upcoming, due }

enum PanelLayout { cards, table, focus }

enum ThemeChoice { system, light, dark }

class UsageLimit {
  const UsageLimit({
    required this.id,
    required this.label,
    this.unit = 'unknown',
    this.status = 'unknown',
    this.windowId,
    this.sharedGroup,
    this.shared = false,
    this.resetsAt,
    this.resetNotStarted = false,
    this.fetchedAt,
    this.duration,
    this.used,
    this.remaining,
    this.limit,
    this.usedFraction,
    this.remainingFraction,
  });

  final String id, label, unit, status;
  final String? windowId, sharedGroup;
  final bool shared;
  final bool resetNotStarted;
  final DateTime? fetchedAt, resetsAt;
  final Duration? duration;
  final double? used, remaining, limit, usedFraction, remainingFraction;

  ResetState resetState(DateTime now) {
    final reset = resetsAt;
    if (reset != null) {
      return now.isBefore(reset) ? ResetState.upcoming : ResetState.due;
    }
    return resetNotStarted && (duration?.inMilliseconds ?? 0) > 0
        ? ResetState.notStarted
        : ResetState.unknown;
  }

  double? fraction(LayerMode mode) {
    if (mode == LayerMode.reset) return null;
    if (mode == LayerMode.used) {
      if (usedFraction != null) return usedFraction;
      if (used != null && limit != null && limit! > 0) return used! / limit!;
      if (unit == 'percent' && used != null) return used! / 100;
      final left = _remainingFraction();
      return left == null ? null : _nonnegative(1 - left);
    }
    final left = _remainingFraction();
    if (left != null) return left;
    double? taken = usedFraction;
    if (taken == null && used != null && limit != null && limit! > 0) {
      taken = used! / limit!;
    }
    if (taken == null && unit == 'percent' && used != null) taken = used! / 100;
    return taken == null ? null : _nonnegative(1 - taken);
  }

  double? barFraction(LayerMode mode, DateTime now) {
    if (mode != LayerMode.reset) return fraction(mode);
    final reset = resetsAt;
    final durationMs = duration?.inMilliseconds;
    if (durationMs == null || durationMs <= 0) return null;
    if (reset == null) return resetNotStarted ? 1 : null;
    return (reset.difference(now).inMilliseconds / durationMs)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double? _remainingFraction() {
    if (remainingFraction != null) return remainingFraction;
    if (remaining != null && limit != null && limit! > 0) {
      return remaining! / limit!;
    }
    if (unit == 'percent' && remaining != null) return remaining! / 100;
    return null;
  }

  String valueText(LayerMode mode, DateTime now, {bool raw = false}) {
    if (mode == LayerMode.reset) {
      final state = resetState(now);
      if (state == ResetState.unknown) return '無重置時間';
      if (state == ResetState.due) return '待更新';
      final difference = state == ResetState.notStarted
          ? duration!
          : resetsAt!.difference(now);
      if (difference.inSeconds < 60) return '<1分';
      final minutes = (difference.inSeconds / 60).ceil();
      if (minutes < 60) return '$minutes分';
      final hours = minutes ~/ 60;
      if (hours < 24) return '$hours時${minutes % 60}分';
      return '${hours ~/ 24}天${hours % 24}時';
    }
    final ratio = fraction(mode);
    if (!raw && unit == 'percent' && ratio != null) {
      return '${_numberText(ratio * 100)}%';
    }
    double? amount = mode == LayerMode.used ? used : remaining;
    if (amount == null && limit != null) {
      final other = mode == LayerMode.used ? remaining : used;
      if (other != null) amount = _nonnegative(limit! - other);
    }
    if (amount == null && unit == 'percent' && ratio != null) {
      return '${_numberText(ratio * 100, precise: raw)}%';
    }
    if (amount == null) {
      if (!raw && ratio != null) {
        final sourceUnit = unit == 'usd'
            ? 'USD'
            : unit == 'unknown'
            ? '單位未知'
            : unit;
        return '${_numberText(ratio * 100)}%（$sourceUnit 配額比例）';
      }
      return '無資料';
    }
    final text = _numberText(amount, precise: raw || unit != 'percent');
    return switch (unit) {
      'percent' => '$text%',
      'usd' => '$text USD',
      'unknown' => '$text（單位未知）',
      _ => '$text $unit',
    };
  }

  static UsageLimit fromJson(Map<String, dynamic> json) => UsageLimit(
    id: _requiredString(json, 'id'),
    label: _requiredString(json, 'label'),
    unit: _optionalString(json, 'unit') ?? 'unknown',
    status: _optionalString(json, 'status') ?? 'unknown',
    windowId: _optionalString(json, 'windowId'),
    sharedGroup: _optionalString(json, 'sharedGroup'),
    shared: _bool(json, 'shared', false),
    fetchedAt: _storedDate(json['fetchedAt']),
    resetsAt: _storedDate(json['resetsAt']),
    resetNotStarted: _bool(json, 'resetNotStarted', false),
    duration: _duration(json['durationMs']),
    used: _storedNumber(json, 'used'),
    remaining: _storedNumber(json, 'remaining'),
    limit: _storedNumber(json, 'limit'),
    usedFraction: _storedNumber(json, 'usedFraction'),
    remainingFraction: _storedNumber(json, 'remainingFraction'),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'unit': unit,
    'status': status,
    'windowId': windowId,
    'sharedGroup': sharedGroup,
    'shared': shared,
    'fetchedAt': fetchedAt?.toUtc().toIso8601String(),
    'resetsAt': resetsAt?.toUtc().toIso8601String(),
    'resetNotStarted': resetNotStarted,
    'durationMs': duration?.inMilliseconds,
    'used': used,
    'remaining': remaining,
    'limit': limit,
    'usedFraction': usedFraction,
    'remainingFraction': remainingFraction,
  };
}

class UsageAccount {
  UsageAccount({
    required this.key,
    required this.provider,
    required this.displayName,
    this.email,
    this.accountId,
    this.orgId,
    this.projectId,
    this.orgName,
    this.plan,
    this.resetSeatCount,
    this.soonestResetSeatExpiresAt,
    this.resetCreditsFetchedAt,
    this.oauthReloginEstimatedAt,
    this.oauthReminderFetchedAt,
    this.issue,
    this.fetchedAt,
    List<UsageLimit> limits = const [],
    this.disabled = false,
    this.identityKnown = false,
  }) : limits = List.unmodifiable(limits);

  final String key, provider, displayName;
  final String? email, accountId, orgId, projectId, orgName, plan, issue;
  final DateTime? fetchedAt;
  final int? resetSeatCount;
  final DateTime? soonestResetSeatExpiresAt, resetCreditsFetchedAt;
  final DateTime? oauthReloginEstimatedAt, oauthReminderFetchedAt;
  final List<UsageLimit> limits;
  final bool disabled, identityKnown;

  static UsageAccount fromJson(Map<String, dynamic> json) => UsageAccount(
    key: _requiredString(json, 'key'),
    provider: _requiredString(json, 'provider'),
    displayName: _requiredString(json, 'displayName'),
    email: _optionalString(json, 'email'),
    accountId: _optionalString(json, 'accountId'),
    orgId: _optionalString(json, 'orgId'),
    projectId: _optionalString(json, 'projectId'),
    orgName: _optionalString(json, 'orgName'),
    plan: _optionalString(json, 'plan'),
    resetSeatCount: json['resetSeatCount'] == null
        ? null
        : _integer(json, 'resetSeatCount', 0),
    soonestResetSeatExpiresAt: _storedDate(json['soonestResetSeatExpiresAt']),
    resetCreditsFetchedAt: _storedDate(json['resetCreditsFetchedAt']),
    oauthReloginEstimatedAt: _storedDate(json['oauthReloginEstimatedAt']),
    oauthReminderFetchedAt: _storedDate(json['oauthReminderFetchedAt']),
    issue: _optionalString(json, 'issue'),
    fetchedAt: _storedDate(json['fetchedAt']),
    limits: _list(
      json,
      'limits',
    ).map((item) => UsageLimit.fromJson(_requiredMap(item))).toList(),
    disabled: _bool(json, 'disabled', false),
    identityKnown: _bool(json, 'identityKnown', false),
  );

  Map<String, dynamic> toJson() => {
    'key': key,
    'provider': provider,
    'displayName': displayName,
    'email': email,
    'accountId': accountId,
    'orgId': orgId,
    'projectId': projectId,
    'orgName': orgName,
    'plan': plan,
    'resetSeatCount': resetSeatCount,
    'soonestResetSeatExpiresAt': soonestResetSeatExpiresAt
        ?.toUtc()
        .toIso8601String(),
    'resetCreditsFetchedAt': resetCreditsFetchedAt?.toUtc().toIso8601String(),
    'oauthReloginEstimatedAt': oauthReloginEstimatedAt
        ?.toUtc()
        .toIso8601String(),
    'oauthReminderFetchedAt': oauthReminderFetchedAt?.toUtc().toIso8601String(),
    'issue': issue,
    'fetchedAt': fetchedAt?.toUtc().toIso8601String(),
    'limits': limits.map((item) => item.toJson()).toList(),
    'disabled': disabled,
    'identityKnown': identityKnown,
  };
}

class UsageSnapshot {
  UsageSnapshot({
    required this.generatedAt,
    required List<UsageAccount> accounts,
    required this.coverageNote,
  }) : accounts = List.unmodifiable(accounts);

  final DateTime generatedAt;
  final List<UsageAccount> accounts;
  final String coverageNote;

  static UsageSnapshot fromOmpJson(
    Map<String, dynamic> payload, {
    String? anthropicUsageText,
    DateTime? oauthObservedAt,
  }) {
    final generatedAt = _epochMilliseconds(payload['generatedAt']);
    if (generatedAt == null || payload['reports'] is! List) {
      throw const _SafeException('OMP 用量資料格式不受支援，請確認 CLI 版本。');
    }
    final oauthFetchedAt = anthropicUsageText == null
        ? null
        : oauthObservedAt ?? generatedAt;
    final oauthDeadlines = anthropicUsageText == null
        ? const <String, DateTime?>{}
        : _anthropicReloginDeadlines(anthropicUsageText, oauthFetchedAt!);
    final accounts = <UsageAccount>[];
    for (final (index, item) in (payload['reports'] as List).indexed) {
      final report = _requiredMap(item);
      final provider = _requiredString(report, 'provider');
      final metadata = _map(report['metadata']) ?? const <String, dynamic>{};
      final fetchedAt = _epochMilliseconds(report['fetchedAt']);
      final supportsResetCredits =
          provider == 'openai-codex' || provider == 'anthropic';
      final resetCredits = supportsResetCredits
          ? _map(report['resetCredits'])
          : null;
      final rawResetSeatCount = resetCredits?['availableCount'];
      final resetSeatCount = rawResetSeatCount is int && rawResetSeatCount >= 0
          ? rawResetSeatCount
          : null;
      final soonestResetSeatExpiresAt = resetSeatCount == 0
          ? null
          : _soonestResetCreditExpiry(resetCredits, fetchedAt);
      final rawLimits = report['limits'];
      final grouped = <String, List<UsageLimit>>{};
      final identities = <String, Map<String, dynamic>>{};
      var incomplete = rawLimits is! List;
      for (final raw in rawLimits is List ? rawLimits : const []) {
        final limit = _map(raw);
        if (limit == null || _text(limit['id']) == null) {
          incomplete = true;
          continue;
        }
        final scope = _map(limit['scope']) ?? const <String, dynamic>{};
        final identity = <String, dynamic>{
          for (final field in [
            'email',
            'accountId',
            'orgId',
            'projectId',
            'orgName',
          ])
            field: _text(scope[field]) ?? _text(metadata[field]),
        };
        final key = _accountKey(provider, identity, 'report-$index');
        identities[key] = identity;
        grouped.putIfAbsent(key, () => []).add(_ompLimit(limit, fetchedAt));
      }
      if (grouped.isEmpty) {
        final identity = <String, dynamic>{
          for (final field in [
            'email',
            'accountId',
            'orgId',
            'projectId',
            'orgName',
          ])
            field: _text(metadata[field]),
        };
        final key = _accountKey(provider, identity, 'report-$index');
        identities[key] = identity;
        grouped[key] = [];
      }
      for (final entry in grouped.entries) {
        final identity = identities[entry.key]!;
        final known = _identityKnown(identity);
        final limits = _uniqueLimits(entry.value);
        final ownsAccountMetadata =
            supportsResetCredits &&
            _reportMetadataBelongsTo(metadata, identity, grouped.length == 1);
        final ownsOAuthReminder = provider == 'anthropic' && ownsAccountMetadata;
        final issue = !known
            ? '用量無法可靠歸屬帳號，不能永久釘選。'
            : incomplete
            ? '部分用量資料格式無法辨識；缺值不代表零。'
            : limits.isEmpty
            ? '此帳號目前沒有可用用量資料。'
            : null;
        _mergeReportedAccount(
          accounts,
          _makeAccount(
            provider,
            entry.key,
            identity,
            limits: limits,
            fetchedAt: fetchedAt,
            plan: _text(metadata['planType']) ?? _text(metadata['plan']),
            resetSeatCount: ownsAccountMetadata ? resetSeatCount : null,
            soonestResetSeatExpiresAt: ownsAccountMetadata
                ? soonestResetSeatExpiresAt
                : null,
            resetCreditsFetchedAt: ownsAccountMetadata ? fetchedAt : null,
            oauthReloginEstimatedAt: ownsOAuthReminder
                ? oauthDeadlines[_oauthIdentityLabel(identity)]
                : null,
            oauthReminderFetchedAt: ownsOAuthReminder ? oauthFetchedAt : null,
            issue: issue,
          ),
        );
      }
    }
    for (final field in ['accountsWithoutUsage', 'disabledCredentials']) {
      final entries = payload[field];
      if (entries != null && entries is! List) {
        throw const _SafeException('OMP 帳號清單格式不受支援。');
      }
      for (final (index, item)
          in (entries is List ? entries : const []).indexed) {
        final identity = _requiredMap(item);
        final provider = _requiredString(identity, 'provider');
        final disabled = field == 'disabledCredentials';
        var key = _accountKey(provider, identity, '$field-$index');
        // A tombstone must not replace a working subscription with the same identity.
        if (accounts.any((account) => account.key == key)) {
          key = '$key:${disabled ? 'disabled' : 'missing'}';
        }
        if (accounts.any((account) => account.key == key)) continue;
        accounts.add(
          _makeAccount(
            provider,
            key,
            identity,
            fetchedAt: disabled
                ? _epochMilliseconds(identity['disabledAtMs'])
                : null,
            disabled: disabled,
            oauthReloginEstimatedAt: provider == 'anthropic' && !disabled
                ? oauthDeadlines[_oauthIdentityLabel(identity)]
                : null,
            oauthReminderFetchedAt: provider == 'anthropic' && !disabled
                ? oauthFetchedAt
                : null,
            issue: disabled
                ? 'OMP 已停用此登入憑證；請在 OMP 檢查或重新登入。'
                : '已登入，但 OMP 未回報此帳號用量。',
          ),
        );
      }
    }
    return UsageSnapshot(
      generatedAt: generatedAt,
      accounts: accounts,
      coverageNote:
          '僅涵蓋 OMP usage 可回報的帳號、未回報帳號及停用憑證；'
          '沒有 usage 介面的 provider 可能不在清單內。共享窗口不加總；'
          '資料時間保留 OMP 回報時間，不保證為即時查詢。',
    );
  }

  static UsageSnapshot fromJson(Map<String, dynamic> json) {
    _cacheSchema(json);
    final generatedAt = _storedDate(json['generatedAt']);
    if (generatedAt == null) throw const _SafeException('快取缺少有效的資料時間。');
    return UsageSnapshot(
      generatedAt: generatedAt,
      accounts: _list(
        json,
        'accounts',
      ).map((item) => UsageAccount.fromJson(_requiredMap(item))).toList(),
      coverageNote: _requiredString(json, 'coverageNote'),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 1,
    'generatedAt': generatedAt.toUtc().toIso8601String(),
    'accounts': accounts.map((item) => item.toJson()).toList(),
    'coverageNote': coverageNote,
  };
}

class PinMetric {
  const PinMetric({required this.limitId, required this.mode});
  final String limitId;
  final LayerMode mode;
  static PinMetric fromJson(Map<String, dynamic> json) => PinMetric(
    limitId: _requiredString(json, 'limitId'),
    mode: _enumValue(LayerMode.values, json['mode'], LayerMode.remaining),
  );
  Map<String, dynamic> toJson() => {'limitId': limitId, 'mode': mode.name};
}

class PinLayer {
  const PinLayer({this.text, this.bar});
  final PinMetric? text, bar;
  bool get isEmpty => text == null && bar == null;
  static PinLayer fromJson(Map<String, dynamic> json) => PinLayer(
    text: json['text'] == null
        ? null
        : PinMetric.fromJson(_requiredMap(json['text'])),
    bar: json['bar'] == null
        ? null
        : PinMetric.fromJson(_requiredMap(json['bar'])),
  );
  Map<String, dynamic> toJson() => {
    'text': text?.toJson(),
    'bar': bar?.toJson(),
  };
}

class PinPreference {
  const PinPreference({
    required this.id,
    required this.accountKey,
    this.label = '',
    this.color = 'auto',
    this.top,
    this.bottom,
    this.labelWidth = 0,
    this.showIcon = true,
  });
  final String id, accountKey, label, color;
  final PinLayer? top, bottom;
  final int labelWidth;
  final bool showIcon;
  static PinPreference fromJson(Map<String, dynamic> json) => PinPreference(
    id: _requiredString(json, 'id'),
    accountKey: _requiredString(json, 'accountKey'),
    label: _optionalString(json, 'label') ?? '',
    color: _optionalString(json, 'color') ?? 'auto',
    top: json['top'] == null
        ? null
        : PinLayer.fromJson(_requiredMap(json['top'])),
    bottom: json['bottom'] == null
        ? null
        : PinLayer.fromJson(_requiredMap(json['bottom'])),
    labelWidth: _integer(json, 'labelWidth', 0),
    showIcon: _bool(json, 'showIcon', true),
  );
  static PinPreference _fromV1Json(Map<String, dynamic> json) {
    final style = _optionalString(json, 'style') ?? 'text';
    if (style != 'text' && style != 'bars' && style != 'icon') {
      throw const _SafeException('設定選項格式損壞或版本不受支援。');
    }
    PinLayer? migrateLayer(dynamic value) {
      if (value == null) return null;
      final metric = PinMetric.fromJson(_requiredMap(value));
      return PinLayer(
        text: metric,
        bar: style == 'bars' && metric.mode != LayerMode.reset ? metric : null,
      );
    }

    final top = migrateLayer(json['top']);
    final bottom = migrateLayer(json['bottom']);
    return PinPreference(
      id: _requiredString(json, 'id'),
      accountKey: _requiredString(json, 'accountKey'),
      label: _optionalString(json, 'label') ?? '',
      color: _optionalString(json, 'color') ?? 'auto',
      top: style == 'icon' ? null : top,
      bottom: style == 'icon' ? null : bottom,
      labelWidth: style == 'icon' ? 0 : _integer(json, 'labelWidth', 0),
      showIcon: style == 'icon' || _bool(json, 'showIcon', true),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountKey': accountKey,
    'label': label,
    'color': color,
    'top': top?.toJson(),
    'bottom': bottom?.toJson(),
    'labelWidth': labelWidth,
    'showIcon': showIcon,
  };
}

class AccountPreference {
  AccountPreference({this.alias = '', List<String> hiddenLimitIds = const []})
    : hiddenLimitIds = List.unmodifiable(hiddenLimitIds);
  final String alias;
  final List<String> hiddenLimitIds;
  static AccountPreference fromJson(Map<String, dynamic> json) =>
      AccountPreference(
        alias: _optionalString(json, 'alias') ?? '',
        hiddenLimitIds: _strings(json, 'hiddenLimitIds'),
      );
  Map<String, dynamic> toJson() => {
    'alias': alias,
    'hiddenLimitIds': hiddenLimitIds.toList(),
  };
}

class Preferences {
  Preferences({
    this.selectedAgent = 'omp',
    this.ompPath = '',
    this.refreshIntervalMinutes = 5,
    this.dense = false,
    this.rawValues = false,
    this.layout = PanelLayout.cards,
    this.theme = ThemeChoice.system,
    this.pinBarLength = 25,
    List<PinPreference> pins = const [],
    Map<String, AccountPreference> accountPreferences = const {},
    List<String> accountOrder = const [],
  }) : pins = List.unmodifiable(pins),
       accountPreferences = Map.unmodifiable(accountPreferences),
       accountOrder = List.unmodifiable(accountOrder) {
    if (refreshIntervalMinutes < 1 || refreshIntervalMinutes > 10) {
      throw RangeError.range(
        refreshIntervalMinutes,
        1,
        10,
        'refreshIntervalMinutes',
      );
    }
    if (pinBarLength < 10 || pinBarLength > 50) {
      throw RangeError.range(pinBarLength, 10, 50, 'pinBarLength');
    }
  }

  final String selectedAgent, ompPath;
  final int refreshIntervalMinutes;
  final int pinBarLength;
  double get pinBarWidth => pinBarLength.toDouble();
  final bool dense, rawValues;
  final PanelLayout layout;
  final ThemeChoice theme;
  final List<PinPreference> pins;
  final Map<String, AccountPreference> accountPreferences;
  final List<String> accountOrder;

  Preferences copyWith({
    String? selectedAgent,
    String? ompPath,
    int? refreshIntervalMinutes,
    bool? dense,
    bool? rawValues,
    PanelLayout? layout,
    ThemeChoice? theme,
    int? pinBarLength,
    List<PinPreference>? pins,
    Map<String, AccountPreference>? accountPreferences,
    List<String>? accountOrder,
  }) => Preferences(
    selectedAgent: selectedAgent ?? this.selectedAgent,
    ompPath: ompPath ?? this.ompPath,
    refreshIntervalMinutes:
        refreshIntervalMinutes ?? this.refreshIntervalMinutes,
    dense: dense ?? this.dense,
    rawValues: rawValues ?? this.rawValues,
    layout: layout ?? this.layout,
    theme: theme ?? this.theme,
    pinBarLength: pinBarLength ?? this.pinBarLength,
    pins: pins ?? this.pins,
    accountPreferences: accountPreferences ?? this.accountPreferences,
    accountOrder: accountOrder ?? this.accountOrder,
  );

  static Preferences fromJson(Map<String, dynamic> json) {
    final version = json['schemaVersion'];
    if (version != 1 && version != 2) {
      throw const _SafeException('儲存資料版本不受支援。');
    }
    var pinBarLength = _integer(json, 'pinBarLength', 25);
    if (!json.containsKey('pinBarLength') &&
        json.containsKey('pinBarLengthLevel')) {
      final level = _integer(json, 'pinBarLengthLevel', 3);
      if (level < 1 || level > 4) {
        throw RangeError.range(level, 1, 4, 'pinBarLengthLevel');
      }
      pinBarLength = (level + 1) * 8;
    }
    return Preferences(
      selectedAgent: _optionalString(json, 'selectedAgent') ?? 'omp',
      ompPath: _optionalString(json, 'ompPath') ?? '',
      refreshIntervalMinutes: _integer(json, 'refreshIntervalMinutes', 5),
      dense: _bool(json, 'dense', false),
      rawValues: _bool(json, 'rawValues', false),
      layout: _enumValue(PanelLayout.values, json['layout'], PanelLayout.cards),
      theme: _enumValue(ThemeChoice.values, json['theme'], ThemeChoice.system),
      pinBarLength: pinBarLength,
      pins: _list(json, 'pins').map((item) {
        final pin = _requiredMap(item);
        return version == 1
            ? PinPreference._fromV1Json(pin)
            : PinPreference.fromJson(pin);
      }).toList(),
      accountPreferences: _requiredMap(json['accountPreferences']).map(
        (key, value) =>
            MapEntry(key, AccountPreference.fromJson(_requiredMap(value))),
      ),
      accountOrder: _strings(json, 'accountOrder'),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': 2,
    'selectedAgent': selectedAgent,
    'ompPath': ompPath,
    'refreshIntervalMinutes': refreshIntervalMinutes,
    'dense': dense,
    'rawValues': rawValues,
    'layout': layout.name,
    'theme': theme.name,
    'pinBarLength': pinBarLength,
    'pins': pins.map((item) => item.toJson()).toList(),
    'accountPreferences': accountPreferences.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
    'accountOrder': accountOrder.toList(),
  };
}

abstract class AgentAdapter {
  String get id;
  String get label;
  String get profile;
  Future<UsageSnapshot> fetch();
  void cancel();
}

class OmpAdapter implements AgentAdapter {
  OmpAdapter({String? executable}) : _requestedExecutable = _text(executable);
  final String? _requestedExecutable;
  String? _executablePath;
  Future<UsageSnapshot>? _inFlight;
  _CliJob? _active;

  @override
  String get id => 'omp';
  @override
  String get label => 'OMP';
  @override
  String get profile => _text(Platform.environment['OMP_PROFILE']) ?? 'default';
  String? get executablePath => _executablePath;

  static Future<String?> discoverExecutable() async {
    for (final directory in _executableDirectories()) {
      final path = '$directory/omp';
      if (await _isExecutable(path)) return path;
    }
    return null;
  }

  @override
  Future<UsageSnapshot> fetch() {
    if (_inFlight != null) return _inFlight!;
    final job = _CliJob();
    _active = job;
    final timer = Timer(const Duration(seconds: 60), () {
      job.abort(const _SafeException('OMP 查詢逾時；已停止查詢，可稍後重試。'));
    });
    final future =
        Future.any<UsageSnapshot>([
          _fetch(job),
          job.aborted.future.then<UsageSnapshot>((error) => throw error),
        ]).whenComplete(() {
          timer.cancel();
          if (identical(_active, job)) {
            _active = null;
            _inFlight = null;
          }
        });
    _inFlight = future;
    return future;
  }

  Future<UsageSnapshot> _fetch(_CliJob job) async {
    try {
      var executable = _requestedExecutable;
      if (executable == null) {
        executable = await discoverExecutable();
      } else {
        executable = _expandHome(executable);
        if (!executable.contains('/')) {
          String? resolved;
          for (final directory in _executableDirectories()) {
            final candidate = '$directory/$executable';
            if (await _isExecutable(candidate)) {
              resolved = candidate;
              break;
            }
          }
          executable = resolved;
        } else {
          executable = File(executable).absolute.path;
          if (!await _isExecutable(executable)) executable = null;
        }
      }
      job.check();
      if (executable == null) {
        throw const _SafeException('找不到可執行的 OMP，請在設定指定 CLI 路徑。');
      }
      _executablePath = executable;
      final applicationDirectory = _applicationDirectory();
      await _privateDirectory(applicationDirectory);
      final directory = Directory('${applicationDirectory.path}/cli');
      await _privateDirectory(directory);
      job.check();
      final paths = <String>{
        File(executable).absolute.parent.path,
        ..._executableDirectories(),
      };
      final environment = {'PATH': paths.join(':')};
      final output = await _runUsage(
        job,
        executable,
        directory.path,
        environment,
        const ['usage', '--json'],
      );
      dynamic decoded;
      try {
        decoded = jsonDecode(output);
      } on FormatException {
        throw const _SafeException('OMP 未回傳有效 JSON，請確認 CLI 版本與設定。');
      }
      final payload = _requiredMap(decoded);
      String? anthropicUsageText;
      DateTime? oauthObservedAt;
      if (_hasAnthropicAccounts(payload)) {
        anthropicUsageText = await _runUsage(
          job,
          executable,
          directory.path,
          environment,
          const ['usage', '--provider', 'anthropic'],
        );
        oauthObservedAt = DateTime.now();
      }
      return UsageSnapshot.fromOmpJson(
        payload,
        anthropicUsageText: anthropicUsageText,
        oauthObservedAt: oauthObservedAt,
      );
    } on _SafeException {
      rethrow;
    } catch (_) {
      throw const _SafeException('無法執行 OMP 用量查詢，請檢查 CLI 路徑及權限。');
    } finally {
      // SIGKILL also handles a CLI that ignores ordinary termination.
      job.process?.kill(ProcessSignal.sigkill);
      job.process = null;
    }
  }

  Future<String> _runUsage(
    _CliJob job,
    String executable,
    String directory,
    Map<String, String> environment,
    List<String> arguments,
  ) async {
    job.check();
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: directory,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
    );
    job.process = process;
    job.check();
    final stdout = _boundedText(process.stdout, 8 * 1024 * 1024, job);
    final stderr = _boundedText(process.stderr, 256 * 1024, job);
    // Drain both pipes; stderr is never surfaced or persisted.
    final exitCode = process.exitCode.then((code) {
      job.process = null;
      return code;
    });
    final results = await Future.wait<Object>([stdout, stderr, exitCode]);
    job.check();
    if (results[2] != 0) {
      throw const _SafeException('OMP 用量查詢失敗，請在 OMP 檢查登入與網路狀態。');
    }
    return results[0] as String;
  }

  @override
  void cancel() {
    _active?.abort(const _SafeException('OMP 查詢已取消。'));
    _active = null;
    _inFlight = null;
  }
}

class AppStorage {
  AppStorage({Directory? directory})
    : _directory = directory ?? _applicationDirectory() {
    if (directory == null) {
      _legacyDirectory = Directory(
        '${_directory.parent.path}/Cross Agent Usage',
      );
    }
  }
  final Directory _directory;
  Directory? _legacyDirectory;
  Future<void> _pending = Future.value();
  bool _preferencesChecked = false;
  bool _preferencesCorrupt = false;
  int _temporaryCounter = 0;

  Future<T> _queue<T>(Future<T> Function() operation) {
    final next = _pending.then((_) {
      if (_legacyDirectory == null) return operation();
      return _migrateDirectory().then((_) => operation());
    });
    _pending = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> _migrateDirectory() async {
    final legacy = _legacyDirectory!;
    if (await FileSystemEntity.type(_directory.path, followLinks: false) ==
        FileSystemEntityType.notFound) {
      final type = await FileSystemEntity.type(legacy.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await legacy.rename(_directory.path);
      } else if (type != FileSystemEntityType.notFound) {
        throw const _SafeException('舊版儲存目錄不是一般目錄；原始資料保留，未自動搬移。');
      }
    }
    _legacyDirectory = null;
  }

  Future<Preferences> loadPreferences() => _queue(_readPreferences);

  Future<Preferences> _readPreferences() async {
    try {
      final json = await _readFile('preferences.json');
      final result = json == null ? Preferences() : Preferences.fromJson(json);
      _preferencesChecked = true;
      _preferencesCorrupt = false;
      return result;
    } catch (_) {
      _preferencesChecked = true;
      _preferencesCorrupt = true;
      throw const _SafeException('設定檔損壞或無法讀取；原檔保留，不會自動覆寫。');
    }
  }

  Future<void> savePreferences(Preferences preferences) => _queue(() async {
    if (!_preferencesChecked) await _readPreferences();
    if (_preferencesCorrupt) {
      throw const _SafeException('設定檔損壞或無法讀取；請先處理原檔，避免遺失設定。');
    }
    await _atomicWrite('preferences.json', preferences.toJson());
  });

  Future<void> resetPreferences(Preferences preferences) => _queue(() async {
    await _privateDirectory(_directory);
    final original = File('${_directory.path}/preferences.json');
    File? backup;
    final type = await FileSystemEntity.type(original.path, followLinks: false);
    if (type != FileSystemEntityType.notFound) {
      if (type != FileSystemEntityType.file) {
        throw const _SafeException('設定不是一般檔案，請先處理原檔；未自動替換。');
      }
      backup = await original.rename(
        '${_directory.path}/preferences.backup-${DateTime.now().microsecondsSinceEpoch}-${_temporaryCounter++}.json',
      );
      await _permission('600', backup.path);
    }
    try {
      await _atomicWrite('preferences.json', preferences.toJson());
      _preferencesChecked = true;
      _preferencesCorrupt = false;
    } catch (_) {
      if (backup != null) await backup.rename(original.path);
      rethrow;
    }
  });

  Future<UsageSnapshot?> loadSnapshot(String agent) => _queue(() async {
    final filename = _snapshotFilename(agent);
    try {
      final json = await _readFile(filename);
      return json == null ? null : UsageSnapshot.fromJson(json);
    } catch (_) {
      throw const _SafeException('用量快取損壞或無法讀取；請重新查詢 OMP。');
    }
  });

  Future<void> saveSnapshot(String agent, UsageSnapshot snapshot) =>
      _queue(() async {
        await _atomicWrite(_snapshotFilename(agent), snapshot.toJson());
      });

  String _snapshotFilename(String agent) {
    if (!RegExp(r'^[a-z][a-z0-9-]{0,63}$').hasMatch(agent)) {
      throw const _SafeException('無效的 agent 快取名稱。');
    }
    return 'snapshot-$agent.json';
  }

  Future<Map<String, dynamic>?> _readFile(String filename) async {
    await _privateDirectory(_directory);
    final file = File('${_directory.path}/$filename');
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file ||
        await file.length() > 8 * 1024 * 1024) {
      throw const _SafeException('儲存資料不是有效的一般檔案。');
    }
    await _permission('600', file.path);
    return _requiredMap(jsonDecode(await file.readAsString()));
  }

  Future<void> _atomicWrite(String filename, Map<String, dynamic> json) async {
    File? temporary;
    try {
      await _privateDirectory(_directory);
      temporary = File(
        '${_directory.path}/.$filename.$pid.${DateTime.now().microsecondsSinceEpoch}.${_temporaryCounter++}.tmp',
      );
      await temporary.create(exclusive: true);
      await _permission('600', temporary.path);
      await temporary.writeAsString(jsonEncode(json), flush: true);
      await temporary.rename('${_directory.path}/$filename');
      temporary = null;
    } catch (_) {
      throw const _SafeException('無法儲存設定或快取；請檢查儲存目錄權限及磁碟空間。');
    } finally {
      if (temporary != null) {
        try {
          await temporary.delete();
        } catch (_) {
          /* Preserve the original failure. */
        }
      }
    }
  }
}

class _CliJob {
  Process? process;
  _SafeException? error;
  final Completer<_SafeException> aborted = Completer();
  void abort(_SafeException reason) {
    if (error != null) return;
    error = reason;
    process?.kill(ProcessSignal.sigkill);
    aborted.complete(reason);
  }

  void check() {
    if (error != null) {
      process?.kill(ProcessSignal.sigkill);
      throw error!;
    }
  }
}

Future<String> _boundedText(
  Stream<List<int>> source,
  int maximum,
  _CliJob job,
) async {
  var count = 0;
  Stream<List<int>> bounded() async* {
    await for (final chunk in source) {
      count += chunk.length;
      if (count > maximum) {
        const error = _SafeException('OMP 回傳資料超過安全大小上限，已停止查詢。');
        job.abort(error);
        throw error;
      }
      yield chunk;
    }
  }

  final buffer = StringBuffer();
  await for (final text in const Utf8Decoder(
    allowMalformed: true,
  ).bind(bounded())) {
    buffer.write(text);
  }
  return buffer.toString();
}

List<String> _executableDirectories() {
  final home = Platform.environment['HOME'];
  return <String>{
    ...?(Platform.environment['PATH']
        ?.split(':')
        .where((path) => path.startsWith('/'))),
    if (home != null) '$home/.bun/bin',
    if (home != null) '$home/.local/bin',
    '/opt/homebrew/bin',
    '/usr/local/bin',
    '/usr/bin',
    '/bin',
    '/usr/sbin',
    '/sbin',
  }.toList();
}

String _expandHome(String path) {
  final home = Platform.environment['HOME'];
  return home != null && path.startsWith('~/')
      ? '$home/${path.substring(2)}'
      : path;
}

Future<bool> _isExecutable(String path) async {
  try {
    final stat = await File(path).stat();
    return stat.type == FileSystemEntityType.file && (stat.mode & 0x49) != 0;
  } catch (_) {
    return false;
  }
}

Directory _applicationDirectory() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) {
    throw const _SafeException('無法取得使用者儲存目錄。');
  }
  return Directory('$home/Library/Application Support/AnyUsagePin');
}

Future<void> _privateDirectory(Directory directory) async {
  await directory.create(recursive: true);
  if (await FileSystemEntity.type(directory.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const _SafeException('儲存目錄不可為符號連結。');
  }
  await _permission('700', directory.path);
}

Future<void> _permission(String mode, String path) async {
  final result = await Process.run('/bin/chmod', [mode, path]);
  if (result.exitCode != 0) throw const _SafeException('無法設定私人儲存權限。');
}

UsageLimit _ompLimit(Map<String, dynamic> json, DateTime? fetchedAt) {
  final scope = _map(json['scope']) ?? const <String, dynamic>{};
  final window = _map(json['window']) ?? const <String, dynamic>{};
  final amount = _map(json['amount']) ?? const <String, dynamic>{};
  final id = _requiredString(json, 'id');
  final milliseconds = _finiteNumber(window['durationMs']);
  return UsageLimit(
    id: id,
    label: _text(json['label']) ?? _text(window['label']) ?? id,
    unit: _text(amount['unit']) ?? 'unknown',
    status: _text(json['status']) ?? 'unknown',
    windowId: _text(window['id']) ?? _text(scope['windowId']),
    sharedGroup: _text(scope['sharedGroup']),
    shared: scope['shared'] == true,
    fetchedAt: fetchedAt,
    resetsAt: _epochMilliseconds(window['resetsAt']),
    resetNotStarted: window['resetsAt'] == null,
    duration:
        milliseconds != null &&
            milliseconds >= 0 &&
            milliseconds < 8640000000000000
        ? Duration(milliseconds: milliseconds.round())
        : null,
    used: _finiteNumber(amount['used']),
    remaining: _finiteNumber(amount['remaining']),
    limit: _finiteNumber(amount['limit']),
    usedFraction: _finiteNumber(amount['usedFraction']),
    remainingFraction: _finiteNumber(amount['remainingFraction']),
  );
}

bool _identityKnown(Map<String, dynamic> identity) =>
    ['email', 'accountId'].any((field) => _text(identity[field]) != null);

String _accountKey(
  String provider,
  Map<String, dynamic> identity,
  String unknown,
) {
  if (!_identityKnown(identity)) return 'unknown:$provider:$unknown';
  final values = [
    provider,
    _text(identity['email'])?.toLowerCase(),
    _text(identity['accountId']),
    _text(identity['orgId']),
    _text(identity['projectId']),
  ];
  return '$provider:${base64Url.encode(utf8.encode(jsonEncode(values)))}';
}

DateTime? _soonestResetCreditExpiry(
  Map<String, dynamic>? resetCredits,
  DateTime? fetchedAt,
) {
  final credits = resetCredits?['credits'];
  if (credits is! List) return null;
  DateTime? soonest;
  for (final raw in credits) {
    final credit = _map(raw);
    if (credit == null) continue;
    final status = _text(credit['status']);
    if (status != null && status != 'available') continue;
    final rawExpiry = _text(credit['expiresAt']);
    final expiry = rawExpiry == null
        ? null
        : DateTime.tryParse(rawExpiry)?.toUtc();
    if (expiry == null || (fetchedAt != null && !expiry.isAfter(fetchedAt))) {
      continue;
    }
    if (soonest == null || expiry.isBefore(soonest)) soonest = expiry;
  }
  return soonest;
}

bool _reportMetadataBelongsTo(
  Map<String, dynamic> metadata,
  Map<String, dynamic> identity,
  bool onlyAccount,
) {
  if (!_identityKnown(metadata)) return onlyAccount;
  for (final field in ['email', 'accountId', 'orgId', 'projectId']) {
    final owner = _text(metadata[field]);
    if (owner == null) continue;
    final scoped = _text(identity[field]);
    if (field == 'email') {
      if (owner.toLowerCase() != scoped?.toLowerCase()) return false;
    } else if (owner != scoped) {
      return false;
    }
  }
  return true;
}

bool _hasAnthropicAccounts(Map<String, dynamic> payload) {
  for (final field in const ['reports', 'accountsWithoutUsage']) {
    final rows = payload[field];
    if (rows is! List) continue;
    for (final row in rows) {
      if (row is Map && row['provider'] == 'anthropic') return true;
    }
  }
  return false;
}

final _ansiSequence = RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]');
final _reloginLine = RegExp(
  r"^\s*⚠ (.+) — (?:re-login within ([0-9.dhms]+) \(Anthropic expires OAuth grants ~30d after login\)|(grant is past Anthropic's ~30d lifetime; re-login now))\s*$",
  multiLine: true,
);
final _durationPart = RegExp(r'(\d+(?:\.\d+)?)(ms|d|h|m|s)');

Map<String, DateTime?> _anthropicReloginDeadlines(
  String text,
  DateTime observedAt,
) {
  final deadlines = <String, DateTime?>{};
  for (final match in _reloginLine.allMatches(
    text.replaceAll(_ansiSequence, ''),
  )) {
    final duration = match.group(2);
    final remaining = duration == null ? Duration.zero : _ompDuration(duration);
    if (remaining == null) continue;
    final label = match.group(1)!.trim().toLowerCase();
    final deadline = observedAt.add(remaining);
    // Identical display labels cannot safely distinguish conflicting grants.
    deadlines[label] =
        deadlines.containsKey(label) && deadlines[label] != deadline
        ? null
        : deadline;
  }
  return deadlines;
}

Duration? _ompDuration(String value) {
  var end = 0;
  var milliseconds = 0.0;
  var previousUnit = double.infinity;
  for (final part in _durationPart.allMatches(value)) {
    if (part.start != end) return null;
    final unit = switch (part.group(2)) {
      'd' => Duration.millisecondsPerDay,
      'h' => Duration.millisecondsPerHour,
      'm' => Duration.millisecondsPerMinute,
      's' => Duration.millisecondsPerSecond,
      _ => 1,
    };
    if (unit >= previousUnit) return null;
    previousUnit = unit.toDouble();
    final amount = double.tryParse(part.group(1)!);
    if (amount == null || !amount.isFinite) return null;
    milliseconds += amount * unit;
    end = part.end;
  }
  if (end != value.length ||
      end == 0 ||
      !milliseconds.isFinite ||
      milliseconds > const Duration(days: 7).inMilliseconds) {
    return null;
  }
  return Duration(milliseconds: milliseconds.ceil());
}

String? _oauthIdentityLabel(Map<String, dynamic> identity) {
  final base =
      _text(identity['email']) ??
      _text(identity['accountId']) ??
      _text(identity['projectId']);
  if (base == null) return null;
  final org = _text(identity['orgName']) ?? _text(identity['orgId']);
  return (org == null || org == base ? base : '$base · $org').toLowerCase();
}

UsageAccount _makeAccount(
  String provider,
  String key,
  Map<String, dynamic> identity, {
  List<UsageLimit> limits = const [],
  DateTime? fetchedAt,
  String? plan,
  int? resetSeatCount,
  DateTime? soonestResetSeatExpiresAt,
  DateTime? resetCreditsFetchedAt,
  DateTime? oauthReloginEstimatedAt,
  DateTime? oauthReminderFetchedAt,
  String? issue,
  bool disabled = false,
}) => UsageAccount(
  key: key,
  provider: provider,
  displayName: provider,
  email: _text(identity['email']),
  accountId: _text(identity['accountId']),
  orgId: _text(identity['orgId']),
  projectId: _text(identity['projectId']),
  orgName: _text(identity['orgName']),
  plan: plan,
  resetSeatCount: resetSeatCount,
  soonestResetSeatExpiresAt: soonestResetSeatExpiresAt,
  resetCreditsFetchedAt: resetCreditsFetchedAt,
  oauthReloginEstimatedAt: oauthReloginEstimatedAt,
  oauthReminderFetchedAt: oauthReminderFetchedAt,
  issue: issue,
  fetchedAt: fetchedAt,
  limits: limits,
  disabled: disabled,
  identityKnown: _identityKnown(identity),
);

List<UsageLimit> _uniqueLimits(List<UsageLimit> limits) {
  final seen = <String>{};
  final result = <UsageLimit>[];
  for (final limit in limits) {
    final data = limit.toJson();
    data.remove('label');
    data.remove('fetchedAt');
    if (limit.shared && limit.sharedGroup != null) {
      data['id'] = limit.sharedGroup;
    }
    if (seen.add(jsonEncode(data))) result.add(limit);
  }
  return result;
}

void _mergeReportedAccount(List<UsageAccount> accounts, UsageAccount next) {
  final index = accounts.indexWhere((account) => account.key == next.key);
  if (index < 0) {
    accounts.add(next);
    return;
  }
  final previous = accounts[index];
  // Repeated observations are not extra subscriptions. Keep independent resources,
  // replacing a repeated meter with its newest observation rather than adding it.
  final nextIsNewer =
      previous.fetchedAt == null ||
      (next.fetchedAt != null &&
          !next.fetchedAt!.isBefore(previous.fetchedAt!));
  final newest = nextIsNewer ? next : previous;
  // Reset credits belong to their own report observation, not the oldest meter.
  final oldCreditsTime = previous.resetCreditsFetchedAt;
  final newCreditsTime = next.resetCreditsFetchedAt;
  final newestCredits =
      oldCreditsTime == null ||
          (newCreditsTime != null && !newCreditsTime.isBefore(oldCreditsTime))
      ? next
      : previous;
  final oldOAuthTime = previous.oauthReminderFetchedAt;
  final newOAuthTime = next.oauthReminderFetchedAt;
  final newestOAuth =
      oldOAuthTime == null ||
          (newOAuthTime != null && !newOAuthTime.isBefore(oldOAuthTime))
      ? next
      : previous;
  // The account age is conservative; each meter retains its own observation time.
  final limits = <String, UsageLimit>{
    for (final item in previous.limits) item.id: item,
  };
  for (final item in next.limits) {
    final existing = limits[item.id];
    final oldTime = existing?.fetchedAt ?? previous.fetchedAt;
    final newTime = item.fetchedAt ?? next.fetchedAt;
    if (existing == null ||
        oldTime == null ||
        (newTime != null && !newTime.isBefore(oldTime))) {
      limits[item.id] = item;
    }
  }
  DateTime? retainedAt = newest.fetchedAt;
  for (final item in limits.values) {
    if (item.fetchedAt == null) {
      retainedAt = null;
      break;
    }
    if (retainedAt == null || item.fetchedAt!.isBefore(retainedAt)) {
      retainedAt = item.fetchedAt;
    }
  }
  accounts[index] = UsageAccount(
    key: newest.key,
    provider: newest.provider,
    displayName: newest.displayName,
    email: newest.email,
    accountId: newest.accountId,
    orgId: newest.orgId,
    projectId: newest.projectId,
    orgName: newest.orgName,
    plan: newest.plan,
    resetSeatCount: newestCredits.resetSeatCount,
    soonestResetSeatExpiresAt: newestCredits.soonestResetSeatExpiresAt,
    resetCreditsFetchedAt: newestCredits.resetCreditsFetchedAt,
    oauthReloginEstimatedAt: newestOAuth.oauthReloginEstimatedAt,
    oauthReminderFetchedAt: newestOAuth.oauthReminderFetchedAt,
    issue: newest.issue,
    fetchedAt: retainedAt,
    limits: _uniqueLimits(limits.values.toList()),
    disabled: newest.disabled,
    identityKnown: newest.identityKnown,
  );
}

String? _text(dynamic value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
Map<String, dynamic>? _map(dynamic value) =>
    value is Map<String, dynamic> ? value : null;
Map<String, dynamic> _requiredMap(dynamic value) =>
    _map(value) ?? (throw const _SafeException('資料格式損壞或不受支援。'));
String _requiredString(Map<String, dynamic> json, String field) =>
    _text(json[field]) ?? (throw const _SafeException('資料缺少必要的識別欄位。'));
String? _optionalString(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value != null && value is! String) {
    throw const _SafeException('資料文字欄位格式損壞。');
  }
  return value as String?;
}

double? _finiteNumber(dynamic value) {
  if (value is! num) return null;
  final number = value.toDouble();
  return number.isFinite && number >= 0 ? number : null;
}

double? _storedNumber(Map<String, dynamic> json, String field) {
  final value = json[field];
  final number = _finiteNumber(value);
  if (value != null && number == null) throw const _SafeException('快取數值格式損壞。');
  return number;
}

DateTime? _epochMilliseconds(dynamic value) {
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    return null;
  }
  try {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  } catch (_) {
    return null;
  }
}

DateTime? _storedDate(dynamic value) {
  if (value == null) return null;
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) throw const _SafeException('快取時間格式損壞。');
  return date.toUtc();
}

Duration? _duration(dynamic value) {
  if (value == null) return null;
  if (value is! int || value < 0 || value >= 8640000000000000) {
    throw const _SafeException('快取窗口長度格式損壞。');
  }
  return Duration(milliseconds: value);
}

bool _bool(Map<String, dynamic> json, String field, bool fallback) {
  final value = json[field];
  if (value == null) return fallback;
  if (value is! bool) throw const _SafeException('設定布林欄位格式損壞。');
  return value;
}

int _integer(Map<String, dynamic> json, String field, int fallback) {
  final value = json[field];
  if (value == null) return fallback;
  if (value is! int || value < 0) throw const _SafeException('設定整數欄位格式損壞。');
  return value;
}

List<dynamic> _list(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is! List) throw const _SafeException('資料清單格式損壞。');
  return value;
}

List<String> _strings(Map<String, dynamic> json, String field) =>
    _list(json, field).map((value) {
      if (value is! String) throw const _SafeException('設定清單欄位格式損壞。');
      return value;
    }).toList();
T _enumValue<T extends Enum>(List<T> values, dynamic value, T fallback) {
  if (value == null) return fallback;
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw const _SafeException('設定選項格式損壞或版本不受支援。');
}

void _cacheSchema(Map<String, dynamic> json) {
  if (json['schemaVersion'] != 1) throw const _SafeException('儲存資料版本不受支援。');
}

double _nonnegative(double value) => value < 0 ? 0 : value;
String _numberText(double value, {bool precise = false}) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  if (precise) return value.toString();
  if (value > 0 && value < 0.05) return '<0.1';
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

class _SafeException implements Exception {
  const _SafeException(this.message);
  final String message;
  @override
  String toString() => message;
}
