/// contract/schema/verdict.schema.json: station result for one package (one site visit).
/// ready: no blockers, no limitations. limited: usable with named limitations, no blockers.
/// blocked: at least one blocker finding. The phone reads verdicts; the station writes them.
public struct Verdict: Hashable, Sendable, Codable {
  /// Fixed statement carried by every verdict.
  public static let fixedStatement =
    "This verdict is an automated check of the intake package. It does not certify any property model or measurement."

  public var schemaVersion: SchemaVersion
  public var verdictId: LowercaseUUID
  public var packageId: LowercaseUUID
  public var visitId: LowercaseUUID
  public var revision: Int
  public var outcome: VerdictOutcome
  /// The preliminary task the outcome applies to.
  public var task: String
  /// One or two plain sentences explaining the outcome.
  public var summary: String
  public var evaluatedAt: UTCTimestamp
  public var evaluator: Evaluator
  /// Result of every rule the station ran on this package.
  public var checks: [CheckResult]
  public var findings: [Finding]
  /// Named limitations in plain words. Empty when the outcome is ready.
  public var limitations: [String]
  /// Targeted measurements, photos, exports or recapture to request.
  public var nextActions: [String]
  /// Always `Verdict.fixedStatement`.
  public var statement: String

  public init(
    schemaVersion: SchemaVersion = .current,
    verdictId: LowercaseUUID,
    packageId: LowercaseUUID,
    visitId: LowercaseUUID,
    revision: Int,
    outcome: VerdictOutcome,
    task: String,
    summary: String,
    evaluatedAt: UTCTimestamp,
    evaluator: Evaluator,
    checks: [CheckResult],
    findings: [Finding],
    limitations: [String],
    nextActions: [String],
    statement: String = Verdict.fixedStatement
  ) {
    self.schemaVersion = schemaVersion
    self.verdictId = verdictId
    self.packageId = packageId
    self.visitId = visitId
    self.revision = revision
    self.outcome = outcome
    self.task = task
    self.summary = summary
    self.evaluatedAt = evaluatedAt
    self.evaluator = evaluator
    self.checks = checks
    self.findings = findings
    self.limitations = limitations
    self.nextActions = nextActions
    self.statement = statement
  }

  /// Station component and rule set version that produced the verdict.
  public struct Evaluator: Hashable, Sendable, Codable {
    public var name: String
    public var version: String

    public init(name: String, version: String) {
      self.name = name
      self.version = version
    }
  }

  public struct CheckResult: Hashable, Sendable, Codable {
    /// Stable rule id, for example units.scale.
    public var ruleId: String
    /// Rule name shown to people, for example Units and scale.
    public var title: String
    public var status: CheckStatus

    public init(ruleId: String, title: String, status: CheckStatus) {
      self.ruleId = ruleId
      self.title = title
      self.status = status
    }
  }

  public struct Finding: Hashable, Sendable, Codable {
    public var ruleId: String
    public var severity: FindingSeverity
    public var message: String
    /// Package file the finding is about.
    public var filePath: String?
    /// Capture the finding is about, when it concerns one capture.
    public var captureId: LowercaseUUID?
    public var areaKey: String?
    /// Measured value with units, for example Distance A -0.4% vs tape.
    public var measured: String?
    /// Expected value or tolerance, for example within 1% or 25.4 mm.
    public var expected: String?
    /// What to do next, or None.
    public var nextAction: String

    public init(
      ruleId: String,
      severity: FindingSeverity,
      message: String,
      filePath: String? = nil,
      captureId: LowercaseUUID? = nil,
      areaKey: String? = nil,
      measured: String? = nil,
      expected: String? = nil,
      nextAction: String
    ) {
      self.ruleId = ruleId
      self.severity = severity
      self.message = message
      self.filePath = filePath
      self.captureId = captureId
      self.areaKey = areaKey
      self.measured = measured
      self.expected = expected
      self.nextAction = nextAction
    }
  }
}
