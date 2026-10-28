class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<String>? trackIds,
    int? createdAt,
  })  : trackIds = trackIds ?? <String>[],
        createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  String name;

  /// Ordered MediaStore track ids. Ids of tracks that no longer exist are kept
  /// (the file may be on an unmounted card) and simply not shown.
  final List<String> trackIds;
  final int createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'trackIds': trackIds,
        'createdAt': createdAt,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: '${json['id']}',
      name: ((json['name'] as String?) ?? 'Playlist').trim(),
      trackIds: (json['trackIds'] as List<dynamic>?)?.map((dynamic e) => '$e').toList() ?? <String>[],
      createdAt: (json['createdAt'] as num?)?.toInt(),
    );
  }
}
