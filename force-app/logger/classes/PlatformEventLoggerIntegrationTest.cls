/**
 * @description Real event bus, real metadata: proves the binding row, the publish-call count of a
 * bulk run, and that publishing needs the Log_Event_Publisher permission set.
 */
@IsTest
private class PlatformEventLoggerIntegrationTest {
  @IsTest
  static void applicationService_withBindingRow_returnsPlatformEventLogger() {
    ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);

    Assert.isInstanceOfType(
      logger,
      PlatformEventLogger.class,
      'DI_Binding.Platform_Event_Logger overrides DebugLogger'
    );
  }

  @IsTest
  static void bulk_200Entries_publishesInFourCalls() {
    LoggingSettings.useRow(LoggerTestFixtures.settings('DEBUG', 50));
    ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);

    Test.startTest();
    for (Integer i = 0; i < 200; i++) {
      logger.info('Shipment ' + i + ' booked');
    }
    logger.flush();
    Integer publishCalls = Limits.getPublishImmediateDML();
    Test.stopTest();

    Assert.areEqual(4, publishCalls, '200 entries at a buffer of 50 make 4 publish calls');
    Assert.areEqual(0, LogFallback.count, 'Every entry was published');
  }

  @IsTest
  static void minimumAccessUser_withoutPermissionSet_fallsBackWithHint() {
    User minimumAccess = LoggerTestFixtures.minimumAccessUser();

    Test.startTest();
    System.runAs(minimumAccess) {
      ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);
      logger.error('Commit failed', new DmlException('Required field missing'));
    }
    Test.stopTest();

    Assert.areEqual(1, LogFallback.count, 'The event bus rejects the entry, so it goes to the debug log');
    Assert.isTrue(
      LogFallback.lastReason.contains(LogFallback.PERMISSION_HINT),
      'The fallback names the fix: ' + LogFallback.lastReason
    );
  }

  @IsTest
  static void minimumAccessUser_withPermissionSet_publishes() {
    User minimumAccess = LoggerTestFixtures.minimumAccessUser();
    LoggerTestFixtures.assignPublisherPermissionSet(minimumAccess);

    Test.startTest();
    System.runAs(minimumAccess) {
      ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);
      logger.error('Commit failed', new DmlException('Required field missing'));
    }
    Test.stopTest();

    Assert.areEqual(0, LogFallback.count, 'Published: ' + LogFallback.lastReason);
  }
}
