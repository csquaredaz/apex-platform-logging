/**
 * @description Holds log entries for the current transaction and publishes them in batches
 * (ADR 0004). It is a per-transaction singleton because A's `ServiceFactory` returns a new
 * `ILogger` on every call: every logger instance shares this one buffer.
 *
 * Flush happens on `flush()`, when the buffer reaches `LoggingSettings.bufferSize`, and on every
 * `error()` (the logger calls `flush()`). Each flush is one publish call.
 *
 * Fail-safe rules: the buffer never throws. When fewer than `PUBLISH_CALLS_RESERVED`
 * publish-immediate calls are left, when the publisher throws, or when an event fails, the
 * affected entries go to the debug log instead. A `LimitException` can't be caught in Apex, which
 * is why the limit is checked before publishing rather than handled after.
 *
 * Publishing needs Create on `Log_Event__e` for the running user, even from Apex, so every user
 * whose code logs needs the `Log_Event_Publisher` permission set (ADR 0003).
 * @group Logging
 */
public with sharing class LogBuffer {
  /**
   * @description Publish-immediate calls left for the host application. The logger stops
   * publishing when only this many remain, so logging never takes the last calls.
   */
  public static final Integer PUBLISH_CALLS_RESERVED = 5;

  /** @description Added to an access failure, because a missing assignment is the usual cause. */
  public static final String PERMISSION_HINT = 'Assign the Log_Event_Publisher permission set to this user.';

  private static LogBuffer instance;

  @TestVisible
  private static Integer publishCallsLeftOverride;
  @TestVisible
  private static Integer debugFallbackCount = 0;
  @TestVisible
  private static String lastFallbackReason;

  private final ILogEventPublisher publisher;
  private final List<LogEntry> entries = new List<LogEntry>();

  /**
   * @description The buffer for this transaction.
   * @return The shared buffer; created on first use with the event bus publisher.
   */
  public static LogBuffer current() {
    if (instance == null) {
      instance = new LogBuffer(new EventBusPublisher());
    }
    return instance;
  }

  /**
   * @description Test seam: replaces the transaction's buffer with an empty one.
   * @param publisher The publisher the new buffer uses, for example a `Mocks` stub.
   */
  @TestVisible
  private static void useNew(ILogEventPublisher publisher) {
    instance = new LogBuffer(publisher);
  }

  private LogBuffer(ILogEventPublisher publisher) {
    this.publisher = publisher;
  }

  /**
   * @description Adds an entry, and flushes when the buffer is full.
   * @param entry The entry; null is ignored.
   */
  public void add(LogEntry entry) {
    if (entry == null) {
      return;
    }
    entries.add(entry);
    if (entries.size() >= LoggingSettings.current().bufferSize) {
      flush();
    }
  }

  /**
   * @description The number of entries waiting to be published.
   * @return The buffered entry count.
   */
  public Integer size() {
    return entries.size();
  }

  /**
   * @description Publishes every buffered entry in one call and empties the buffer. Entries that
   * can't be published are written to the debug log. Never throws a catchable exception.
   */
  public void flush() {
    if (entries.isEmpty()) {
      return;
    }
    List<LogEntry> batch = new List<LogEntry>(entries);
    entries.clear();

    if (publishCallsLeft() <= PUBLISH_CALLS_RESERVED) {
      writeToDebugLog(batch, 'publish-immediate limit reserve reached');
      return;
    }
    try {
      publishBatch(batch);
    } catch (Exception publishFailure) {
      writeToDebugLog(batch, 'publish threw ' + publishFailure.getTypeName() + ': ' + publishFailure.getMessage());
    }
  }

  private void publishBatch(List<LogEntry> batch) {
    List<Log_Event__e> events = new List<Log_Event__e>();
    for (LogEntry entry : batch) {
      events.add(entry.toEvent());
    }
    List<Database.SaveResult> results = publisher.publish(events);
    for (Integer i = 0; i < batch.size(); i++) {
      Database.SaveResult result = results == null || i >= results.size() ? null : results[i];
      if (result == null || !result.isSuccess()) {
        writeToDebugLog(new List<LogEntry>{ batch[i] }, 'publish failed: ' + describe(result));
      }
    }
  }

  private static Integer publishCallsLeft() {
    if (publishCallsLeftOverride != null) {
      return publishCallsLeftOverride;
    }
    return Limits.getLimitPublishImmediateDML() - Limits.getPublishImmediateDML();
  }

  private static String describe(Database.SaveResult result) {
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

  private static void writeToDebugLog(List<LogEntry> batch, String reason) {
    lastFallbackReason = reason;
    for (LogEntry entry : batch) {
      System.debug(LoggingLevel.ERROR, 'LogBuffer fallback (' + reason + '): ' + entry.toDebugString());
      debugFallbackCount++;
    }
  }
}
