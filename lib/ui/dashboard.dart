import 'dart:async';

import 'package:flutter/material.dart';

import '../controller.dart';
import '../core.dart';
import 'customize.dart';
import 'widgets.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.controller});
  final UsageController controller;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool _customizing = false;
  bool _expandedFocus = false;

  Future<void> _pinAccount(UsageAccount account) async {
    final pin = await editPin(context, widget.controller, account: account);
    if (pin == null || !mounted) return;
    await widget.controller.applyPreferences(
      widget.controller.preferences.copyWith(
        pins: [...widget.controller.preferences.pins, pin],
      ),
    );
  }

  Future<void> _settings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => SourceSettings(controller: widget.controller),
    );
  }

  Future<void> _resetSettings() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重設無法讀取的顯示設定？'),
        content: const Text(
          '只會替換此 app 的顯示設定；不會更動 OMP 的登入或 token。原 pins、別名與版型設定將被清除。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('重設設定'),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.controller.resetUnreadablePreferences();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final prefs = controller.preferences;
    if (_customizing) {
      return CustomizePage(
        controller: controller,
        onClose: () => setState(() => _customizing = false),
      );
    }
    final accounts = controller.orderedAccounts();
    final pinnedKeys = prefs.pins.map((p) => p.accountKey).toSet();
    final focusing = prefs.layout == PanelLayout.focus && !_expandedFocus;
    final visible = focusing
        ? accounts.where((a) => pinnedKeys.contains(a.key)).toList()
        : accounts;
    final unpinnedProblems = accounts
        .where(
          (a) =>
              !pinnedKeys.contains(a.key) &&
              (a.disabled ||
                  a.issue != null ||
                  a.limits.isEmpty ||
                  a.limits.any((l) => l.status != 'ok')),
        )
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 35,
                    height: 35,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.stacked_bar_chart_rounded,
                      size: 24,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AnyUsagePin',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          '把 agent 訂閱額度釘在選單列',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '來源與 app 設定',
                    onPressed: _settings,
                    icon: const Icon(Icons.settings_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: '隱藏面板',
                    onPressed: () => controller.desktop.hide(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.terminal, size: 15),
                        const SizedBox(width: 7),
                        const Text('Agent', style: TextStyle(fontSize: 11)),
                        const SizedBox(width: 9),
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value:
                                controller.agentIds.contains(
                                  prefs.selectedAgent,
                                )
                                ? prefs.selectedAgent
                                : null,
                            hint: const Text('請選擇'),
                            isDense: true,
                            style: Theme.of(context).textTheme.labelLarge,
                            items: const [
                              DropdownMenuItem(
                                value: 'omp',
                                child: Text('OMP'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value != null &&
                                  value != prefs.selectedAgent) {
                                unawaited(
                                  controller.applyPreferences(
                                    prefs.copyWith(selectedAgent: value),
                                  ),
                                );
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${accounts.length} 個帳號 · ${prefs.pins.length} 個 pins',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _customizing = true),
                    icon: const Icon(Icons.tune, size: 17),
                    label: const Text('客製化'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Profile（只讀）：${controller.profile}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Spacer(),
                  if (controller.loading)
                    const Padding(
                      padding: EdgeInsets.only(right: 7),
                      child: SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                    ),
                  Text(
                    controller.loading ? '向 OMP 查詢中' : '每 5 分鐘查詢',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: controller.initialized
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  children: [
                    if (controller.error != null) ...[
                      Notice(
                        '${controller.error!}${controller.snapshot == null ? '' : '\n保留上次已知資料；來源更新時間未重設。'}',
                        error: true,
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (controller.storageError != null) ...[
                      Notice(
                        controller.storageError!,
                        error: true,
                        action: controller.preferencesWritable
                            ? null
                            : TextButton(
                                onPressed: _resetSettings,
                                child: const Text('重設'),
                              ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (prefs.pins.isNotEmpty) ...[
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          for (final pin in prefs.pins)
                            PinPreview(controller.pinView(pin)),
                        ],
                      ),
                      const SizedBox(height: 15),
                    ] else ...[
                      Surface(
                        child: Row(
                          children: [
                            Icon(
                              Icons.push_pin_outlined,
                              size: 25,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '先挑選要關注的訂閱帳號',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    '自己與朋友的帳號可以分別釘選，每個最多兩層。',
                                    style: TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 15),
                    ],
                    if (prefs.layout == PanelLayout.focus &&
                        controller.snapshot != null) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _expandedFocus ? '已展開全部帳號' : '只顯示釘選帳號',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(
                              () => _expandedFocus = !_expandedFocus,
                            ),
                            child: Text(_expandedFocus ? '收起全部' : '展開全部帳號'),
                          ),
                        ],
                      ),
                      if (!_expandedFocus && unpinnedProblems.isNotEmpty)
                        Notice(
                          '${unpinnedProblems.length} 個未釘選帳號需注意：${unpinnedProblems.map((a) => '${providerName(a.provider)} · ${controller.accountLabel(a)}').join('、')}。請展開全部帳號查看。',
                          error: true,
                        ),
                      const SizedBox(height: 8),
                    ],
                    if (controller.snapshot == null)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Column(
                          children: [
                            Icon(
                              controller.loading ? Icons.sync : Icons.terminal,
                              size: 36,
                              color: Theme.of(context).colorScheme.outline,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              controller.loading
                                  ? '正在讀取 OMP 的訂閱用量…'
                                  : '目前沒有可顯示的 OMP 用量',
                            ),
                            const SizedBox(height: 7),
                            const Text(
                              '請先在 OMP 登入訂閱；本 app 不保管 provider 登入資訊。',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      )
                    else if (visible.isEmpty)
                      Notice(
                        prefs.layout == PanelLayout.focus
                            ? '聚焦版型只顯示已釘選的帳號。請新增 pin，或改回帳號卡片。'
                            : 'OMP 未回報可查詢的帳號。CLI 不保證列出所有已登入的 provider。',
                      )
                    else ...[
                      SectionHeading(
                        focusing ? '釘選帳號' : '訂閱帳號',
                        trailing: Text(
                          '剩餘配額',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                      for (final account in visible)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: prefs.dense ? 8 : 12,
                          ),
                          child: AccountCard(
                            controller: controller,
                            account: account,
                            table: prefs.layout == PanelLayout.table,
                            onPin: account.identityKnown
                                ? () => _pinAccount(account)
                                : null,
                          ),
                        ),
                    ],
                    const SizedBox(height: 6),
                    Notice(
                      controller.snapshot?.coverageNote ??
                          '只查詢目前選取的 OMP；不讀原生 Codex、Claude 或其他 provider app 的登入。',
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '不同帳號、窗口、共用資源與單位不合併加總。重置期限到了只代表待更新，不推測配額已補滿。',
                      style: TextStyle(fontSize: 11, height: 1.5),
                    ),
                  ],
                )
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 7, 12, 7),
          child: Row(
            children: [
              Icon(
                controller.error != null
                    ? Icons.warning_amber_rounded
                    : Icons.check_circle_outline,
                size: 14,
                color: controller.error != null
                    ? Colors.orange
                    : Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  controller.snapshot == null
                      ? '等待來源資料'
                      : '快照 ${ageText(controller.snapshot!.generatedAt, controller.now)} · 各帳號時間見卡片',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                onPressed: controller.loading || !controller.initialized
                    ? null
                    : () => controller.refresh(),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('更新'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AccountCard extends StatelessWidget {
  const AccountCard({
    super.key,
    required this.controller,
    required this.account,
    required this.table,
    this.onPin,
  });
  final UsageController controller;
  final UsageAccount account;
  final bool table;
  final VoidCallback? onPin;

  @override
  Widget build(BuildContext context) {
    final prefs = controller.preferences;
    final hidden =
        prefs.accountPreferences[account.key]?.hiddenLimitIds.toSet() ??
        const <String>{};
    final limits = account.limits
        .where(
          (limit) =>
              !hidden.contains(limit.id) ||
              controller.limitStatus(account, limit) != 'ok',
        )
        .toList();
    final count = prefs.pins.where((p) => p.accountKey == account.key).length;
    final stale = controller.accountStale(account);
    return Surface(
      padding: EdgeInsets.all(prefs.dense ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProviderMark(account.provider, size: prefs.dense ? 28 : 33),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          providerName(account.provider),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        if (account.plan?.isNotEmpty ?? false) ...[
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              account.plan!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    SelectableText(
                      controller.accountLabel(account),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: onPin,
                icon: Icon(
                  count > 0 ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 14,
                ),
                label: Text(count > 0 ? '新增 · $count' : '釘選'),
              ),
            ],
          ),
          if (account.orgName?.isNotEmpty ?? false)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                '組織：${account.orgName}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 5),
            child: Row(
              children: [
                Icon(
                  stale ? Icons.schedule : Icons.history,
                  size: 12,
                  color: stale
                      ? Colors.orange.shade800
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 5),
                Text(
                  '${stale ? '舊資料 · ' : ''}${ageText(account.fetchedAt, controller.now)}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (account.fetchedAt != null)
                  Tooltip(
                    message: account.fetchedAt!.toLocal().toString(),
                    child: const Padding(
                      padding: EdgeInsets.only(left: 5),
                      child: Icon(Icons.info_outline, size: 11),
                    ),
                  ),
              ],
            ),
          ),
          if (account.issue != null || account.disabled)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Notice(
                account.issue ?? 'OMP 已停用此憑證；請到 OMP 處理登入。',
                error: true,
              ),
            ),
          if (!account.identityKnown)
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Notice('來源缺少可靠身份，不能建立持久 pin，避免錯綁到另一個帳號。', error: true),
            ),
          if (account.limits.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 9),
              child: Text(
                '沒有可用的配額資料。此處不代表 0% 或無限制。',
                style: TextStyle(fontSize: 12),
              ),
            )
          else if (limits.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 9),
              child: Text('此帳號的一般窗口已在顯示設定隱藏。', style: TextStyle(fontSize: 12)),
            )
          else if (table) ...[
            const SizedBox(height: 8),
            const Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text('窗口', style: TextStyle(fontSize: 10)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('剩餘', style: TextStyle(fontSize: 10)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('重置倒數', style: TextStyle(fontSize: 10)),
                ),
              ],
            ),
            const Divider(height: 12),
            for (final limit in limits)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: Text(
                        '${limit.label}${limit.shared ? ' · 共用' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        limit.valueText(
                          LayerMode.remaining,
                          controller.now,
                          raw: prefs.rawValues,
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        limit.valueText(LayerMode.reset, controller.now),
                        style: TextStyle(
                          fontSize: 11,
                          color: controller.limitStatus(account, limit) == 'ok'
                              ? null
                              : Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ] else
            for (final limit in limits)
              _LimitRow(controller: controller, account: account, limit: limit),
        ],
      ),
    );
  }
}

class _LimitRow extends StatelessWidget {
  const _LimitRow({
    required this.controller,
    required this.account,
    required this.limit,
  });
  final UsageController controller;
  final UsageAccount account;
  final UsageLimit limit;
  @override
  Widget build(BuildContext context) {
    final prefs = controller.preferences;
    final remaining = limit.fraction(LayerMode.remaining);
    final resetPassed =
        limit.resetsAt != null && !controller.now.isBefore(limit.resetsAt!);
    final status = controller.limitStatus(account, limit);
    final color = remaining != null && remaining <= .1
        ? Colors.red.shade600
        : remaining != null && remaining <= .25
        ? Colors.orange.shade700
        : providerColor(account.provider);
    return Padding(
      padding: EdgeInsets.only(top: prefs.dense ? 10 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${limit.label}${limit.shared ? ' · 共用' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                limit.valueText(
                  LayerMode.remaining,
                  controller.now,
                  raw: prefs.rawValues,
                ),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: status == 'ok'
                      ? color
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (remaining != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: LinearProgressIndicator(
                value: remaining.clamp(0, 1),
                minHeight: 4,
                borderRadius: BorderRadius.circular(3),
                color: status == 'ok' ? color : color.withValues(alpha: .5),
                backgroundColor: color.withValues(alpha: .10),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              children: [
                Icon(
                  resetPassed ? Icons.schedule : Icons.restart_alt,
                  size: 11,
                  color: resetPassed
                      ? Colors.orange.shade800
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    limit.valueText(LayerMode.reset, controller.now),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ),
                if (status == 'error' && limit.status != 'ok')
                  Text(
                    '來源狀態：${limit.status}',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade800,
                    ),
                  ),
                if (resetPassed)
                  Text(
                    '待來源更新',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.orange.shade800,
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

class SourceSettings extends StatefulWidget {
  const SourceSettings({super.key, required this.controller});
  final UsageController controller;
  @override
  State<SourceSettings> createState() => _SourceSettingsState();
}

class _SourceSettingsState extends State<SourceSettings> {
  late TextEditingController _path;
  bool _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _path = TextEditingController(text: widget.controller.preferences.ompPath);
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('來源與 app 設定'),
    content: SizedBox(
      width: 470,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '目前支援 OMP。只向選取的 agent 查詢，沒有 provider 登入、帳號切換或 token 編輯功能。',
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _path,
              decoration: const InputDecoration(
                labelText: 'OMP CLI 路徑',
                hintText: '留空自動尋找，或輸入完整可執行檔路徑',
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              '目前解析：${widget.controller.executablePath ?? '尚未找到'}',
              style: const TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 14),
            Text('Profile（只讀）：${widget.controller.profile}'),
            const SizedBox(height: 7),
            const Text(
              'Profile 由啟動 app 的 OMP 環境決定，不是可切換的資料來源。',
              style: TextStyle(fontSize: 11),
            ),
            const SizedBox(height: 14),
            const Notice(
              '背景每 5 分鐘執行一次 omp usage --json；面板關閉仍會更新。正常刷新不清除 OMP 快取。CLI 可能依自身規則刷新 OAuth／更新快取，但本 app 不讀取或保存 bearer token。',
            ),
            const SizedBox(height: 12),
            const Text(
              '設定與白名單用量快照存於本機 Application Support/AnyUsagePin。沒有雲端同步或遙測。',
              style: TextStyle(fontSize: 11),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Notice(_error!, error: true),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => widget.controller.desktop.quit(),
        child: const Text('結束 app'),
      ),
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: _saving
            ? null
            : () async {
                setState(() => _saving = true);
                final saved = await widget.controller.applyPreferences(
                  widget.controller.preferences.copyWith(
                    ompPath: _path.text.trim(),
                  ),
                );
                if (!context.mounted) return;
                if (saved) {
                  Navigator.pop(context);
                } else {
                  setState(() {
                    _saving = false;
                    _error = widget.controller.storageError ?? '設定儲存失敗。';
                  });
                }
              },
        child: Text(_saving ? '儲存中…' : '套用'),
      ),
    ],
  );
}
