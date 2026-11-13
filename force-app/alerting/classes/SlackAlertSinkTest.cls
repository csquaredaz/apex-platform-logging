/**
 * @description Unit tests for `SlackAlertSink`: one job per call, never throws, and the shipped
 * binding is inactive (D5, ADR 0006).
 */
@IsTest
private class SlackAlertSinkTest {
  @IsTest
  static void send_nullEmptyOrNullEntries_enqueuesNothing() {
    AlertTestFixtures.RecordingEnqueuer enqueuer = AlertTestFixtures.recordEnqueues();
    RecordingLogger logger = AlertTestFixtures.recordLogs();
    LoggingSettings.useRow(AlertTestFixtures.settingsWithChannel(AlertTestFixtures.CHANNEL));

    new SlackAlertSink().send(null);
    new SlackAlertSink().send(new List<Alert>());
    new SlackAlertSink().send(new List<Alert>{ null });

    Assert.areEqual(0, enqueuer.jobs.size(), 'Nothing to send');
    Assert.areEqual(0, logger.entries().size(), 'Nothing to log');
  }

  @IsTest
  static void send_200Alerts_enqueuesOneJobWithEveryAlert() {
    AlertTestFixtures.RecordingEnqueuer enqueuer = AlertTestFixtures.recordEnqueues();
    LoggingSettings.useRow(AlertTestFixtures.settingsWithChannel(' ' + AlertTestFixtures.CHANNEL + ' '));
    List<Alert> alerts = AlertTestFixtures.alerts(200);
    alerts.add(null);

    new SlackAlertSink().send(alerts);

    Assert.areEqual(1, enqueuer.jobs.size(), 'One call, one job, one message');
    Assert.areEqual(0, enqueuer.delays[0], 'Runs as soon as possible');
    Assert.areEqual(200, enqueuer.jobs[0].alerts.size(), 'Every non-null alert');
    Assert.areEqual(AlertTestFixtures.CHANNEL, enqueuer.jobs[0].channel, 'The trimmed channel travels with the job');
    Assert.areEqual(1, enqueuer.jobs[0].attempt, 'First attempt');
  }

  @IsTest
  static void send_noChannel_warnsAndEnqueuesNothing() {
    AlertTestFixtures.RecordingEnqueuer enqueuer = AlertTestFixtures.recordEnqueues();
    RecordingLogger logger = AlertTestFixtures.recordLogs();
    LoggingSettings.useRow(AlertTestFixtures.settingsWithChannel('  '));

    new SlackAlertSink().send(AlertTestFixtures.alerts(2));

    Assert.areEqual(0, enqueuer.jobs.size(), 'No channel, no job');
    Assert.isTrue(onlyWarn(logger).contains('no channel is set'), 'The WARN names the cause');
  }

  @IsTest
  static void send_enqueueFails_warnsAndNeverThrows() {
    AlertTestFixtures.RecordingEnqueuer enqueuer = AlertTestFixtures.recordEnqueues();
    enqueuer.failure = new AsyncException('Too many queueable jobs');
    RecordingLogger logger = AlertTestFixtures.recordLogs();
    LoggingSettings.useRow(AlertTestFixtures.settingsWithChannel(AlertTestFixtures.CHANNEL));

    new SlackAlertSink().send(AlertTestFixtures.alerts(1));

    Assert.isTrue(onlyWarn(logger).contains('Too many queueable jobs'), 'The WARN names the cause');
  }

  // The loop deliberately uses up the transaction's Queueable limit.
  @SuppressWarnings('PMD.OperationWithLimitsInLoop')
  @IsTest
  static void send_noQueueableJobsLeft_warnsWithoutEnqueuing() {
    LoggingSettings.useRow(AlertTestFixtures.settingsWithChannel(AlertTestFixtures.CHANNEL));
    // The filler jobs run when the test ends, so they need a mock to call out to.
    Test.setMock(HttpCalloutMock.class, new AlertTestFixtures.SlackHttpMock(200, '{"ok":true}'));
    while (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) {
      System.enqueueJob(new SlackAlertJob(AlertTestFixtures.alerts(1), AlertTestFixtures.CHANNEL));
    }
    RecordingLogger logger = AlertTestFixtures.recordLogs();

    new SlackAlertSink().send(AlertTestFixtures.alerts(1));

    Assert.isTrue(onlyWarn(logger).contains('no Queueable jobs left'), 'The WARN names the cause');
  }

  @IsTest
  static void binding_shipsInactive_resolvesNoOpAlertSink() {
    DI_Binding__mdt row = DI_Binding__mdt.getInstance('Slack_Alert_Sink');

    Assert.areEqual('SlackAlertSink', row.Implementation__c, 'The row names this adapter');
    Assert.areEqual('IAlertSink', row.Interface__c, 'For A port');
    Assert.isFalse(row.Is_Active__c, 'Inactive until the token and channel are set (D5)');
    Assert.isInstanceOfType(
      Application.Service.newInstance(IAlertSink.class),
      NoOpAlertSink.class,
      'An inactive row falls back to A default'
    );
  }

  // The single WARN, after checking it is the only entry, never ERROR, and flushed.
  private static String onlyWarn(RecordingLogger logger) {
    List<RecordingLogger.Entry> warnings = logger.entries(LoggingLevel.WARN);
    Assert.areEqual(1, warnings.size(), 'One WARN');
    Assert.isTrue(warnings[0].message.startsWith(SlackAlertJob.FAILURE_PREFIX), warnings[0].message);
    Assert.areEqual(0, logger.entries(LoggingLevel.ERROR).size(), 'Never ERROR (D15)');
    Assert.areEqual(1, logger.flushCount(), 'Flushed, so the WARN is not left in the buffer');
    return warnings[0].message;
  }
}
