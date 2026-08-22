/// Data models mirroring the backend REST payloads.
library;

/// One step of the teleportation walkthrough shown while signing.
class SignatureStep {
  SignatureStep({
    required this.index,
    required this.digestBit,
    required this.basis,
    required this.preparedState,
    required this.bellMeasurement,
    required this.pauliCorrection,
    required this.description,
  });

  final int index;
  final int digestBit;
  final String basis;
  final String preparedState;
  final String bellMeasurement;
  final String pauliCorrection;
  final String description;

  factory SignatureStep.fromJson(Map<String, dynamic> json) => SignatureStep(
        index: json['index'] as int,
        digestBit: json['digest_bit'] as int,
        basis: json['basis'] as String,
        preparedState: json['prepared_state'] as String,
        bellMeasurement: json['bell_measurement'] as String,
        pauliCorrection: json['pauli_correction'] as String,
        description: json['description'] as String,
      );
}

/// Result of `POST /sign`.
class SignatureResult {
  SignatureResult({
    required this.signatureId,
    required this.message,
    required this.messageHash,
    required this.signer,
    required this.keyId,
    required this.length,
    required this.bases,
    required this.corrections,
    required this.bellBits,
    required this.steps,
    required this.elapsedMs,
    required this.keyQber,
  });

  final String signatureId;
  final String message;
  final String messageHash;
  final String signer;
  final String keyId;
  final int length;
  final List<String> bases;
  final List<String> corrections;
  final List<List<int>> bellBits;
  final List<SignatureStep> steps;
  final double elapsedMs;
  final double keyQber;

  factory SignatureResult.fromJson(Map<String, dynamic> json) => SignatureResult(
        signatureId: json['signature_id'] as String,
        message: json['message'] as String,
        messageHash: json['message_hash'] as String,
        signer: json['signer'] as String,
        keyId: json['key_id'] as String,
        length: json['length'] as int,
        bases: (json['encoding_bases'] as List).cast<String>(),
        corrections: (json['corrections'] as List).cast<String>(),
        bellBits: (json['bell_bits'] as List)
            .map((e) => (e as List).map((v) => v as int).toList())
            .toList(),
        steps: (json['steps'] as List)
            .map((e) => SignatureStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        elapsedMs: (json['elapsed_ms'] as num).toDouble(),
        keyQber: (json['key_qber'] as num).toDouble(),
      );
}

/// Result of `POST /verify`.
class VerificationResult {
  VerificationResult({
    required this.signatureId,
    required this.verifier,
    required this.message,
    required this.verdict,
    required this.accepted,
    required this.mismatchRate,
    required this.threshold,
    required this.qber,
    required this.forgeryProbability,
    required this.reason,
    required this.bases,
    required this.measuredBits,
    required this.expectedBits,
    required this.anomalies,
    required this.elapsedMs,
  });

  final String signatureId;
  final String verifier;
  final String message;
  final String verdict;
  final bool accepted;
  final double mismatchRate;
  final double threshold;
  final double qber;
  final double forgeryProbability;
  final String reason;
  final List<String> bases;
  final List<int> measuredBits;
  final List<int> expectedBits;
  final List<String> anomalies;
  final double elapsedMs;

  factory VerificationResult.fromJson(Map<String, dynamic> json) {
    final decision = json['decision'] as Map<String, dynamic>;
    return VerificationResult(
      signatureId: json['signature_id'] as String,
      verifier: json['verifier'] as String,
      message: json['message'] as String,
      verdict: json['verdict'] as String,
      accepted: json['accepted'] as bool,
      mismatchRate: (decision['mismatch_rate'] as num).toDouble(),
      threshold: (decision['threshold'] as num).toDouble(),
      qber: (decision['qber'] as num).toDouble(),
      forgeryProbability: (decision['forgery_probability'] as num).toDouble(),
      reason: decision['reason'] as String,
      bases: (json['verifier_bases'] as List).cast<String>(),
      measuredBits: (json['measured_bits'] as List).cast<int>(),
      expectedBits: (json['expected_bits'] as List).cast<int>(),
      anomalies: (json['anomalies'] as List).cast<String>(),
      elapsedMs: (json['elapsed_ms'] as num).toDouble(),
    );
  }
}

/// Result of `POST /simulate-attack`.
class AttackResult {
  AttackResult({
    required this.attackId,
    required this.attackType,
    required this.description,
    required this.targetSignatureId,
    required this.presentedMessage,
    required this.attacker,
    required this.detected,
    required this.expectedDetection,
    required this.indicators,
    required this.verification,
    required this.elapsedMs,
  });

  final String attackId;
  final String attackType;
  final String description;
  final String targetSignatureId;
  final String presentedMessage;
  final String attacker;
  final bool detected;
  final bool expectedDetection;
  final List<String> indicators;
  final VerificationResult verification;
  final double elapsedMs;

  factory AttackResult.fromJson(Map<String, dynamic> json) => AttackResult(
        attackId: json['attack_id'] as String,
        attackType: json['attack_type'] as String,
        description: json['description'] as String,
        targetSignatureId: json['target_signature_id'] as String,
        presentedMessage: json['presented_message'] as String,
        attacker: json['attacker'] as String,
        detected: json['detected'] as bool,
        expectedDetection: json['expected_detection'] as bool,
        indicators: (json['indicators'] as List).cast<String>(),
        verification: VerificationResult.fromJson(
            json['verification'] as Map<String, dynamic>),
        elapsedMs: (json['elapsed_ms'] as num).toDouble(),
      );
}

/// An attack type offered by `GET /attack-types`.
class AttackType {
  AttackType({required this.name, required this.description});

  final String name;
  final String description;

  factory AttackType.fromJson(Map<String, dynamic> json) => AttackType(
        name: json['attack_type'] as String,
        description: json['description'] as String,
      );
}

/// One row of `GET /logs`.
class LogEvent {
  LogEvent({
    required this.id,
    required this.eventType,
    required this.signatureId,
    required this.subject,
    required this.verdict,
    required this.detected,
    required this.mismatchRate,
    required this.qber,
    required this.elapsedMs,
    required this.createdAt,
    required this.payload,
  });

  final int id;
  final String eventType;
  final String? signatureId;
  final String? subject;
  final String? verdict;
  final bool? detected;
  final double? mismatchRate;
  final double? qber;
  final double? elapsedMs;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  factory LogEvent.fromJson(Map<String, dynamic> json) => LogEvent(
        id: json['id'] as int,
        eventType: json['event_type'] as String,
        signatureId: json['signature_id'] as String?,
        subject: json['subject'] as String?,
        verdict: json['verdict'] as String?,
        detected: json['detected'] as bool?,
        mismatchRate: (json['mismatch_rate'] as num?)?.toDouble(),
        qber: (json['qber'] as num?)?.toDouble(),
        elapsedMs: (json['elapsed_ms'] as num?)?.toDouble(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            ((json['created_at'] as num) * 1000).round()),
        payload: (json['payload'] as Map).cast<String, dynamic>(),
      );
}

/// Aggregated view of `GET /metrics`.
class MetricsSnapshot {
  MetricsSnapshot({
    required this.signatures,
    required this.verifications,
    required this.attacks,
    required this.threatsDetected,
    required this.detectionAccuracy,
    required this.detectionRate,
    required this.falseAcceptanceRate,
    required this.falseRejectionRate,
    required this.theoreticalForgeryProbability,
    required this.threshold,
    required this.signatureLength,
    required this.avgSignMs,
    required this.avgVerifyMs,
    required this.maxVerifyMs,
    required this.complexity,
    required this.perAttack,
    required this.mismatchSeries,
  });

  final int signatures;
  final int verifications;
  final int attacks;
  final int threatsDetected;
  final double detectionAccuracy;
  final double detectionRate;
  final double falseAcceptanceRate;
  final double falseRejectionRate;
  final double theoreticalForgeryProbability;
  final double threshold;
  final int signatureLength;
  final double avgSignMs;
  final double avgVerifyMs;
  final double maxVerifyMs;
  final String complexity;
  final Map<String, AttackStat> perAttack;
  final List<MismatchPoint> mismatchSeries;

  factory MetricsSnapshot.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'] as Map<String, dynamic>;
    final security = json['security'] as Map<String, dynamic>;
    final performance = json['performance'] as Map<String, dynamic>;
    return MetricsSnapshot(
      signatures: totals['signatures'] as int,
      verifications: totals['verifications'] as int,
      attacks: totals['attacks'] as int,
      threatsDetected: totals['threats_detected'] as int,
      detectionAccuracy: (security['detection_accuracy'] as num).toDouble(),
      detectionRate: (security['detection_rate'] as num).toDouble(),
      falseAcceptanceRate: (security['false_acceptance_rate'] as num).toDouble(),
      falseRejectionRate: (security['false_rejection_rate'] as num).toDouble(),
      theoreticalForgeryProbability:
          (security['theoretical_forgery_probability'] as num).toDouble(),
      threshold: (security['threshold'] as num).toDouble(),
      signatureLength: security['signature_length_qubits'] as int,
      avgSignMs: (performance['avg_sign_ms'] as num).toDouble(),
      avgVerifyMs: (performance['avg_verify_ms'] as num).toDouble(),
      maxVerifyMs: (performance['max_verify_ms'] as num).toDouble(),
      complexity: performance['complexity'] as String,
      perAttack: (json['per_attack'] as Map).map(
        (key, value) => MapEntry(
            key as String, AttackStat.fromJson((value as Map).cast<String, dynamic>())),
      ),
      mismatchSeries: (json['mismatch_series'] as List)
          .map((e) => MismatchPoint.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class AttackStat {
  AttackStat({
    required this.runs,
    required this.detected,
    required this.detectionRate,
    required this.meanMismatchRate,
  });

  final int runs;
  final int detected;
  final double detectionRate;
  final double meanMismatchRate;

  factory AttackStat.fromJson(Map<String, dynamic> json) => AttackStat(
        runs: json['runs'] as int,
        detected: json['detected'] as int,
        detectionRate: (json['detection_rate'] as num).toDouble(),
        meanMismatchRate: (json['mean_mismatch_rate'] as num).toDouble(),
      );
}

class MismatchPoint {
  MismatchPoint({required this.timestamp, required this.value, required this.type});

  final DateTime timestamp;
  final double value;
  final String? type;

  factory MismatchPoint.fromJson(Map<String, dynamic> json) => MismatchPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
            ((json['t'] as num) * 1000).round()),
        value: (json['value'] as num).toDouble(),
        type: json['type'] as String?,
      );
}
