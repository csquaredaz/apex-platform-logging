/**
 * @description One immutable log entry (Value Object). It captures its context when it is
 * created, not when it is flushed, so `Logged_At__c` and `Sequence__c` reflect the call order.
 *
 * Long text is cut to `MAX_TEXT_LENGTH` with a visible marker, so an oversized message never
 * makes the event fail to publish.
 * @group Logging
 */
public with sharing class LogEntry {
  /** @description The longest text kept per field; matches the `Log_Event__e` long text fields. */
  public static final Integer MAX_TEXT_LENGTH = 32768;
  /** @description Appended to text that was cut. */
  public static final String TRUNCATION_MARKER = '...[truncated]';

  private static final Integer EXCEPTION_TYPE_LENGTH = 255;

  /** @description The entry's level: DEBUG, INFO, WARN or ERROR. */
  public final LoggingLevel level;
  /** @description The entry text, never null. */
  public final String message;
  /** @description The exception type name, or null. */
  public final String exceptionType;
  /** @description The exception message, or null. */
  public final String exceptionMessage;
  /** @description The exception stack trace, or null. */
  public final String stackTrace;
  /** @description The entry's position in its transaction. */
  public final Integer sequence;
  /** @description When the entry was logged. */
  public final Datetime loggedAt;

  /**
   * @description Creates an entry and claims the next sequence number.
   * @param level The entry's level; null means DEBUG.
   * @param message The entry text; null becomes empty.
   * @param cause The exception, or null.
   */
  public LogEntry(LoggingLevel level, String message, Exception cause) {
    this.level = level == null ? LoggingLevel.DEBUG : level;
    this.message = truncate(message == null ? '' : message, MAX_TEXT_LENGTH);
    if (cause != null) {
      this.exceptionType = truncate(cause.getTypeName(), EXCEPTION_TYPE_LENGTH);
      this.exceptionMessage = truncate(cause.getMessage(), MAX_TEXT_LENGTH);
      this.stackTrace = truncate(cause.getStackTraceString(), MAX_TEXT_LENGTH);
    }
    this.sequence = LogContext.nextSequence();
    this.loggedAt = Datetime.now();
  }

  /**
   * @description Maps the entry to the event that carries it.
   * @return A new, unpublished `Log_Event__e`.
   */
  public Log_Event__e toEvent() {
    return new Log_Event__e(
      Level__c = level.name(),
      Message__c = message,
      Exception_Type__c = exceptionType,
      Exception_Message__c = exceptionMessage,
      Stack_Trace__c = stackTrace,
      Request_Id__c = LogContext.requestId(),
      Quiddity__c = LogContext.quiddity(),
      Sequence__c = sequence,
      Logged_At__c = loggedAt
    );
  }

  /**
   * @description Renders the entry for the debug log, used when publishing fails.
   * @return One line per entry, plus the exception detail when there is one.
   */
  public String toDebugString() {
    String text = '[' + level.name() + '] #' + sequence + ' ' + message;
    if (exceptionType != null) {
      text += ' | ' + exceptionType + ': ' + exceptionMessage + '\n' + stackTrace;
    }
    return text;
  }

  @TestVisible
  private static String truncate(String value, Integer maxLength) {
    if (value == null || value.length() <= maxLength) {
      return value;
    }
    return value.left(maxLength - TRUNCATION_MARKER.length()) + TRUNCATION_MARKER;
  }
}
