import 'package:any_usage_pin/controller.dart';
import 'package:any_usage_pin/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final observed = DateTime.utc(2026, 10, 4, 8);
  late UsageController controller;

  setUp(() {
    controller = UsageController()..now = observed;
  });
  tearDown(() => controller.dispose());

  Map<String, Object?> project(List<UsageLimit> limits) {
    controller.preferences = Preferences(
      layout: PanelLayout.focus,
      accountPreferences: {
        'member': AccountPreference(
          hiddenLimitIds: limits.map((limit) => limit.id).toList(),
        ),
      },
    );
    controller.snapshot = UsageSnapshot(
      generatedAt: observed,
      coverageNote: '',
      accounts: [
        UsageAccount(
          key: 'member',
          provider: 'anthropic',
          displayName: 'Claude',
          identityKnown: true,
          fetchedAt: observed,
          limits: limits,
        ),
      ],
    );
    return (controller.panelView()['accounts'] as List).single
        as Map<String, Object?>;
  }

  Map<String, Object?>? resetSeats({
    int? count = 3,
    DateTime? expiry,
    DateTime? fetchedAt,
    String provider = 'anthropic',
  }) {
    controller.snapshot = UsageSnapshot(
      generatedAt: observed,
      coverageNote: '',
      accounts: [
        UsageAccount(
          key: 'member',
          provider: provider,
          displayName: 'Member',
          identityKnown: true,
          fetchedAt: observed,
          resetSeatCount: count,
          soonestResetSeatExpiresAt: expiry,
          resetCreditsFetchedAt: fetchedAt ?? observed,
          limits: const [],
        ),
      ],
    );
    return (controller.panelView()['accounts'] as List).single['resetSeats']
        as Map<String, Object?>?;
  }

  test(
    'OMP countdown changes from unstarted to running without refilling quota',
    () {
      UsageSnapshot snapshot(DateTime? reset) => UsageSnapshot.fromOmpJson({
        'generatedAt': observed.millisecondsSinceEpoch,
        'reports': [
          {
            'provider': 'anthropic',
            'fetchedAt': observed.millisecondsSinceEpoch,
            'metadata': {'email': 'member@example.invalid'},
            'status': 'ok',
            'limits': [
              {
                'id': 'session',
                'label': 'Five hour',
                'status': 'ok',
                'window': {
                  'durationMs': const Duration(hours: 5).inMilliseconds,
                  'resetsAt': ?reset?.millisecondsSinceEpoch,
                },
                'amount': {'unit': 'percent', 'remaining': 75},
              },
            ],
          },
        ],
      });
      controller.snapshot = snapshot(null);
      final pin = PinPreference(
        id: 'session-pin',
        accountKey: controller.snapshot!.accounts.single.key,
        top: const PinLayer(
          text: PinMetric(limitId: 'session', mode: LayerMode.reset),
          bar: PinMetric(limitId: 'session', mode: LayerMode.reset),
        ),
      );
      Map<String, Object?> row() =>
          (controller.pinView(pin)['layers'] as List).single
              as Map<String, Object?>;
      expect(row()['text'], '5時0分');
      expect(row()['fraction'], 1);
      expect(row()['status'], 'ok');
      final account =
          (controller.panelView()['accounts'] as List).single as Map;
      expect((account['limits'] as List).single['reset'], '尚未開始計時 · 5時0分');

      controller.now = observed.add(const Duration(seconds: 30));
      expect(row()['text'], '5時0分');
      expect(row()['fraction'], 1);
      expect(row()['status'], 'ok');

      controller.now = observed;
      controller.snapshot = snapshot(observed.add(const Duration(hours: 2)));
      expect(row()['text'], '2時0分');
      expect(row()['fraction'], .4);
      expect(row()['status'], 'ok');

      controller.now = observed.add(const Duration(hours: 2));
      expect(row()['text'], '待更新');
      expect(row()['fraction'], 0);
      expect(row()['status'], 'stale');
      expect(
        controller.snapshot!.accounts.single.limits.single.fraction(
          LayerMode.remaining,
        ),
        .75,
      );
    },
  );

  test('hidden meters reappear at reset deadline without refilling quota', () {
    final account = project([
      UsageLimit(
        id: 'healthy',
        label: 'Weekly',
        status: 'ok',
        unit: 'percent',
        remaining: 80,
        resetsAt: observed.add(const Duration(days: 1)),
      ),
      UsageLimit(
        id: 'due',
        label: 'Session',
        status: 'ok',
        unit: 'percent',
        remaining: 12,
        resetsAt: observed,
      ),
    ]);
    final limits = account['limits'] as List;
    expect(limits.map((limit) => limit['id']), ['due']);
    expect(limits.single['status'], 'stale');
    expect(limits.single['fraction'], .12);
    expect(account['needsAttention'], isTrue);
    expect(account['pinned'], isFalse);
  });

  test(
    'hidden missing and errored meters cannot disappear from focus warnings',
    () {
      final account = project([
        UsageLimit(
          id: 'missing',
          label: 'Session',
          status: 'ok',
          resetsAt: observed.add(const Duration(hours: 1)),
        ),
        const UsageLimit(id: 'failed', label: 'Weekly', status: 'error'),
      ]);
      final limits = account['limits'] as List;
      expect(limits.map((limit) => limit['id']), ['missing', 'failed']);
      expect(limits.map((limit) => limit['status']), ['missing', 'error']);
      expect(limits.first['fraction'], isNull);
      expect(account['needsAttention'], isTrue);
    },
  );

  test('meter observation age overrides a fresh account observation', () {
    final account = project([
      UsageLimit(
        id: 'old',
        label: 'Session',
        status: 'ok',
        unit: 'percent',
        remaining: 30,
        fetchedAt: observed.subtract(const Duration(minutes: 10)),
      ),
      const UsageLimit(
        id: 'fresh',
        label: 'Weekly',
        status: 'ok',
        unit: 'percent',
        remaining: 90,
      ),
    ]);
    final limits = account['limits'] as List;
    expect(limits.map((limit) => limit['id']), ['old']);
    expect(limits.single['status'], 'stale');
    expect(account['needsAttention'], isTrue);
  });

  test('reset seat urgency advances at seven days, three days and expiry', () {
    final expiry = observed.add(const Duration(days: 8));
    for (final (remaining, status) in [
      (const Duration(days: 7, microseconds: 1), 'normal'),
      (const Duration(days: 7), 'warning'),
      (const Duration(days: 3, microseconds: 1), 'warning'),
      (const Duration(days: 3), 'urgent'),
      (const Duration(microseconds: 1), 'urgent'),
      (Duration.zero, 'expired'),
      (const Duration(minutes: -1), 'expired'),
    ]) {
      controller.now = expiry.subtract(remaining);
      final seats = resetSeats(expiry: expiry)!;
      expect(seats['status'], status, reason: '$remaining');
      expect(seats['count'], '3');
      expect(controller.snapshot!.accounts.single.resetSeatCount, 3);
      expect(
        (seats['countdown'] as String).contains('待來源更新'),
        status == 'expired',
      );
    }
  });

  test('reset seat countdown stays positive immediately before expiry', () {
    for (final (remaining, countdown) in [
      (const Duration(days: 2, hours: 3), '2天3時後到期'),
      (const Duration(hours: 2, minutes: 7), '2時7分後到期'),
      (const Duration(minutes: 1), '1分後到期'),
      (const Duration(seconds: 59), '不到 1 分鐘後到期'),
      (const Duration(microseconds: 1), '不到 1 分鐘後到期'),
    ]) {
      final seats = resetSeats(expiry: observed.add(remaining))!;
      expect(seats['countdown'], countdown);
    }
  });

  test('available reset seats retain their count when expiry is unknown', () {
    final undated = resetSeats()!;
    expect(undated['status'], 'missing');
    expect(undated['count'], '3');
    expect(undated['countdown'], '到期時間未知');
  });

  test(
    'missing and zero reset seat counts hide the block for Claude and Codex',
    () {
      for (final provider in ['anthropic', 'openai-codex']) {
        for (final count in [null, 0]) {
          expect(resetSeats(provider: provider, count: count), isNull);
          expect(
            resetSeats(
              provider: provider,
              count: count,
              expiry: observed.add(const Duration(hours: 1)),
            ),
            isNull,
          );
        }
      }
    },
  );

  test('stale reset credits retain expiry urgency and source seat count', () {
    final seats = resetSeats(
      provider: 'openai-codex',
      expiry: observed.add(const Duration(hours: 3)),
      fetchedAt: observed.subtract(const Duration(days: 1)),
    )!;
    expect(seats['status'], 'urgent');
    expect(seats['count'], '3');
    expect(seats['countdown'], '3時後到期 · 舊資料');
  });

  test(
    'OAuth reminders stay separate from healthy quota status and count down',
    () {
      final deadline = observed.add(const Duration(days: 6, hours: 8));
      controller.snapshot = UsageSnapshot(
        generatedAt: observed,
        coverageNote: '',
        accounts: [
          UsageAccount(
            key: 'member',
            provider: 'anthropic',
            displayName: 'Claude',
            identityKnown: true,
            fetchedAt: observed,
            oauthReloginEstimatedAt: deadline,
            oauthReminderFetchedAt: observed,
            limits: [
              UsageLimit(
                id: 'session',
                label: 'Session',
                status: 'ok',
                unit: 'percent',
                remaining: 75,
                resetsAt: observed.add(const Duration(hours: 2)),
              ),
            ],
          ),
        ],
      );
      Map<String, Object?> account() =>
          (controller.panelView()['accounts'] as List).single
              as Map<String, Object?>;
      expect(account()['warning'], '⚠ OAuth · 約6天8時內重新登入');
      expect(account()['needsAttention'], isTrue);
      expect((account()['limits'] as List).single['status'], 'ok');
      expect((account()['limits'] as List).single['fraction'], .75);

      controller.now = observed.add(const Duration(hours: 1));
      expect(account()['warning'], '⚠ OAuth · 約6天7時內重新登入 · 舊資料');
      controller.now = deadline;
      expect(account()['warning'], '⚠ OAuth · 請重新登入 · 舊資料');
    },
  );

  test('a renewed OAuth grant removes the reminder from the panel', () {
    Map<String, Object?> account(String text) {
      controller.snapshot = UsageSnapshot.fromOmpJson({
        'generatedAt': observed.millisecondsSinceEpoch,
        'reports': [
          {
            'provider': 'anthropic',
            'fetchedAt': observed.millisecondsSinceEpoch,
            'metadata': {'email': 'member@example.invalid'},
            'limits': [
              {
                'id': 'session',
                'status': 'ok',
                'amount': {'unit': 'percent', 'remaining': 75},
                'window': {
                  'resetsAt': observed
                      .add(const Duration(hours: 2))
                      .millisecondsSinceEpoch,
                },
              },
            ],
          },
        ],
      }, anthropicUsageText: text);
      return (controller.panelView()['accounts'] as List).single
          as Map<String, Object?>;
    }

    final warned = account(
      '  ⚠ member@example.invalid — re-login within 6d8h '
      '(Anthropic expires OAuth grants ~30d after login)',
    );
    expect(warned['needsAttention'], isTrue);
    final renewed = account('');
    expect(renewed['warning'], isNull);
    expect(renewed['needsAttention'], isFalse);
  });
}
