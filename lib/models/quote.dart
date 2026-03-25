import 'package:cloud_firestore/cloud_firestore.dart';

/// Official Quote sent by a provider inside the chat.
/// Firestore path: `quotes/{quoteId}`
class QuoteModel {
  final String id;
  final String providerId;
  final String clientId;
  final String chatRoomId;
  final String description;
  final double amount;

  /// 'pending' | 'approved' | 'paid' | 'rejected'
  final String status;

  /// Firestore doc ID of the Job created when the client pays.
  final String? jobId;
  final dynamic createdAt;

  const QuoteModel({
    required this.id,
    required this.providerId,
    required this.clientId,
    required this.chatRoomId,
    required this.description,
    required this.amount,
    required this.status,
    this.jobId,
    this.createdAt,
  });

  factory QuoteModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return QuoteModel(
      id:          doc.id,
      providerId:  d['providerId']?.toString()  ?? '',
      clientId:    d['clientId']?.toString()    ?? '',
      chatRoomId:  d['chatRoomId']?.toString()  ?? '',
      description: d['description']?.toString() ?? '',
      amount:      (d['amount'] as num? ?? 0).toDouble(),
      status:      d['status']?.toString()      ?? 'pending',
      jobId:       d['jobId']?.toString(),
      createdAt:   d['createdAt'],
    );
  }

  Map<String, dynamic> toMap() => {
    'providerId':  providerId,
    'clientId':    clientId,
    'chatRoomId':  chatRoomId,
    'description': description,
    'amount':      amount,
    'status':      status,
    'createdAt':   FieldValue.serverTimestamp(),
  };
}
