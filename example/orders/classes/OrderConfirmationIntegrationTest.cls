/**
 * @description End to end, with real DML and a real event bus: a consumer logs through `ILogger`,
 * the entries become `Log__c` rows, and an ERROR raises one CRITICAL alert, even though the
 * failed work rolls back. The alert sink is mocked, so nothing is sent to Slack.
 */
@IsTest
private class OrderConfirmationIntegrationTest {
  private static Mocks alertSink;

  private static List<Order> insertOrders(Integer count) {
    Account customer = new Account(Name = 'Example Customer');
    insert as system customer;
    List<Order> orders = new List<Order>();
    for (Integer i = 0; i < count; i++) {
      orders.add(new Order(AccountId = customer.Id, EffectiveDate = Date.today(), Status = 'Draft'));
    }
    insert as system orders;
    return orders;
  }

  private static void mockAlertSink() {
    alertSink = new Mocks();
    Application.Service.setMock(IAlertSink.class, alertSink.stub(IAlertSink.class));
  }

  private static List<Log__c> persistedLogs() {
    return [SELECT Level__c, Message__c, Exception_Type__c FROM Log__c WITH SYSTEM_MODE ORDER BY Sequence__c];
  }

  @IsTest
  static void confirm_twoHundredOrders_updatesThemAndPersistsOneInfoEntry() {
    List<Order> orders = insertOrders(200);
    mockAlertSink();

    Test.startTest();
    new OrderConfirmationService().confirm(orders);
    Test.getEventBus().deliver();
    Test.stopTest();

    Set<Id> orderIds = new Map<Id, Order>(orders).keySet();
    for (Order confirmed : [SELECT Description FROM Order WHERE Id IN :orderIds WITH SYSTEM_MODE]) {
      Assert.areEqual(OrderConfirmationService.CONFIRMED_NOTE, confirmed.Description, 'Confirmed');
    }
    List<Log__c> logs = persistedLogs();
    Assert.areEqual(1, logs.size(), 'One entry for the whole batch');
    Assert.areEqual('INFO', logs[0].Level__c, 'Level');
    Assert.areEqual('Confirming 200 order(s) for fulfilment', logs[0].Message__c, 'Message');
    alertSink.verify('send', 0);
  }

  @IsTest
  static void confirm_updateFails_entriesSurviveTheRollbackAndRaiseOneAlert() {
    List<Order> orders = insertOrders(2);
    delete as system orders[1];
    mockAlertSink();

    Test.startTest();
    try {
      new OrderConfirmationService().confirm(orders);
      Assert.fail('Updating a deleted order fails');
    } catch (DmlException expected) {
      Assert.isNotNull(expected.getMessage(), 'The caller still sees the failure');
    }
    Test.getEventBus().deliver();
    Test.stopTest();

    List<Log__c> logs = persistedLogs();
    Assert.areEqual(2, logs.size(), 'The attempt and the failure are both persisted');
    Assert.areEqual('INFO', logs[0].Level__c, 'The attempt');
    Assert.areEqual('ERROR', logs[1].Level__c, 'The failure');
    Assert.areEqual('System.DmlException', logs[1].Exception_Type__c, 'Exception type');
    alertSink.verify('send', 1);
    List<Alert> alerts = (List<Alert>) alertSink.argumentsOf('send', 0)[0];
    Assert.areEqual(1, alerts.size(), 'One alert, for the ERROR only');
    Assert.areEqual(Alert.Severity.CRITICAL, alerts[0].severity, 'Severity');
    Assert.areEqual('Order confirmation failed for 2 order(s)', alerts[0].title, 'Title');
  }

  @IsTest
  static void confirm_nullOrEmpty_logsNothing() {
    new OrderConfirmationService().confirm(null);
    new OrderConfirmationService().confirm(new List<Order>());

    Assert.areEqual(0, Limits.getPublishImmediateDml(), 'Nothing to confirm, nothing published');
  }
}
