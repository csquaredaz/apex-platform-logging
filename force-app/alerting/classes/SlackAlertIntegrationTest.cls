/**
 * @description Real Queueable, real `CalloutClient`, real event bus, with `HttpCalloutMock` in
 * place of Slack: a send becomes one Block Kit POST, the subscriber turns ERROR entries into one
 * alert batch, and a failed delivery is persisted at WARN without raising another alert
 * (D14, D15, ADR 0006). No Slack workspace or token is involved: `HttpCalloutMock` answers before
 * the External Credential is used, even for a user without principal access (R2).
 */
@IsTest
private class SlackAlertIntegrationTest {
  @IsTest
  static void send_asUserWithoutPrincipalAccess_postsOneBlockKitMessage() {
    User sender = LoggerTestFixtures.minimumAccessUser();
    AlertTestFixtures.SlackHttpMock slack = new AlertTestFixtures.SlackHttpMock(200, '{"ok":true}');
    Test.setMock(HttpCalloutMock.class, slack);
    LoggingSettings.useRow(AlertTestFixtures.settingsWithChannel(AlertTestFixtures.CHANNEL));

    Test.startTest();
    System.runAs(sender) {
      new SlackAlertSink().send(AlertTestFixtures.alerts(3));
    }
    Test.stopTest();

    Assert.areEqual(1, slack.requests.size(), 'One send, one POST');
    HttpRequest request = slack.requests[0];
    Assert.areEqual('POST', request.getMethod(), 'Method');
    Assert.areEqual('callout:Slack/chat.postMessage', request.getEndpoint(), 'Named Credential endpoint');
    Assert.areEqual('application/json', request.getHeader('Content-Type'), 'JSON body');
    Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(request.getBody());
    Assert.areEqual(AlertTestFixtures.CHANNEL, body.get('channel'), 'Channel from the settings');
    Assert.areEqual(7, ((List<Object>) body.get('blocks')).size(), 'Header plus two blocks per alert');
  }

  @IsTest
  static void subscriber_errorAndInfoEntries_sendsOneCriticalAlert() {
    Mocks sink = new Mocks();
    Application.Service.setMock(IAlertSink.class, sink.stub(IAlertSink.class));
    ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);

    Test.startTest();
    logger.info('Booking shipment for order 42');
    logger.error('Shipment booking failed for order 42', new DmlException('Required field missing'));
    Test.getEventBus().deliver();
    Test.stopTest();

    sink.verify('send', 1);
    List<Alert> alerts = (List<Alert>) sink.argumentsOf('send', 0)[0];
    Assert.areEqual(1, alerts.size(), 'Only the ERROR entry alerts');
    Assert.areEqual(Alert.Severity.CRITICAL, alerts[0].severity, 'ERROR maps to CRITICAL');
    Assert.areEqual('Shipment booking failed for order 42', alerts[0].title, 'Title from the message');
    Assert.areEqual('System.DmlException: Required field missing', alerts[0].detail, 'Detail from the exception');
    Assert.areEqual(2, [SELECT COUNT() FROM Log__c WITH SYSTEM_MODE], 'Both entries persisted');
  }

  @IsTest
  static void failedDelivery_isPersistedAtWarn_andRaisesNoAlert() {
    User sender = LoggerTestFixtures.minimumAccessUser();
    LoggerTestFixtures.assignPublisherPermissionSet(sender);
    Mocks sink = new Mocks();
    Application.Service.setMock(IAlertSink.class, sink.stub(IAlertSink.class));
    Test.setMock(
      HttpCalloutMock.class,
      new AlertTestFixtures.SlackHttpMock(200, '{"ok":false,"error":"channel_not_found"}')
    );
    LoggingSettings.useRow(AlertTestFixtures.settingsWithChannel(AlertTestFixtures.CHANNEL));

    Test.startTest();
    System.runAs(sender) {
      new SlackAlertSink().send(AlertTestFixtures.alerts(1));
    }
    Test.stopTest();
    Test.getEventBus().deliver();

    List<Log__c> logs = [SELECT Level__c, Message__c FROM Log__c WITH SYSTEM_MODE];
    Assert.areEqual(1, logs.size(), 'The failure was published and persisted');
    Assert.areEqual('WARN', logs[0].Level__c, 'At WARN (D15)');
    Assert.isTrue(logs[0].Message__c.startsWith(SlackAlertJob.FAILURE_PREFIX), logs[0].Message__c);
    Assert.isTrue(logs[0].Message__c.contains('channel_not_found'), logs[0].Message__c);
    sink.verify('send', 0);
  }
}
