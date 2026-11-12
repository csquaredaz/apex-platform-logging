@IsTest
private class PlatformEventLoggerTest {
  private static Mocks publisherMock;

  private static ILogger loggerWith(String minimumLevel, Integer bufferSize) {
    LoggingSettings.useRow(LoggerTestFixtures.settings(minimumLevel, bufferSize));
    publisherMock = new Mocks().stubReturn('publish', LoggerTestFixtures.successes(bufferSize));
    LogBuffer.useNew((ILogEventPublisher) publisherMock.stub(ILogEventPublisher.class));
    return new PlatformEventLogger();
  }

  private static List<Log_Event__e> published(Integer callIndex) {
    return (List<Log_Event__e>) publisherMock.argumentsOf('publish', callIndex)[0];
  }

  @IsTest
  static void everyLevel_minimumDebug_buffersEachEntry() {
    ILogger logger = loggerWith('DEBUG', 10);

    logger.debug('d');
    logger.info('i');
    logger.warn('w');

    Assert.areEqual(3, LogBuffer.current().size(), 'DEBUG, INFO and WARN are buffered');
    publisherMock.verify('publish', 0);
  }

  @IsTest
  static void belowMinimum_isDropped() {
    ILogger logger = loggerWith('WARN', 10);

    logger.debug('dropped');
    logger.info('dropped');
    logger.warn('kept');

    Assert.areEqual(1, LogBuffer.current().size(), 'Only WARN reaches the buffer');
  }

  @IsTest
  static void error_flushesEverythingImmediately() {
    ILogger logger = loggerWith('DEBUG', 10);
    logger.info('Booking shipment for order 42');

    logger.error('Carrier rejected the booking', new CalloutException('503'));

    publisherMock.verify('publish', 1);
    List<Log_Event__e> events = published(0);
    Assert.areEqual(2, events.size(), 'The entries before the error are published with it');
    Assert.areEqual('INFO', events[0].Level__c, 'Earlier entry first');
    Assert.areEqual('ERROR', events[1].Level__c, 'Then the error');
    Assert.areEqual('System.CalloutException', events[1].Exception_Type__c, 'With its exception');
  }

  @IsTest
  static void flush_publishesBufferedEntries() {
    ILogger logger = loggerWith('DEBUG', 10);
    logger.info('Order received');

    logger.flush();

    publisherMock.verify('publish', 1);
    Assert.areEqual(0, LogBuffer.current().size(), 'The buffer is empty');
  }

  @IsTest
  static void disabled_publishesNothing() {
    Logging_Setting__mdt row = LoggerTestFixtures.settings('DEBUG', 10);
    row.Is_Enabled__c = false;
    LoggingSettings.useRow(row);
    publisherMock = new Mocks();
    LogBuffer.useNew((ILogEventPublisher) publisherMock.stub(ILogEventPublisher.class));
    ILogger logger = new PlatformEventLogger();

    logger.error('Ignored', new DmlException('x'));

    Assert.areEqual(0, publisherMock.callCount('publish'), 'The kill switch drops entries before the buffer');
    Assert.areEqual(0, LogBuffer.current().size(), 'Nothing is buffered');
  }

  @IsTest
  static void separateInstances_shareOneBuffer() {
    loggerWith('DEBUG', 10);

    new PlatformEventLogger().info('first');
    new PlatformEventLogger().info('second');

    Assert.areEqual(2, LogBuffer.current().size(), 'A new instance per newInstance call still shares the buffer');
  }

  @IsTest
  static void publisherThrows_loggerDoesNotThrow() {
    ILogger logger = loggerWith('DEBUG', 10);
    publisherMock.stubThrow('publish', new DmlException('Event bus unavailable'));

    logger.error('Carrier rejected the booking', null);

    Assert.areEqual(1, LogBuffer.debugFallbackCount, 'The entry went to the debug log instead');
  }
}
