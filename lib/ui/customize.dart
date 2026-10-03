import 'package:flutter/material.dart';

import '../controller.dart';
import '../core.dart';
import 'widgets.dart';

Future<PinPreference?> editPin(
  BuildContext context,
  UsageController controller, {
  PinPreference? pin,
  UsageAccount? account,
  Preferences? settings,
}) => showDialog<PinPreference>(
  context: context,
  builder: (_) => PinEditor(
    controller: controller,
    original: pin,
    account: account,
    settings: settings ?? controller.preferences,
  ),
);

class PinEditor extends StatefulWidget {
  const PinEditor({
    super.key,
    required this.controller,
    required this.settings,
    this.original,
    this.account,
  });
  final UsageController controller;
  final Preferences settings;
  final PinPreference? original;
  final UsageAccount? account;

  @override
  State<PinEditor> createState() => _PinEditorState();
}

class _PinEditorState extends State<PinEditor> {
  late String _accountKey;
  late String _id;
  late TextEditingController _label;
  late PinLayer? _top;
  late PinLayer? _bottom;
  late int _labelWidth;
  late bool _showIcon;
  late String _color;
  String? _error;

  @override
  void initState() {
    super.initState();
    final first =
        widget.account ??
        widget.controller.findAccount(widget.original?.accountKey ?? '') ??
        widget.controller
            .orderedAccounts()
            .where((a) => a.identityKnown)
            .firstOrNull;
    _accountKey = widget.original?.accountKey ?? first?.key ?? '';
    _id = widget.original?.id ?? 'pin-${DateTime.now().microsecondsSinceEpoch}';
    _label = TextEditingController(text: widget.original?.label ?? '');
    _top =
        widget.original?.top ??
        (widget.original == null && (first?.limits.isNotEmpty ?? false)
            ? PinLayer(
                text: PinMetric(
                  limitId: first!.limits.first.id,
                  mode: LayerMode.remaining,
                ),
              )
            : null);
    _bottom = widget.original?.bottom;
    _labelWidth = widget.original?.labelWidth ?? 0;
    _showIcon = widget.original?.showIcon ?? true;
    _color = widget.original?.color ?? 'auto';
    widget.controller.addListener(_refreshPreview);
  }

  PinPreference get _value => PinPreference(
    id: _id,
    accountKey: _accountKey,
    label: _label.text.trim(),
    top: _top,
    bottom: _bottom,
    labelWidth: _labelWidth,
    showIcon: _showIcon,
    color: _color,
  );
  void _refreshPreview() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_refreshPreview);
    _label.dispose();
    super.dispose();
  }

  Widget _metric(
    String title,
    PinMetric? metric,
    ValueChanged<PinMetric?> change, {
    required bool bar,
  }) {
    final limits =
        widget.controller.findAccount(_accountKey)?.limits ??
        const <UsageLimit>[];
    final currentMissing =
        metric != null && !limits.any((limit) => limit.id == metric.limitId);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: DropdownButtonFormField<String>(
            dropdownColor: Theme.of(context).colorScheme.surface,
            key: ValueKey('$title:$_accountKey:${metric?.limitId}'),
            initialValue: metric?.limitId ?? '',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '$title · 窗口',
              isDense: true,
            ),
            items: [
              DropdownMenuItem(value: '', child: Text(bar ? '不顯示條狀' : '不顯示文字')),
              if (currentMissing)
                DropdownMenuItem(
                  value: metric.limitId,
                  child: const Text('原窗口目前不可用'),
                ),
              for (final limit in limits)
                DropdownMenuItem(
                  value: limit.id,
                  child: Text(
                    '${limit.label}${limit.shared ? ' · 共用' : ''}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) => setState(
              () => change(
                id == null || id.isEmpty
                    ? null
                    : PinMetric(
                        limitId: id,
                        mode: metric?.mode ?? LayerMode.remaining,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<LayerMode>(
            dropdownColor: Theme.of(context).colorScheme.surface,
            key: ValueKey('$title:${metric?.mode}'),
            initialValue: metric?.mode ?? LayerMode.remaining,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '$title · 內容',
              isDense: true,
            ),
            items: [
              DropdownMenuItem(
                value: LayerMode.remaining,
                child: Text(bar ? '剩餘配額比例' : '剩餘配額'),
              ),
              DropdownMenuItem(
                value: LayerMode.used,
                child: Text(bar ? '已用配額比例' : '已用配額'),
              ),
              DropdownMenuItem(
                value: LayerMode.reset,
                child: Text(bar ? '剩餘時間比例' : '重置倒數'),
              ),
            ],
            onChanged: metric == null
                ? null
                : (mode) => setState(
                    () =>
                        change(PinMetric(limitId: metric.limitId, mode: mode!)),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _layer(String title, PinLayer? layer, ValueChanged<PinLayer?> change) {
    void update(PinLayer next) => change(next.isEmpty ? null : next);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 9),
        _metric(
          '$title文字',
          layer?.text,
          (value) => update(PinLayer(text: value, bar: layer?.bar)),
          bar: false,
        ),
        const SizedBox(height: 10),
        _metric(
          '$title條狀',
          layer?.bar,
          (value) => update(PinLayer(text: layer?.text, bar: value)),
          bar: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.controller
        .orderedAccounts(settings: widget.settings)
        .where((a) => a.identityKnown)
        .toList();
    final exists = accounts.any((a) => a.key == _accountKey);
    final view = widget.controller.pinView(_value, settings: widget.settings);
    return Dialog(
      child: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .82,
        child: Column(
          children: [
            PageHeader(
              title: widget.original == null ? '新增 pin' : '編輯 pin',
              subtitle: '單一帳號 · 最多兩層',
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 6),
                FilledButton(
                  onPressed: () {
                    if (_accountKey.isEmpty) {
                      setState(() => _error = '請選擇可可靠辨識的帳號。');
                      return;
                    }
                    if (!_showIcon &&
                        _top == null &&
                        _bottom == null &&
                        (_label.text.trim().isEmpty || _labelWidth == 0)) {
                      setState(() => _error = '至少需顯示圖示、資訊層或標籤。');
                      return;
                    }
                    Navigator.pop(context, _value);
                  },
                  child: const Text('完成'),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionHeading('訂閱帳號'),
                    Surface(
                      child: DropdownButtonFormField<String>(
                        dropdownColor: Theme.of(context).colorScheme.surface,
                        key: ValueKey(_accountKey),
                        initialValue: _accountKey.isEmpty ? null : _accountKey,
                        isExpanded: true,
                        itemHeight: null,
                        decoration: const InputDecoration(labelText: '帳號'),
                        items: [
                          if (!exists && _accountKey.isNotEmpty)
                            DropdownMenuItem(
                              value: _accountKey,
                              child: const Text('原帳號目前不可用（保留綁定）'),
                            ),
                          for (final account in accounts)
                            DropdownMenuItem(
                              value: account.key,
                              child: Text(
                                '${providerName(account.provider)} · ${widget.controller.accountLabel(account, settings: widget.settings)}',
                              ),
                            ),
                        ],
                        onChanged: (key) => setState(() {
                          _accountKey = key!;
                          final limits =
                              widget.controller.findAccount(key)?.limits ??
                              const <UsageLimit>[];
                          _top = limits.isEmpty
                              ? null
                              : PinLayer(
                                  text: PinMetric(
                                    limitId: limits.first.id,
                                    mode: LayerMode.remaining,
                                  ),
                                );
                          _bottom = null;
                        }),
                      ),
                    ),
                    const SectionHeading('資訊層'),
                    Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _layer('上層', _top, (value) => _top = value),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Divider(height: 1),
                          ),
                          _layer('下層', _bottom, (value) => _bottom = value),
                          const SizedBox(height: 12),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            shape: const Border(),
                            collapsedShape: const Border(),
                            title: const Text('資訊層與倒數條說明'),
                            children: const [
                              Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: Text(
                                  '每層的文字與條狀可各自選窗口及內容，也可各自關閉。兩層都關閉時可只保留圖示。\n\n倒數條顯示「距離重置的剩餘時間 ÷ 來源窗口長度」。缺少時間或長度時顯示 ?，不推算比例。',
                                  style: TextStyle(fontSize: 11, height: 1.4),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SectionHeading('共用外觀'),
                    Surface(
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            dropdownColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            initialValue:
                                [
                                  'auto',
                                  '#168575',
                                  '#4575CB',
                                  '#BF7045',
                                  '#8861B0',
                                ].contains(_color)
                                ? _color
                                : 'auto',
                            decoration: const InputDecoration(labelText: '顏色'),
                            items: const [
                              DropdownMenuItem(
                                value: 'auto',
                                child: Text('跟隨選單列'),
                              ),
                              DropdownMenuItem(
                                value: '#168575',
                                child: Text('綠色'),
                              ),
                              DropdownMenuItem(
                                value: '#4575CB',
                                child: Text('藍色'),
                              ),
                              DropdownMenuItem(
                                value: '#BF7045',
                                child: Text('橘色'),
                              ),
                              DropdownMenuItem(
                                value: '#8861B0',
                                child: Text('紫色'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _color = value!),
                          ),
                          SwitchListTile.adaptive(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('顯示 provider 圖示'),
                            value: _showIcon,
                            onChanged: (value) =>
                                setState(() => _showIcon = value),
                          ),
                          TextField(
                            controller: _label,
                            decoration: const InputDecoration(
                              labelText: '選單列標籤（可留空）',
                              hintText: '例如：自己、朋友、工作',
                            ),
                            onChanged: (value) => setState(() {
                              if (value.isNotEmpty && _labelWidth == 0) {
                                _labelWidth = 48;
                              }
                            }),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '標籤寬度：${_labelWidth == 0 ? '隱藏' : '$_labelWidth pt'}',
                              ),
                              Expanded(
                                child: Slider(
                                  value: _labelWidth.clamp(0, 120).toDouble(),
                                  max: 120,
                                  divisions: 30,
                                  onChanged: (value) => setState(
                                    () => _labelWidth = value.round(),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Surface(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '即時預覽 · 尚未套用',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: PinPreview(view),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Notice(_error!, error: true),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CustomizePage extends StatefulWidget {
  const CustomizePage({
    super.key,
    required this.controller,
    required this.onClose,
  });
  final UsageController controller;
  final VoidCallback onClose;

  @override
  State<CustomizePage> createState() => _CustomizePageState();
}

class _CustomizePageState extends State<CustomizePage> {
  late Preferences _draft;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final original = widget.controller.preferences;
    _draft = original.copyWith(
      pins: List.of(original.pins),
      accountOrder: List.of(original.accountOrder),
      accountPreferences: Map.of(original.accountPreferences),
    );
  }

  Future<void> _edit({PinPreference? pin}) async {
    final value = await editPin(
      context,
      widget.controller,
      pin: pin,
      settings: _draft,
    );
    if (value == null || !mounted) return;
    final pins = List<PinPreference>.of(_draft.pins);
    final index = pin == null ? -1 : pins.indexWhere((p) => p.id == pin.id);
    if (index < 0) {
      pins.add(value);
    } else {
      pins[index] = value;
    }
    setState(() => _draft = _draft.copyWith(pins: pins));
  }

  Future<void> _editAccount(UsageAccount account) async {
    final current =
        _draft.accountPreferences[account.key] ?? AccountPreference();
    final result = await showDialog<AccountPreference>(
      context: context,
      builder: (_) => AccountEditor(
        account: account,
        current: current,
        title: widget.controller.accountLabel(account, settings: _draft),
      ),
    );
    if (result == null || !mounted) return;
    setState(
      () => _draft = _draft.copyWith(
        accountPreferences: {..._draft.accountPreferences, account.key: result},
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    final success = await widget.controller.applyPreferences(
      widget.controller.preferences.copyWith(
        pins: _draft.pins,
        accountOrder: _draft.accountOrder,
        accountPreferences: _draft.accountPreferences,
        layout: _draft.layout,
        theme: _draft.theme,
        dense: _draft.dense,
        rawValues: _draft.rawValues,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (success) widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final accounts = controller.orderedAccounts(settings: _draft);
    return Column(
      children: [
        PageHeader(
          title: '客製化顯示',
          subtitle: '變更只會在按「套用」後儲存',
          leading: IconButton(
            tooltip: '返回來源設定並取消變更',
            onPressed: _saving ? null : widget.onClose,
            icon: const Icon(Icons.arrow_back, size: 18),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : widget.onClose,
              child: const Text('取消'),
            ),
            const SizedBox(width: 6),
            FilledButton(
              onPressed: _saving ? null : _apply,
              child: Text(_saving ? '儲存中…' : '套用'),
            ),
          ],
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              if (controller.storageError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Notice(controller.storageError!, error: true),
                ),
              SectionHeading(
                '選單列 pins · ${_draft.pins.length}',
                trailing: TextButton.icon(
                  onPressed: accounts.any((a) => a.identityKnown)
                      ? () => _edit()
                      : null,
                  icon: const Icon(Icons.add, size: 17),
                  label: const Text('新增 pin'),
                ),
              ),
              if (_draft.pins.isEmpty)
                const Surface(child: Text('尚未選擇 pins。可以加入自己與朋友的不同訂閱帳號。')),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: _draft.pins.length,
                onReorderItem: (oldIndex, newIndex) {
                  final pins = List<PinPreference>.of(_draft.pins);
                  pins.insert(newIndex, pins.removeAt(oldIndex));
                  setState(() => _draft = _draft.copyWith(pins: pins));
                },
                itemBuilder: (context, index) {
                  final pin = _draft.pins[index];
                  final account = controller.findAccount(pin.accountKey);
                  return Padding(
                    key: ValueKey(pin.id),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Surface(
                      padding: const EdgeInsets.all(10),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.drag_indicator, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  account == null
                                      ? '原帳號目前不可用'
                                      : '${providerName(account.provider)} · ${controller.accountLabel(account, settings: _draft)}',
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                                const SizedBox(height: 7),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: PinPreview(
                                    controller.pinView(pin, settings: _draft),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '編輯 pin',
                            onPressed: () => _edit(pin: pin),
                            icon: const Icon(Icons.edit_outlined, size: 18),
                          ),
                          IconButton(
                            tooltip: '移除 pin',
                            onPressed: () => setState(
                              () => _draft = _draft.copyWith(
                                pins: _draft.pins
                                    .where((p) => p.id != pin.id)
                                    .toList(),
                              ),
                            ),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Surface(
                padding: EdgeInsets.zero,
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  shape: const Border(),
                  collapsedShape: const Border(),
                  title: const Text('Pins 與排序說明'),
                  children: const [
                    Text(
                      '每個 pin 只屬於一個帳號，最多兩層；不會自動合併或收起 pins。拖曳調整順序。macOS 可能隱藏放不下的項目，但此處永遠保留完整設定。',
                      style: TextStyle(fontSize: 11, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SectionHeading('面板外觀'),
              Surface(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<PanelLayout>(
                            key: ValueKey(_draft.layout),
                            dropdownColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            initialValue: _draft.layout,
                            decoration: const InputDecoration(
                              labelText: '面板版型',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: PanelLayout.cards,
                                child: Text('帳號卡片'),
                              ),
                              DropdownMenuItem(
                                value: PanelLayout.table,
                                child: Text('緊湊表格'),
                              ),
                              DropdownMenuItem(
                                value: PanelLayout.focus,
                                child: Text('釘選帳號聚焦'),
                              ),
                            ],
                            onChanged: (value) => setState(
                              () => _draft = _draft.copyWith(layout: value),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<ThemeChoice>(
                            key: ValueKey(_draft.theme),
                            dropdownColor: Theme.of(
                              context,
                            ).colorScheme.surface,
                            initialValue: _draft.theme,
                            decoration: const InputDecoration(labelText: '主題'),
                            items: const [
                              DropdownMenuItem(
                                value: ThemeChoice.system,
                                child: Text('跟隨系統'),
                              ),
                              DropdownMenuItem(
                                value: ThemeChoice.light,
                                child: Text('淺色'),
                              ),
                              DropdownMenuItem(
                                value: ThemeChoice.dark,
                                child: Text('深色'),
                              ),
                            ],
                            onChanged: (value) => setState(
                              () => _draft = _draft.copyWith(theme: value),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('緊湊間距'),
                      value: _draft.dense,
                      onChanged: (value) => setState(
                        () => _draft = _draft.copyWith(dense: value),
                      ),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('顯示原始單位數值'),
                      subtitle: const Text(
                        '有明確原始數值時顯示美元、credits 等；不把不同單位混成總數。',
                      ),
                      value: _draft.rawValues,
                      onChanged: (value) => setState(
                        () => _draft = _draft.copyWith(rawValues: value),
                      ),
                    ),
                    const Divider(height: 1),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: _saving
                            ? null
                            : () => setState(
                                () => _draft = Preferences(
                                  selectedAgent: _draft.selectedAgent,
                                  ompPath: _draft.ompPath,
                                  theme: _draft.theme,
                                ),
                              ),
                        icon: const Icon(Icons.restore, size: 16),
                        label: const Text('恢復目前 agent 的顯示預設'),
                      ),
                    ),
                  ],
                ),
              ),
              const SectionHeading('帳號順序、別名與窗口顯示'),
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: accounts.length,
                onReorderItem: (oldIndex, newIndex) {
                  final keys = accounts.map((a) => a.key).toList();
                  keys.insert(newIndex, keys.removeAt(oldIndex));
                  setState(() => _draft = _draft.copyWith(accountOrder: keys));
                },
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  return Padding(
                    key: ValueKey(account.key),
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Surface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          ReorderableDragStartListener(
                            index: index,
                            child: const MouseRegion(
                              cursor: SystemMouseCursors.grab,
                              child: Padding(
                                padding: EdgeInsets.all(6),
                                child: Icon(Icons.drag_indicator, size: 18),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          ProviderMark(account.provider),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  controller.accountLabel(
                                    account,
                                    settings: _draft,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  [
                                    providerName(account.provider),
                                    if (account.email != null &&
                                        account.email !=
                                            controller.accountLabel(
                                              account,
                                              settings: _draft,
                                            ))
                                      account.email!,
                                  ].join(' · '),
                                  style: Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: '帳號顯示設定',
                            onPressed: () => _editAccount(account),
                            icon: const Icon(Icons.tune, size: 18),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              Surface(
                padding: const EdgeInsets.all(12),
                child: Text(
                  '隱藏窗口只影響面板的一般配額列；錯誤、失效與缺少資料仍會顯示。已釘選的窗口不受影響。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class AccountEditor extends StatefulWidget {
  const AccountEditor({
    super.key,
    required this.account,
    required this.current,
    required this.title,
  });
  final UsageAccount account;
  final AccountPreference current;
  final String title;
  @override
  State<AccountEditor> createState() => _AccountEditorState();
}

class _AccountEditorState extends State<AccountEditor> {
  late TextEditingController _alias;
  late Set<String> _hidden;
  @override
  void initState() {
    super.initState();
    _alias = TextEditingController(text: widget.current.alias);
    _hidden = widget.current.hiddenLimitIds.toSet();
  }

  @override
  void dispose() {
    _alias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: SizedBox(
      width: 500,
      height: MediaQuery.sizeOf(context).height * .72,
      child: Column(
        children: [
          PageHeader(
            title: '帳號顯示',
            subtitle: providerName(widget.account.provider),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              const SizedBox(width: 6),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  AccountPreference(
                    alias: _alias.text.trim(),
                    hiddenLimitIds: _hidden.toList(),
                  ),
                ),
                child: const Text('完成'),
              ),
            ],
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeading('帳號與別名'),
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ProviderMark(widget.account.provider),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SelectableText(widget.title),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _alias,
                          decoration: const InputDecoration(
                            labelText: '帳號別名',
                            hintText: '留空使用完整 email',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SectionHeading('在面板中顯示的窗口'),
                  Surface(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.account.limits.isEmpty)
                          const Text('目前沒有可設定的窗口。'),
                        for (final limit in widget.account.limits)
                          CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(limit.label),
                            subtitle: limit.shared
                                ? const Text('共用資源，不重複加總')
                                : null,
                            value: !_hidden.contains(limit.id),
                            onChanged: (value) => setState(() {
                              if (value!) {
                                _hidden.remove(limit.id);
                              } else {
                                _hidden.add(limit.id);
                              }
                            }),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          '只影響面板的一般配額列。錯誤、失效、缺少資料與已釘選窗口仍會顯示。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
