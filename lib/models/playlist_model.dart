class Song {
  final String id;
  final String title;
  final String url;
  final String thumbnail;
  final String duration;
  final String artist;

  Song({
    required this.id,
    required this.title,
    required this.url,
    required this.thumbnail,
    this.duration = "",
    this.artist = "",
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'url': url,
      'thumbnail': thumbnail,
      'duration': duration,
      'artist': artist,
    };
  }

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'] ?? "",
      title: json['title'] ?? "",
      url: json['url'] ?? "",
      thumbnail: json['thumbnail'] ?? "",
      duration: json['duration'] ?? "",
      artist: json['artist'] ?? "",
    );
  }
}

class Playlist {
  final String id;
  final String name;
  final List<Song> songs;

  Playlist({
    required this.id,
    required this.name,
    required this.songs,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'songs': songs.map((s) => s.toJson()).toList(),
    };
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] ?? "",
      name: json['name'] ?? "",
      songs: (json['songs'] as List?)
              ?.map((s) => Song.fromJson(s))
              .toList() ??
          [],
    );
  }

  Playlist copyWith({
    String? id,
    String? name,
    List<Song>? songs,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      songs: songs ?? this.songs,
    );
  }
}
