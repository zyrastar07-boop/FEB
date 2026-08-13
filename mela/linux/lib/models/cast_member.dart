class CastMember {
  final int id;
  final String name;
  final String? profilePath;
  final String character;
  final String? biography;
  final String? birthday;

  CastMember({
    required this.id,
    required this.name,
    this.profilePath,
    required this.character,
    this.biography,
    this.birthday,
  });

  factory CastMember.fromJson(Map<String, dynamic> json) {
    return CastMember(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Unknown',
      profilePath: json['profile_path'],
      character: json['character'] ?? json['job'] ?? '',
      biography: json['biography'],
      birthday: json['birthday'],
    );
  }
}