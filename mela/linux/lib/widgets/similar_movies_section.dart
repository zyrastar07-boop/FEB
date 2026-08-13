import 'package:flutter/material.dart';
import '../../models/movie.dart'; // Adjust import to match your project's movie model path
// Adjust import to your global or feature-level movie card widget

class SimilarMoviesSection extends StatelessWidget {
  final List<Movie> movies;

  const SimilarMoviesSection({
    super.key,
    required this.movies,
  });

  @override
  Widget build(BuildContext context) {
    // Hide the section entirely if there are no recommendations
    if (movies.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title matching the reference design ("More like this")
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            "More like this",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(height: 12),
        
        // Horizontal Scrollable List of Movie Cards
        SizedBox(
          height: 180,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: movies.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: MovieCard(
                  movie: movies[index],
                  isLarge: false,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}