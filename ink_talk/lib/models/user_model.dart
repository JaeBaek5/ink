import 'package:cloud_firestore/cloud_firestore.dart';

/// 사용자 모델
class UserModel {
  final String uid;
  final String visibleId;
  final String? email;
  final String? phoneNumber;
  final String? displayName;
  final String? photoUrl;
  final String? statusMessage;
  final DateTime createdAt;
  final DateTime lastActiveAt;

  UserModel({
    required this.uid,
    required this.visibleId,
    this.email,
    this.phoneNumber,
    this.displayName,
    this.photoUrl,
    this.statusMessage,
    required this.createdAt,
    required this.lastActiveAt,
  });

  /// Firestore 문서에서 생성
  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return UserModel(
      uid: doc.id,
      visibleId: data['visibleId'] ?? '',
      email: data['email'],
      phoneNumber: data['phoneNumber'],
      displayName: data['displayName'],
      photoUrl: data['photoUrl'],
      statusMessage: data['statusMessage'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastActiveAt: (data['lastActiveAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  /// Firestore에 저장할 Map
  Map<String, dynamic> toFirestore() {
    return {
      'visibleId': visibleId,
      'email': email,
      'phoneNumber': phoneNumber,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'statusMessage': statusMessage,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastActiveAt': Timestamp.fromDate(lastActiveAt),
    };
  }

  /// 복사본 생성
  UserModel copyWith({
    String? visibleId,
    String? email,
    String? phoneNumber,
    String? displayName,
    String? photoUrl,
    String? statusMessage,
    DateTime? lastActiveAt,
  }) {
    return UserModel(
      uid: uid,
      visibleId: visibleId ?? this.visibleId,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      statusMessage: statusMessage ?? this.statusMessage,
      createdAt: createdAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
    );
  }
}
