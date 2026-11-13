@IsTest
private class LogBufferTest {
  private static Mocks publisherMock;

  private static LogBuffer bufferOfSize(Integer bufferSize) {
    LoggingSettings.useRow(LoggerTestFixtures.settings('DEBUG', bufferSize));
    publisherMock = new Mocks();
    LogBuffer.useNew((ILogEventPublisher) publisherMock.stub(ILogEventPublisher.class));
    return LogBuffer.current();
  }

  private static LogEntry entry(String message) {
    return new LogEntry(LoggingLevel.INFO, message, null);
  }

  @IsTest
  static void add_belowBufferSize_holdsEntries() {
    LogBuffer buffer = bufferOfSize(3);

    buffer.add(entry('a'));
    buffer.add(entry('b'));

    Assert.areEqual(2, buffer.size(), 'Entries wait in the buffer');
    publisherMock.verify('publish', 0);
  }

  @IsTest
  static void add_reachesBufferSize_publishesOneBatch() {
    LogBuffer buffer = bufferOfSize(3);
    publisherMock.stubReturn('publish', LoggerTestFixtures.successes(3));

    buffer.add(entry('a'));
    buffer.add(entry('b'));
    buffer.add(entry('c'));

    publisherMock.verify('publish', 1);
    List<Log_Event__e> published = (List<Log_Event__e>) publisherMock.argumentsOf('publish', 0)[0];
    Assert.areEqual(3, published.size(), 'One publish call carries the whole batch');
    Assert.areEqual('a', published[0].Message__c, 'Order is kept');
    Assert.areEqual(0, buffer.size(), 'The buffer is empty after the flush');
    Assert.areEqual(0, LogFallback.count, 'Nothing fell back');
  }

  @IsTest
  static void add_null_isIgnored() {
    LogBuffer buffer = bufferOfSize(1);

    buffer.add(null);

    Assert.areEqual(0, buffer.size(), 'Null is not buffered');
    publisherMock.verify('publish', 0);
  }

  @IsTest
  static void flush_emptyBuffer_doesNotPublish() {
    LogBuffer buffer = bufferOfSize(5);

    buffer.flush();

    Assert.areEqual(0, publisherMock.callCount('publish'), 'Nothing to publish, so no publish call is spent');
  }

  @IsTest
  static void flush_partialFailure_fallsBackOnlyForFailedEntries() {
    LogBuffer buffer = bufferOfSize(10);
    List<Database.SaveResult> results = LoggerTestFixtures.successes(1);
    results.add(LoggerTestFixtures.failure('Event bus unavailable'));
    publisherMock.stubReturn('publish', results);
    buffer.add(entry('kept'));
    buffer.add(entry('lost'));

    buffer.flush();

    Assert.areEqual(1, LogFallback.count, 'Only the failed entry goes to the debug log');
    Assert.areEqual(0, buffer.size(), 'The buffer is empty either way');
  }

  @IsTest
  static void flush_missingResults_fallsBackForUnconfirmedEntries() {
    LogBuffer buffer = bufferOfSize(10);
    publisherMock.stubReturn('publish', LoggerTestFixtures.successes(1));
    buffer.add(entry('confirmed'));
    buffer.add(entry('unconfirmed'));

    buffer.flush();

    Assert.areEqual(1, LogFallback.count, 'An entry without a result is not assumed published');
  }

  @IsTest
  static void flush_publisherThrows_fallsBackWithoutThrowing() {
    LogBuffer buffer = bufferOfSize(10);
    publisherMock.stubThrow('publish', new DmlException('Event bus unavailable'));
    buffer.add(entry('a'));
    buffer.add(entry('b'));

    buffer.flush();

    Assert.areEqual(2, LogFallback.count, 'Every entry goes to the debug log');
    Assert.areEqual(0, buffer.size(), 'The buffer is empty, so the entries are not retried twice');
  }

  @IsTest
  static void flush_atPublishReserve_skipsPublishing() {
    LogBuffer buffer = bufferOfSize(10);
    LogBuffer.publishCallsLeftOverride = LogBuffer.PUBLISH_CALLS_RESERVED;
    buffer.add(entry('a'));

    buffer.flush();

    publisherMock.verify('publish', 0);
    Assert.areEqual(1, LogFallback.count, 'The entry goes to the debug log');
  }

  @IsTest
  static void flush_aboveReserve_publishes() {
    LogBuffer buffer = bufferOfSize(10);
    LogBuffer.publishCallsLeftOverride = LogBuffer.PUBLISH_CALLS_RESERVED + 1;
    publisherMock.stubReturn('publish', LoggerTestFixtures.successes(1));
    buffer.add(entry('a'));

    buffer.flush();

    Assert.areEqual(1, publisherMock.callCount('publish'), 'One call above the reserve still publishes');
    Assert.areEqual(0, LogFallback.count, 'Nothing fell back');
  }

  @IsTest
  static void current_withoutSeam_isSharedSingleton() {
    LogBuffer first = LogBuffer.current();

    Assert.areEqual(first, LogBuffer.current(), 'Every logger shares one buffer per transaction');
  }

  @IsTest
  static void add_whileSuppressed_writesToDebugLogInstead() {
    LogBuffer buffer = bufferOfSize(1);

    LogBuffer.suppress();
    buffer.add(entry('inside the subscriber'));
    LogBuffer.resume();

    publisherMock.verify('publish', 0);
    Assert.areEqual(0, buffer.size(), 'A suppressed entry is not buffered either');
    Assert.areEqual(1, LogFallback.count, 'It went to the debug log');
    Assert.areEqual(LogBuffer.SUPPRESSED_REASON, LogFallback.lastReason, 'The reason says why');
  }

  @IsTest
  static void flush_whileSuppressed_drainsToDebugLog() {
    LogBuffer buffer = bufferOfSize(5);
    buffer.add(entry('before suppression'));

    LogBuffer.suppress();
    buffer.flush();
    LogBuffer.resume();

    publisherMock.verify('publish', 0);
    Assert.areEqual(0, buffer.size(), 'The buffer is drained');
    Assert.areEqual(1, LogFallback.count, 'Buffered entries are never published while suppressed');
  }

  @IsTest
  static void resume_afterSuppress_publishesAgain() {
    LogBuffer buffer = bufferOfSize(1);
    publisherMock.stubReturn('publish', LoggerTestFixtures.successes(1));

    LogBuffer.suppress();
    Assert.isTrue(LogBuffer.isSuppressed(), 'suppress() turns publishing off');
    LogBuffer.resume();
    buffer.add(entry('after the subscriber'));

    Assert.isFalse(LogBuffer.isSuppressed(), 'resume() turns it back on');
    publisherMock.verify('publish', 1);
  }
}
