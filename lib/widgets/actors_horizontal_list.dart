import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design/tokens.dart';
import '../models/cast_member.dart';
import '../navigation/app_navigator.dart';
import 'app_card.dart';

/// Horizontal cast list — responsive + uses [AppCard] for tap feedback.
class ActorsHorizontalList extends StatelessWidget {
  final List<CastMember> cast;

  const ActorsHorizontalList({super.key, required this.cast});

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();

    final pagePadding = AppDesignTokens.pagePadding(context);
    final isMobile = MediaQuery.sizeOf(context).width < AppDesignTokens.bpTablet;
    final itemWidth = isMobile ? 75.0 : 90.0;
    final avatarRadius = isMobile ? 32.0 : 38.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pagePadding.left),
          child: Text(
            "Actors",
            style: AppDesignTokens.headlineMedium().copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: avatarRadius * 2 + 40,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: pagePadding.left - 4),
            itemCount: cast.length,
            itemBuilder: (context, index) {
              final actor = cast[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AppCard(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    AppNavigator.openActor(context, actor.id);
                  },
                  borderRadius: AppDesignTokens.radiusSm,
                  border: false,
                  elevation: AppCardElevation.none,
                  backgroundColor: Colors.transparent,
                  semanticLabel: actor.name,
                  child: SizedBox(
                    width: itemWidth,
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: avatarRadius,
                          backgroundColor: Colors.grey[850],
                          backgroundImage: actor.profilePath != null
                              ? NetworkImage(
                                  "https://image.tmdb.org/t/p/w185${actor.profilePath}")
                              : null,
                          child: actor.profilePath == null
                              ? const Icon(Icons.person, color: Colors.white54)
                              : null,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          actor.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: AppDesignTokens.labelSmall().copyWith(
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
