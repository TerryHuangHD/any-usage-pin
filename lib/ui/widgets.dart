import 'package:flutter/material.dart';

import '../controller.dart';

Color providerColor(String provider) => switch (provider) {
  'anthropic' => const Color(0xFFC17652),
  'openai-codex' => const Color(0xFF178477),
  'google-antigravity' => const Color(0xFF5276D4),
  'xai-oauth' => const Color(0xFF777787),
  'cursor' => const Color(0xFF8869B4),
  _ => const Color(0xFF668586),
};

const _subscriptionAssets = {
  'anthropic': 'assets/providers/anthropic.png',
  'openai-codex': 'assets/providers/openai-codex.png',
  'google-antigravity': 'assets/providers/google-antigravity.png',
  'xai-oauth': 'assets/providers/xai-oauth.png',
  'cursor': 'assets/providers/cursor.png',
};

class SubscriptionIcon extends StatelessWidget {
  const SubscriptionIcon(this.provider, {super.key, required this.size});
  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = _subscriptionAssets[provider];
    if (asset == null) return Icon(Icons.help_outline, size: size);
    final colored = provider == 'anthropic' || provider == 'google-antigravity';
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      color: colored ? null : Theme.of(context).colorScheme.onSurface,
      semanticLabel: providerName(provider),
    );
  }
}

class ProviderMark extends StatelessWidget {
  const ProviderMark(this.provider, {super.key, this.size = 32});
  final String provider;
  final double size;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: providerName(provider),
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: providerColor(provider).withValues(alpha: .10),
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Center(child: SubscriptionIcon(provider, size: size * .56)),
    ),
  );
}

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: Theme.of(
          context,
        ).colorScheme.outlineVariant.withValues(alpha: .65),
      ),
    ),
    child: child,
  );
}

class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.error = false, this.action});
  final String text;
  final bool error;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: (error ? Colors.orange : Theme.of(context).colorScheme.primary)
          .withValues(alpha: .08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          error ? Icons.warning_amber_rounded : Icons.info_outline,
          size: 16,
          color: error
              ? Colors.orange.shade800
              : Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.bodySmall),
        ),
        ?action,
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Row(
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const Spacer(),
        ?trailing,
      ],
    ),
  );
}

class PinPreview extends StatelessWidget {
  const PinPreview(this.view, {super.key});
  final Map<String, Object?> view;

  @override
  Widget build(BuildContext context) {
    final layers = view['layers'] as List<Map<String, Object?>>;
    final colorHex = view['color'] as String;
    final color = colorHex.startsWith('#') && colorHex.length == 7
        ? Color(
            0xFF000000 | (int.tryParse(colorHex.substring(1), radix: 16) ?? 0),
          )
        : Theme.of(context).colorScheme.onSurface;
    final showLabel =
        (view['labelWidth'] as int) > 0 && (view['label'] as String).isNotEmpty;
    final fontSize = layers.length == 2 ? 9.0 : 11.0;
    return Tooltip(
      message: view['tooltip'] as String,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (view['showIcon'] == true) ...[
              SubscriptionIcon(view['provider'] as String, size: 17),
              if (showLabel || layers.isNotEmpty) const SizedBox(width: 6),
            ],
            if (showLabel) ...[
              SizedBox(
                width: (view['labelWidth'] as int).toDouble(),
                child: Text(
                  view['label'] as String,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: color),
                ),
              ),
              if (layers.isNotEmpty) const SizedBox(width: 5),
            ],
            if (layers.isNotEmpty)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final layer in layers)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (layer['showBar'] == true) ...[
                          if (layer['fraction'] != null)
                            SizedBox(
                              width: 32,
                              child: LinearProgressIndicator(
                                value: (layer['fraction'] as double).clamp(
                                  0,
                                  1,
                                ),
                                color: color,
                                minHeight: 4,
                                backgroundColor: color.withValues(alpha: .25),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            )
                          else
                            Container(
                              width: 32,
                              height: 8,
                              decoration: BoxDecoration(
                                border: Border.all(color: color),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Center(
                                child: Text(
                                  '?',
                                  style: TextStyle(
                                    fontSize: fontSize,
                                    height: 1,
                                    color: color,
                                  ),
                                ),
                              ),
                            ),
                          if (layer['text'] != null || layer['status'] != 'ok')
                            const SizedBox(width: 6),
                        ],
                        if (layer['status'] != 'ok') ...[
                          Text(
                            '!',
                            style: TextStyle(fontSize: fontSize, color: color),
                          ),
                          if (layer['text'] != null) const SizedBox(width: 3),
                        ],
                        if (layer['text'] != null)
                          Text(
                            layer['text'] as String,
                            style: TextStyle(
                              fontSize: fontSize,
                              height: 1.12,
                              color: color,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            if (view['status'] != 'ok' &&
                layers.every((layer) => layer['status'] == 'ok'))
              Text(' !', style: TextStyle(fontSize: 11, color: color)),
          ],
        ),
      ),
    );
  }
}
