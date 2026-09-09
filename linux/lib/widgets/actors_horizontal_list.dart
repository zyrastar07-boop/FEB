import 'package:flutter/material.dart';
import '../models/cast_member.dart';
import '../screens/actor_detail_screen.dart';

class ActorsHorizontalList extends StatelessWidget {
  final List<CastMember> cast;

  const ActorsHorizontalList({super.key, required this.cast});

  @override
  Widget build(BuildContext context) {
    if (cast.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            "Actors",
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cast.length,
            itemBuilder: (context, index) {
              final actor = cast[index];
              return GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ActorDetailScreen(actorId: actor.id),
                    ),
                  );
                },
                child: Container(
                  width: 75,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.grey[850],
                        backgroundImage: actor.profilePath != null
                            ? NetworkImage("https://image.tmdb.org/t/p/w185${actor.profilePath}")
                            : null,
                        child: actor.profilePath == null ? const Icon(Icons.person, color: Colors.white54) : null,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        actor.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
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