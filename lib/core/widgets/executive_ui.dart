import 'package:flutter/material.dart';

/// Reusable executive-grade design components directly styled after Stitch Mobile POS.
class ExecutiveCard extends StatelessWidget {
  const ExecutiveCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 12),
    this.borderColor,
    this.backgroundColor,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final border = borderColor ?? const Color(0xff31353f);
    final bg = backgroundColor ?? const Color(0xff1c1f29);

    Widget content = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: content,
        ),
      );
    }
    return content;
  }
}

/// Status pill badge with semantic color fills and subtle glowing border.
class ExecutiveBadge extends StatelessWidget {
  const ExecutiveBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dot = true,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool dot;

  factory ExecutiveBadge.paid({String label = 'PAID'}) => ExecutiveBadge(
        label: label,
        color: const Color(0xff4edea3),
      );

  factory ExecutiveBadge.partial({String label = 'PARTIAL'}) => ExecutiveBadge(
        label: label,
        color: const Color(0xfff59e0b),
      );

  factory ExecutiveBadge.unpaid({String label = 'UNPAID'}) => ExecutiveBadge(
        label: label,
        color: const Color(0xfff43f5e),
      );

  factory ExecutiveBadge.info(String label) => ExecutiveBadge(
        label: label,
        color: const Color(0xff3b82f6),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Store telemetry status banner showing real-time store indicators identical to Stitch.
class ExecutiveStoreRibbon extends StatelessWidget {
  const ExecutiveStoreRibbon({
    super.key,
    required this.roleLabel,
  });

  final String roleLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xff0a0e17),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff31353f)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xff4edea3),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0xff4edea3),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Store Active',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xffdfe2ef),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xff2563eb).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xff2563eb).withValues(alpha: 0.5),
              ),
            ),
            child: Text(
              roleLabel.toUpperCase(),
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: Color(0xffb4c5ff),
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
