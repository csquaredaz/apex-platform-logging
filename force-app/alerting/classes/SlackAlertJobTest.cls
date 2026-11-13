/**
 * @description Unit tests for `SlackAlertJob` with a Stub API `ICalloutClient`: every outcome,
 * the single 429 re-enqueue and its delay, and the WARN-only loop guard (D7, D15, ADR 0006).
 */
@IsTest
private class SlackAlertJobTest {
  private static Mocks client;
  private static RecordingLogger logger;
  private static AlertTestFixtures.RecordingEnqueuer enqueuer;

  private static void useMocks() {
    client = new Mocks();
    Application.Service.setMock(ICalloutClient.class, client.stub(ICalloutClient.class));
    logger = AlertTestFixtures.recordLogs();
    enqueuer = AlertTestFixtures.recordEnqueues();
  }

  private static void answer(Integer statusCode, String body, String retryAfter) {
    client.stubReturn('send', AlertTestFixtures.response(statusCode, body, retryAfter));
  }

  private static SlackAlertJob job(Integer alertCount, Integer attempt) {
    return new SlackAlertJob(AlertTestFixtures.alerts(alertCount), AlertTestFixtures.CHANNEL, attempt);
  }

  private static CalloutRequest sentRequest() {
    return (CalloutRequest) client.argumentsOf('send', 0)[0];
  }

  @IsTest
  static void deliver_slackOk_postsOnceAndLogsNothing() {
    useMocks();
    answer(200, '{"ok":true,"ts":"1700000000.000100"}', null);

    job(3, 1).deliver();

    client.verify('send', 1);
    CalloutRequest request = sentRequest();
    Assert.areEqual('POST', request.getMethod(), 'chat.postMessage is a POST');
    Assert.areEqual('callout:Slack/chat.postMessage', request.getEndpoint(), 'Through the Slack Named Credential');
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
    Assert.areEqual(AlertTestFixtures.CHANNEL, body.get('channel'), 'Channel');
    Assert.areEqual(7, ((List<Object>) body.get('blocks')).size(), 'Header plus two blocks per alert');
    Assert.areEqual(0, logger.entries().size(), 'Success logs nothing');
    Assert.areEqual(1, logger.flushCount(), 'The logger is always flushed');
    Assert.areEqual(0, enqueuer.jobs.size(), 'No retry');
  }

  @IsTest
  static void deliver_200Alerts_postsOneMessageAtTheBlockCap() {
    useMocks();
    answer(200, '{"ok":true}', null);

    job(200, 1).deliver();

    client.verify('send', 1);
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(sentRequest().getBody());
    Assert.areEqual(
      SlackMessageBuilder.MAX_BLOCKS,
      ((List<Object>) body.get('blocks')).size(),
      'One message, 50 blocks'
    );
  }

  @IsTest
  static void deliver_slackNotOk_warnsWithTheErrorCode() {
    useMocks();
    answer(200, '{"ok":false,"error":"channel_not_found"}', null);

    job(2, 1).deliver();

    Assert.isTrue(
      onlyFailure().contains('Slack returned channel_not_found. 2 alert(s) not sent (attempt 1).'),
      'The WARN names the cause'
    );
  }

  @IsTest
  static void deliver_notOkWithoutCode_warns() {
    useMocks();
    answer(200, '{"ok":false}', null);

    job(1, 1).deliver();

    Assert.isTrue(onlyFailure().contains('ok: false with no error code'), 'The WARN names the cause');
  }

  @IsTest
  static void deliver_unreadableBody_warns() {
    useMocks();
    answer(200, '<html>maintenance</html>', null);

    job(1, 1).deliver();

    Assert.isTrue(onlyFailure().contains('not Slack JSON'), 'The WARN names the cause');
  }

  @IsTest
  static void deliver_serverError_warnsWithoutRetry() {
    useMocks();
    answer(503, '', null);

    job(1, 1).deliver();

    Assert.isTrue(onlyFailure().contains('HTTP 503.'), 'The WARN names the cause');
    Assert.areEqual(0, enqueuer.jobs.size(), 'A resent POST could post twice, so no retry');
  }

  @IsTest
  static void deliver_calloutFails_warnsWithThePermissionSetHint() {
    useMocks();
    client.stubThrow('send', new CalloutClientException('We couldn\'t access the credential(s).'));

    job(1, 1).deliver();

    Assert.isTrue(onlyFailure().contains('assign the Slack_Alert_Sender permission set'), 'The WARN names the cause');
  }

  @IsTest
  static void deliver_rateLimitedFirstAttempt_reenqueuesOnceAfterRetryAfter() {
    useMocks();
    answer(429, '{"ok":false,"error":"ratelimited"}', '90');

    job(4, 1).deliver();

    Assert.areEqual(1, enqueuer.jobs.size(), 'One re-enqueue (D7)');
    Assert.areEqual(2, enqueuer.delays[0], '90 seconds rounds up to 2 minutes');
    Assert.areEqual(2, enqueuer.jobs[0].attempt, 'Second attempt');
    Assert.areEqual(4, enqueuer.jobs[0].alerts.size(), 'The same alerts');
    Assert.areEqual(AlertTestFixtures.CHANNEL, enqueuer.jobs[0].channel, 'The same channel');
    List<RecordingLogger.Entry> warnings = logger.entries(LoggingLevel.WARN);
    Assert.areEqual(1, warnings.size(), 'The retry is recorded');
    Assert.isTrue(warnings[0].message.contains('retrying once in 2 minute(s)'), warnings[0].message);
    Assert.areEqual(0, logger.entries(LoggingLevel.ERROR).size(), 'Never ERROR (D15)');
  }

  @IsTest
  static void deliver_rateLimitedSecondAttempt_dropsWithWarn() {
    useMocks();
    answer(429, '', '30');

    job(1, SlackAlertJob.MAX_ATTEMPTS).deliver();

    Assert.areEqual(0, enqueuer.jobs.size(), 'Only one re-enqueue per batch');
    Assert.isTrue(
      onlyFailure().contains('rate limited (HTTP 429) again after a retry. 1 alert(s) not sent (attempt 2).'),
      'The WARN names the cause'
    );
  }

  @IsTest
  static void deliver_retryCannotBeEnqueued_warns() {
    useMocks();
    enqueuer.failure = new AsyncException('Maximum stack depth');
    answer(429, '', null);

    job(1, 1).deliver();

    Assert.isTrue(
      onlyFailure().contains('the retry could not be enqueued: Maximum stack depth'),
      'The WARN names the cause'
    );
  }

  @IsTest
  static void delayMinutes_roundsUpAndClamps() {
    Assert.areEqual(1, SlackAlertJob.delayMinutes(null), 'No header: 1 minute');
    Assert.areEqual(1, SlackAlertJob.delayMinutes(0), 'Zero: the minimum');
    Assert.areEqual(1, SlackAlertJob.delayMinutes(30), '30 s rounds up to 1');
    Assert.areEqual(1, SlackAlertJob.delayMinutes(60), 'Exactly 1');
    Assert.areEqual(2, SlackAlertJob.delayMinutes(61), '61 s rounds up to 2');
    Assert.areEqual(AlertJobEnqueuer.MAX_DELAY_MINUTES, SlackAlertJob.delayMinutes(900), 'Clamped to 10');
  }

  // The single failure WARN, after checking it is the only entry, never ERROR, and flushed.
  private static String onlyFailure() {
    List<RecordingLogger.Entry> warnings = logger.entries(LoggingLevel.WARN);
    Assert.areEqual(1, warnings.size(), 'One WARN');
    Assert.isTrue(warnings[0].message.startsWith(SlackAlertJob.FAILURE_PREFIX), warnings[0].message);
    Assert.areEqual(0, logger.entries(LoggingLevel.ERROR).size(), 'Never ERROR (D15)');
    Assert.areEqual(1, logger.flushCount(), 'Flushed');
    return warnings[0].message;
  }
}
