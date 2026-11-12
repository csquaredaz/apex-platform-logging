@IsTest
private class LogEntryTest {
  @IsTest
  static void constructor_withoutCause_leavesExceptionFieldsBlank() {
    LogEntry entry = new LogEntry(LoggingLevel.INFO, 'Booking shipment for order 42', null);

    Assert.areEqual(LoggingLevel.INFO, entry.level, 'Level');
    Assert.areEqual('Booking shipment for order 42', entry.message, 'Message');
    Assert.isNull(entry.exceptionType, 'No exception type');
    Assert.isNull(entry.stackTrace, 'No stack trace');
    Assert.isNotNull(entry.loggedAt, 'Logged time is captured');
  }

  @IsTest
  static void constructor_nullArguments_defaultsSafely() {
    LogEntry entry = new LogEntry(null, null, null);

    Assert.areEqual(LoggingLevel.DEBUG, entry.level, 'A null level means DEBUG');
    Assert.areEqual('', entry.message, 'A null message becomes empty, not "null"');
  }

  @IsTest
  static void constructor_withCause_capturesExceptionDetail() {
    LogEntry entry = new LogEntry(LoggingLevel.ERROR, 'Commit failed', new DmlException('Required field missing'));

    Assert.areEqual('System.DmlException', entry.exceptionType, 'Exception type name');
    Assert.areEqual('Required field missing', entry.exceptionMessage, 'Exception message');
    Assert.isNotNull(entry.stackTrace, 'Stack trace is captured');
  }

  @IsTest
  static void constructor_twoEntries_takeConsecutiveSequences() {
    LogEntry first = new LogEntry(LoggingLevel.DEBUG, 'a', null);
    LogEntry second = new LogEntry(LoggingLevel.DEBUG, 'b', null);

    Assert.areEqual(first.sequence + 1, second.sequence, 'Sequence follows creation order');
  }

  @IsTest
  static void constructor_oversizedMessage_truncatesWithMarker() {
    String oversized = 'x'.repeat(LogEntry.MAX_TEXT_LENGTH + 10);

    LogEntry entry = new LogEntry(LoggingLevel.WARN, oversized, null);

    Assert.areEqual(LogEntry.MAX_TEXT_LENGTH, entry.message.length(), 'Cut to the field length');
    Assert.isTrue(entry.message.endsWith(LogEntry.TRUNCATION_MARKER), 'The cut is visible');
  }

  @IsTest
  static void truncate_atLimit_isUnchanged() {
    String exact = 'y'.repeat(20);

    Assert.areEqual(exact, LogEntry.truncate(exact, 20), 'Text at the limit is kept whole');
    Assert.isNull(LogEntry.truncate(null, 20), 'Null stays null');
  }

  @IsTest
  static void toEvent_withCause_mapsEveryField() {
    LogEntry entry = new LogEntry(LoggingLevel.ERROR, 'Commit failed', new DmlException('Required field missing'));

    Log_Event__e event = entry.toEvent();

    Assert.areEqual('ERROR', event.Level__c, 'Level__c');
    Assert.areEqual('Commit failed', event.Message__c, 'Message__c');
    Assert.areEqual('System.DmlException', event.Exception_Type__c, 'Exception_Type__c');
    Assert.areEqual('Required field missing', event.Exception_Message__c, 'Exception_Message__c');
    Assert.areEqual(entry.stackTrace, event.Stack_Trace__c, 'Stack_Trace__c');
    Assert.areEqual(LogContext.requestId(), event.Request_Id__c, 'Request_Id__c');
    Assert.areEqual(LogContext.quiddity(), event.Quiddity__c, 'Quiddity__c');
    Assert.areEqual(entry.sequence, event.Sequence__c, 'Sequence__c');
    Assert.areEqual(entry.loggedAt, event.Logged_At__c, 'Logged_At__c');
  }

  @IsTest
  static void toDebugString_withAndWithoutCause_rendersLevelSequenceAndDetail() {
    LogEntry plain = new LogEntry(LoggingLevel.INFO, 'Order received', null);
    LogEntry failed = new LogEntry(LoggingLevel.ERROR, 'Commit failed', new DmlException('Required field missing'));

    Assert.areEqual('[INFO] #' + plain.sequence + ' Order received', plain.toDebugString(), 'Plain entry');
    Assert.isTrue(
      failed.toDebugString()
        .startsWith('[ERROR] #' + failed.sequence + ' Commit failed | System.DmlException: Required field missing'),
      failed.toDebugString()
    );
  }
}
