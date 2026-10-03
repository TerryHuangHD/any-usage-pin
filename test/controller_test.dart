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
}
