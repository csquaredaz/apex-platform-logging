/**
 * @description Tests for `LogFallback`: how a failed publish is described, and that every entry
 * written is counted with its reason.
 */
@IsTest
private class LogFallbackTest {
  private static Database.SaveResult result(String errorsJson) {
    return (Database.SaveResult) JSON.deserialize(
      '{"success":false,"errors":' + errorsJson + '}',
      Database.SaveResult.class
    );
  }

  @IsTest
  static void describe_nullResult_saysNoneWasReturned() {
    Assert.areEqual('no result returned', LogFallback.describe(null), 'A missing result');
  }

  @IsTest
  static void describe_accessError_addsThePermissionHint() {
    String reason = LogFallback.describe(
      result('[{"statusCode":"CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY","message":"Access to entity denied","fields":[]}]')
    );

    Assert.areEqual(
      'CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY Access to entity denied; ' + LogFallback.PERMISSION_HINT,
      reason,
      'The status, the message and the fix'
    );
  }

  @IsTest
  static void describe_twoErrors_joinsThemWithoutAHint() {
    String reason = LogFallback.describe(
      result(
        '[{"statusCode":"UNKNOWN_EXCEPTION","message":"first","fields":[]},' +
        '{"statusCode":"LIMIT_EXCEEDED","message":"second","fields":[]}]'
      )
    );

    Assert.areEqual('UNKNOWN_EXCEPTION first; LIMIT_EXCEEDED second', reason, 'Both errors, no hint');
  }

  @IsTest
  static void write_entries_countsEachAndKeepsTheReason() {
    LogEntry entry = new LogEntry(LoggingLevel.WARN, 'Booking shipment for order 42', null);

    LogFallback.write(new List<LogEntry>{ entry, entry }, 'publish-immediate limit reserve reached');

    Assert.areEqual(2, LogFallback.count, 'Each entry is counted');
    Assert.areEqual('publish-immediate limit reserve reached', LogFallback.lastReason, 'The reason');
  }
}
