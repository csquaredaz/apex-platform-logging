/**
 * @description Unit tests for `SlackAlertFinalizer`: a failed job's alerts are logged at WARN and
 * never retried; a successful job logs nothing (D16, ADR 0006).
 */
@IsTest
private class SlackAlertFinalizerTest {
  @IsTest
  static void execute_jobSucceeded_logsNothing() {
    RecordingLogger logger = AlertTestFixtures.recordLogs();
    AlertTestFixtures.RecordingEnqueuer enqueuer = AlertTestFixtures.recordEnqueues();

    new SlackAlertFinalizer(AlertTestFixtures.alerts(3))
      .execute(new AlertTestFixtures.FakeFinalizerContext(ParentJobResult.SUCCESS, null));

    Assert.areEqual(0, logger.entries().size(), 'Nothing was lost');
    Assert.areEqual(0, enqueuer.jobs.size(), 'Never retries');
  }

  @IsTest
  static void execute_jobFailed_logsTheCauseAndEachLostAlert() {
    RecordingLogger logger = AlertTestFixtures.recordLogs();
    AlertTestFixtures.RecordingEnqueuer enqueuer = AlertTestFixtures.recordEnqueues();

    new SlackAlertFinalizer(AlertTestFixtures.alerts(3))
      .execute(
        new AlertTestFixtures.FakeFinalizerContext(ParentJobResult.UNHANDLED_EXCEPTION, new NullPointerException())
      );

    List<RecordingLogger.Entry> warnings = logger.entries(LoggingLevel.WARN);
    Assert.areEqual(4, warnings.size(), 'The cause, then one line per alert');
    Assert.isTrue(warnings[0].message.startsWith(SlackAlertJob.FAILURE_PREFIX), warnings[0].message);
    Assert.isTrue(warnings[0].message.contains('System.NullPointerException'), warnings[0].message);
    Assert.isTrue(warnings[0].message.contains('3 alert(s) not sent'), warnings[0].message);
    Assert.areEqual('Unsent alert [CRITICAL] Shipment booking failed for order 2', warnings[2].message, 'By title');
    Assert.areEqual(0, logger.entries(LoggingLevel.ERROR).size(), 'Never ERROR (D15)');
    Assert.areEqual(1, logger.flushCount(), 'Flushed');
    Assert.areEqual(0, enqueuer.jobs.size(), 'No retry (D16)');
  }

  @IsTest
  static void execute_jobFailedWithoutException_namesAnUnknownError() {
    RecordingLogger logger = AlertTestFixtures.recordLogs();

    new SlackAlertFinalizer(AlertTestFixtures.alerts(1))
      .execute(new AlertTestFixtures.FakeFinalizerContext(ParentJobResult.UNHANDLED_EXCEPTION, null));

    Assert.isTrue(logger.entries(LoggingLevel.WARN)[0].message.contains('an unknown error'), 'Null-safe');
  }
}
