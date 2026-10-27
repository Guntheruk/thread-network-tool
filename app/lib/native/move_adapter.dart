import '../move/move_execution.dart';
import '../move/move_execution_controller.dart';

/// Common lifecycle used by the isolated lab and explicit Mac execution route.
/// Profile-specific preparation and worker protocols stay in their adapters.
abstract class MoveAdapter {
  bool get available;
  MoveExecutionController get controller;
  Future<void> initialize();
  void invalidateReviews();
  MoveExecutionPlan resolveReview(String reviewId);
  void credentialsChanged({
    required String? source,
    required String? target,
    required int sourceGeneration,
    required int targetGeneration,
    required String sessionId,
    required String discoveryRevision,
  });
}
