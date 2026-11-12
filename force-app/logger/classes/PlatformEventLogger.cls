/**
 * @description `ILogger` adapter that publishes each entry as a `Log_Event__e` (Ports and
 * Adapters). It replaces A's `DebugLogger` through the `DI_Binding.Platform_Event_Logger` row, so
 * callers keep calling `Application.Service.newInstance(ILogger.class)` and need no code change.
 *
 * Entries are buffered per transaction in `LogBuffer` and published Publish Immediately, so they
 * survive a rollback (ADR 0003). Write messages as attempts ("Booking shipment for order X"),
 * not outcomes: the entry is published even if the work later rolls back.
 *
 * The logger never throws a catchable exception, so a logging failure can't break the caller's
 * work. `LogBuffer.flush` catches every publish failure and writes the entries to the debug log;
 * building an entry has no failure mode. A `LimitException` can't be caught in Apex, so
 * `LogBuffer` checks the publish limit before it publishes (ADR 0004).
 *
 * ```apex
 * ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);
 * logger.info('Booking shipment for order ' + orderId);
 * logger.flush();
 * ```
 * @group Public API
 */
public with sharing class PlatformEventLogger implements ILogger {
  /** @description See `ILogger.debug`. @param message The entry text. */
  public void debug(String message) {
    log(LoggingLevel.DEBUG, message, null);
  }

  /** @description See `ILogger.info`. @param message The entry text. */
  public void info(String message) {
    log(LoggingLevel.INFO, message, null);
  }

  /** @description See `ILogger.warn`. @param message The entry text. */
  public void warn(String message) {
    log(LoggingLevel.WARN, message, null);
  }

  /**
   * @description See `ILogger.error`. Flushes the buffer straight away, so the failure and the
   * entries before it are published even if the transaction ends abruptly.
   * @param message The entry text.
   * @param cause The exception, or null.
   */
  public void error(String message, Exception cause) {
    log(LoggingLevel.ERROR, message, cause);
    flush();
  }

  /** @description Publishes every buffered entry in this transaction. */
  public void flush() {
    LogBuffer.current().flush();
  }

  private void log(LoggingLevel level, String message, Exception cause) {
    if (LoggingSettings.current().accepts(level)) {
      LogBuffer.current().add(new LogEntry(level, message, cause));
    }
  }
}
