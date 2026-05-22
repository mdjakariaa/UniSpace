/// Room entity — domain model
class RoomEntity {
  final String id;
  final String name;
  final String building;
  final int floor;
  final int totalSeats;
  final int availableSeats;
  final List<String> facilities;
  final String? imageUrl;
  final String status;
  final double rating;
  final int totalRatings;
  final DateTime createdAt;

  const RoomEntity({
    required this.id,
    required this.name,
    required this.building,
    required this.floor,
    required this.totalSeats,
    required this.availableSeats,
    this.facilities = const [],
    this.imageUrl,
    this.status = 'available',
    this.rating = 0.0,
    this.totalRatings = 0,
    required this.createdAt,
  });

  factory RoomEntity.fromJson(Map<String, dynamic> json) {
    return RoomEntity(
      id: json['id'] as String,
      name: json['name'] as String,
      building: json['building'] as String,
      floor: json['floor'] as int? ?? 1,
      totalSeats: json['total_seats'] as int? ?? 0,
      availableSeats: json['available_seats'] as int? ?? 0,
      facilities: (json['facilities'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      imageUrl: json['image_url'] as String?,
      status: json['status'] as String? ?? 'available',
      rating: (json['rating'] as num?)?.toDouble() ?? 0.0,
      totalRatings: json['total_ratings'] as int? ?? 0,
      createdAt: DateTime.parse(
        json['created_at'] as String? ?? DateTime.now().toIso8601String(),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'building': building,
        'floor': floor,
        'total_seats': totalSeats,
        'available_seats': availableSeats,
        'facilities': facilities,
        'image_url': imageUrl,
        'status': status,
        'rating': rating,
        'total_ratings': totalRatings,
      };
}
