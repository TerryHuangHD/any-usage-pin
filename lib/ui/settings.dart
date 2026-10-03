import 'package:flutter/material.dart';

import '../controller.dart';
import '../native_bridge.dart';
import 'customize.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});
  final UsageController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _path = TextEditingController();
  String? _agent;
  bool _sourceLoaded = false;
  bool _customizing = false;
  bool _saving = false;
  String? _error;
  String? _savedMessage;

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  void _loadSource() {
    _path.text = widget.controller.preferences.ompPath;
    final agent = widget.controller.preferences.selectedAgent;
    _agent = widget.controller.agentIds.contains(agent) ? agent : null;
    _error = null;
    _savedMessage = null;
  }

  Future<void> _applySource() async {
    setState(() {
      _saving = true;
      _error = null;
      _savedMessage = null;
    });
    // Merge only source fields into current preferences, never a stale form snapshot.
    final saved = await widget.controller.applyPreferences(
      widget.controller.preferences.copyWith(
        selectedAgent: _agent,
        ompPath: _path.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) {
        _savedMessage = '來源設定已儲存。';
      } else {
        _error =
            widget.controller.storageError ??
            widget.controller.error ??
            '設定儲存失敗。';
      }
    });
  }

  Future<void> _setLaunchAtLogin(bool enabled) async {
    final saved = await widget.controller.setLaunchAtLogin(enabled);
    if (!mounted || !saved) return;
    setState(() {
      _savedMessage =
          widget.controller.launchAtLoginStatus ==
              LaunchAtLoginStatus.requiresApproval
          ? '已登記開機自動啟動；請在系統設定中允許。'
          : enabled
          ? '已開啟開機自動啟動。'
          : '已關閉開機自動啟動。';
    });
  }

  Future<void> _setRefreshInterval(int minutes) async {
    setState(() {
      _saving = true;
      _error = null;
      _savedMessage = null;
    });
    final saved = await widget.controller.applyPreferences(
      widget.controller.preferences.copyWith(refreshIntervalMinutes: minutes),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) {
        _savedMessage = '更新頻率已儲存：每 $minutes 分鐘。';
      } else {
        _error = widget.controller.storageError ?? '更新頻率儲存失敗，變更未套用。';
      }
    });
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
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    await widget.controller.resetUnreadablePreferences();
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (widget.controller.preferencesWritable) _loadSource();
    });
  }

  Widget _metadata(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 94,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!_sourceLoaded && controller.initialized) {
      _loadSource();
      _sourceLoaded = true;
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: !controller.initialized
            ? const Center(child: CircularProgressIndicator())
            : _customizing
            ? CustomizePage(
                controller: controller,
                onClose: () => setState(() => _customizing = false),
              )
            : Column(
                children: [
                  PageHeader(
                    title: '設定',
                    subtitle: '來源與 app 行為',
                    actions: [
                      OutlinedButton.icon(
                        onPressed: _saving || !controller.preferencesWritable
                            ? null
                            : () => setState(() => _customizing = true),
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('客製化顯示'),
                      ),
                    ],
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      children: [
                        if (controller.storageError != null) ...[
                          const SizedBox(height: 14),
                          Notice(controller.storageError!, error: true),
                          if (!controller.preferencesWritable)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: _saving ? null : _resetSettings,
                                icon: const Icon(Icons.restore, size: 16),
                                label: const Text('重設無法讀取的設定…'),
                              ),
                            ),
                        ],
                        const SectionHeading('資料來源'),
                        Surface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              DropdownButtonFormField<String>(
                                key: ValueKey(_agent),
                                dropdownColor: Theme.of(
                                  context,
                                ).colorScheme.surface,
                                initialValue: _agent,
                                decoration: const InputDecoration(
                                  labelText: 'Agent',
                                ),
                                hint: const Text('請選擇 OMP'),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'omp',
                                    child: Text('OMP'),
                                  ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (value) => setState(() {
                                        _agent = value;
                                        _savedMessage = null;
                                      }),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _path,
                                enabled: !_saving,
                                onChanged: (_) =>
                                    setState(() => _savedMessage = null),
                                decoration: const InputDecoration(
                                  labelText: 'OMP CLI 路徑',
                                  hintText: '留空自動尋找，或輸入完整可執行檔路徑',
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 8),
                              _metadata(
                                context,
                                '目前解析',
                                controller.executablePath ?? '尚未找到',
                              ),
                              _metadata(
                                context,
                                'Profile · 只讀',
                                controller.profile,
                              ),
                            ],
                          ),
                        ),
                        const SectionHeading('App 行為 · 變更即儲存'),
                        Surface(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('開機自動啟動'),
                                subtitle: Text(
                                  controller.launchAtLoginStatus ==
                                          LaunchAtLoginStatus.requiresApproval
                                      ? '等待系統允許；請到登入項目設定開啟。'
                                      : '登入此 Mac 時自動啟動，並在選單列背景執行。',
                                ),
                                value:
                                    controller.launchAtLoginStatus != null &&
                                    controller.launchAtLoginStatus !=
                                        LaunchAtLoginStatus.disabled,
                                onChanged:
                                    _saving ||
                                        controller.changingLaunchAtLogin ||
                                        controller.launchAtLoginStatus == null
                                    ? null
                                    : _setLaunchAtLogin,
                              ),
                              if (controller.launchAtLoginError != null) ...[
                                Notice(
                                  controller.launchAtLoginError!,
                                  error: true,
                                ),
                                TextButton(
                                  onPressed: controller.changingLaunchAtLogin
                                      ? null
                                      : controller.reloadLaunchAtLogin,
                                  child: const Text('重新讀取啟動設定'),
                                ),
                              ],
                              if (controller.launchAtLoginStatus ==
                                  LaunchAtLoginStatus.requiresApproval)
                                TextButton(
                                  onPressed: controller.openLoginItemSettings,
                                  child: const Text('開啟系統登入項目設定'),
                                ),
                              const Divider(height: 16),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Refresh 頻率'),
                                subtitle: const Text('1～10 分鐘；變更後立即套用背景排程。'),
                                trailing: DropdownButton<int>(
                                  value: controller
                                      .preferences
                                      .refreshIntervalMinutes,
                                  dropdownColor: Theme.of(
                                    context,
                                  ).colorScheme.surface,
                                  items: [
                                    for (
                                      var minutes = 1;
                                      minutes <= 10;
                                      minutes++
                                    )
                                      DropdownMenuItem(
                                        value: minutes,
                                        child: Text('$minutes 分鐘'),
                                      ),
                                  ],
                                  onChanged:
                                      _saving || !controller.preferencesWritable
                                      ? null
                                      : (value) {
                                          if (value != null) {
                                            _setRefreshInterval(value);
                                          }
                                        },
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SectionHeading('資料與 app'),
                        Surface(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                shape: const Border(),
                                collapsedShape: const Border(),
                                leading: const Icon(
                                  Icons.storage_outlined,
                                  size: 18,
                                ),
                                title: const Text('來源與資料範圍'),
                                subtitle: const Text('只查詢選取的 agent，不合併配額'),
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '目前僅支援 OMP；沒有 provider 登入、帳號切換或 token 編輯功能。',
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'Profile 由啟動 app 的 OMP 環境決定，不是可切換的資料來源。',
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        controller.snapshot?.coverageNote ??
                                            '只查詢目前選取的 OMP；不讀原生 Codex、Claude 或其他 provider app 的登入。',
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        '不同帳號、窗口、共用資源與單位不合併加總。重置期限到了只代表待更新，不推測配額已補滿。',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 1),
                              ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                childrenPadding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                shape: const Border(),
                                collapsedShape: const Border(),
                                leading: const Icon(
                                  Icons.privacy_tip_outlined,
                                  size: 18,
                                ),
                                title: const Text('背景更新與隱私'),
                                subtitle: Text(
                                  '每 ${controller.preferences.refreshIntervalMinutes} 分鐘更新 · 僅本機儲存',
                                ),
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '背景每 ${controller.preferences.refreshIntervalMinutes} 分鐘執行一次 omp usage --json；面板及設定視窗關閉仍會更新。正常刷新不清除 OMP 快取。CLI 可能依自身規則刷新 OAuth／更新快取，但本 app 不讀取或保存 bearer token。',
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        '設定與白名單用量快照存於本機 Application Support/AnyUsagePin。沒有雲端同步或遙測。',
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  10,
                                  12,
                                  10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '關閉設定視窗不會停止背景更新。',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                    TextButton.icon(
                                      onPressed: _saving
                                          ? null
                                          : () => controller.desktop.quit(),
                                      icon: const Icon(
                                        Icons.power_settings_new,
                                        size: 16,
                                      ),
                                      label: const Text('結束 app'),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_error != null) ...[
                          Notice(_error!, error: true),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _savedMessage ??
                                    (_saving
                                        ? '正在儲存來源設定…'
                                        : '來源：${_agent?.toUpperCase() ?? '尚未選取'}'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: _saving
                                  ? null
                                  : () => setState(_loadSource),
                              child: const Text('取消變更'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed:
                                  _saving ||
                                      _agent == null ||
                                      !controller.preferencesWritable
                                  ? null
                                  : _applySource,
                              child: Text(_saving ? '儲存中…' : '套用來源'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
