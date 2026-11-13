/**
 * @description Where log entries go when they can't be published (ADR 0004): the debug log, with
 * a reason. `LogBuffer` decides when to fall back; this class says why and writes the entries.
 * It never throws.
 * @group Logging
 */
public with sharing class LogFallback {
  /** @description Added to an access failure, because a missing assignment is the usual cause. */
  public static final String PERMISSION_HINT = 'Assign the Log_Event_Publisher permission set to this user.';

  @TestVisible
  private static Integer count = 0;
  @TestVisible
  private static String lastReason;

  /**
   * @description Writes the entries to the debug log at `ERROR`, so they show in any trace.
   * @param entries The entries that weren't published.
   * @param reason Why, for example `publish-immediate limit reserve reached`.
   */
  public static void write(List<LogEntry> entries, String reason) {
    lastReason = reason;
    for (LogEntry entry : entries) {
      System.debug(LoggingLevel.ERROR, 'LogBuffer fallback (' + reason + '): ' + entry.toDebugString());
      count++;
    }
  }

  /**
   * @description The reason an event failed to publish, with a permission hint for an access error.
   * @param result The event's save result, or null when the publisher returned none.
   * @return Each error's status code and message, joined by `; `.
   */
  public static String describe(Database.SaveResult result) {
    if (result == null) {
      return 'no result returned';
    }
    List<String> messages = new List<String>();
    for (Database.Error error : result.getErrors()) {
      messages.add(error.getStatusCode() + ' ' + error.getMessage());
      if (error.getStatusCode() == StatusCode.CANNOT_INSERT_UPDATE_ACTIVATE_ENTITY) {
        messages.add(PERMISSION_HINT);
      }
    }
    return String.join(messages, '; ');
  }
}
