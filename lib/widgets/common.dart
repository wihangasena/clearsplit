import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';

/// Parses a "#RRGGBB" hex string into a [Color], falling back to blue.
Color colorFromHex(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final value = int.tryParse(h, radix: 16);
  return value == null ? const Color(0xFF2563EB) : Color(value);
}

/// Formats a dollar amount as "$12.50".
String money(double amount) => '\$${amount.abs().toStringAsFixed(2)}';

/// Emoji for an expense category.
String categoryEmoji(String category) {
  switch (category) {
    case 'food':
      return '🍔';
    case 'transport':
      return '🚕';
    case 'home':
      return '🏠';
    case 'utilities':
      return '💡';
    case 'travel':
      return '✈️';
    case 'entertainment':
      return '🎬';
    case 'shopping':
      return '🛍️';
    case 'health':
      return '💊';
    default:
      return '🧾';
  }
}

const expenseCategories = <String>[
  'food',
  'transport',
  'home',
  'utilities',
  'travel',
  'entertainment',
  'shopping',
  'health',
  'general',
];

/// Palette for profile color selection (PROF-03).
const profilePalette = <String>[
  '#2563EB',
  '#10B981',
  '#8B5CF6',
  '#EF4444',
  '#F59E0B',
  '#0EA5E9',
  '#EC4899',
  '#14B8A6',
];

const avatarChoices = <String>[
  '🙂', '🧑', '👩', '🧔', '👧', '🧒', '😎', '🤓', '🐱', '🐶', '🦊', '🐼',
];

/// Circular avatar built from a [Person]'s emoji + color, with a soft tinted
/// fill and a subtle ring in the person's color.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({super.key, required this.person, this.radius = 20});

  final Person person;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final color = colorFromHex(person.color);
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.28), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(person.avatar, style: TextStyle(fontSize: radius)),
    );
  }
}

/// Colored "owes you / you owe / settled up" label for a net balance.
class BalanceLabel extends StatelessWidget {
  const BalanceLabel({
    super.key,
    required this.net,
    this.compact = false,
    this.isSelf = false,
  });

  /// Positive = they owe me; negative = I owe them.
  final double net;
  final bool compact;

  /// When true the label refers to the signed-in user (e.g. "you owe" instead
  /// of "owes"), used for the user's own row in a group's member balances.
  final bool isSelf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settled = net.abs() < 0.005;
    final owesMe = net > 0;
    final color = settled
        ? theme.colorScheme.outline
        : (owesMe ? const Color(0xFF10B981) : const Color(0xFFEF4444));
    final label = settled
        ? 'settled up'
        : (owesMe ? 'owes you' : 'you owe');

    if (compact) {
      // Directional so a member who owes vs. one who gets money back can't be
      // misread — the bare number alone looked like everyone had the same sign.
      final String text;
      if (settled) {
        text = 'settled up';
      } else if (owesMe) {
        text = '${isSelf ? 'you get back' : 'gets back'} ${money(net)}';
      } else {
        text = '${isSelf ? 'you owe' : 'owes'} ${money(net)}';
      }
      return Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      );
    }

    if (settled) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text('settled up',
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: (owesMe ? AppTheme.positiveSoft : AppTheme.negativeSoft),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            money(net),
            style: theme.textTheme.titleSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Hero card showing the user's overall balance with a brand gradient.
class OverallBalanceCard extends StatelessWidget {
  const OverallBalanceCard({super.key, required this.summary});

  final BalanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final net = summary.net;
    final settled = net.abs() < 0.005;
    final positive = net >= 0;

    final gradient = settled
        ? AppTheme.brandGradient
        : positive
            ? AppTheme.positiveGradient
            : AppTheme.negativeGradient;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: gradient.colors.last.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                settled
                    ? Icons.check_circle_outline
                    : positive
                        ? Icons.trending_up
                        : Icons.trending_down,
                color: Colors.white.withValues(alpha: 0.9),
                size: 18,
              ),
              const SizedBox(width: 6),
              Text(
                settled
                    ? "You're all settled up"
                    : positive
                        ? 'Overall, you are owed'
                        : 'Overall, you owe',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            money(net),
            style: theme.textTheme.displaySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _chip(context, 'you are owed', summary.owed),
              const SizedBox(width: 12),
              _chip(context, 'you owe', summary.owe),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, double value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.white.withValues(alpha: 0.85),
                    )),
            const SizedBox(height: 2),
            Text(
              money(value),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
