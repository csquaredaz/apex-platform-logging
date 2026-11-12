/**
 * @description Persists `Log_Event__e` events as `Log__c` rows (Domain, ADR 0005). The
 * `LogEventTrigger` calls A's `TriggerDispatcher`, which builds this domain through the
 * `DI_Binding.Log_Events_Domain` row, so a `Trigger_Setting__mdt` row can switch persistence off.
 *
 * Each trigger batch is one upsert on `Log__c.Log_Key__c` through a Unit of Work with `SystemDml`:
 * the subscriber runs as the Automated Process user, and the rows are written for every logging
 * user, so persistence runs in system mode (D9). A redelivered event updates its row instead of
 * adding a second one.
 *
 * Failures (D11): `IDml` is all-or-none, so one bad row fails the batch. A failed commit throws
 * `EventBus.RetryableException` while the batch has been retried fewer than `MAX_RETRIES` times;
 * after that the batch is written to the debug log through `DebugLogger` and the subscriber moves
 * on, so a poison batch can't stop the event stream.
 *
 * Recursion (D12): `LogBuffer` is suppressed for the whole of `onAfterInsert`, so any `ILogger`
 * call made while persisting goes to the debug log and never publishes another log event.
 * @group Persistence
 */
public with sharing class LogEventsDomain extends SObjectDomain {
  /** @description Retries before a failing batch is given up and written to the debug log. */
  public static final Integer MAX_RETRIES = 3;
  /** @description Joins the request Id and the sequence in `Log_Key__c`. */
  public static final String KEY_SEPARATOR = '-';
  /** @description Prefixes the event UUID in `Log_Key__c` when the request Id or sequence is missing. */
  public static final String UUID_KEY_PREFIX = 'uuid-';

  /** Test seam: the retry count, because `EventBus.TriggerContext` exists only in a real delivery. */
  @TestVisible
  private static Integer retriesOverride;

  /** Test seam: where a given-up batch goes. Never `Application.Service`, which would publish (D9). */
  @TestVisible
  private static ILogger fallbackLogger = new DebugLogger();

  /**
   * @description Creates the domain over a trigger batch.
   * @param records The `Log_Event__e` events.
   */
  public LogEventsDomain(List<SObject> records) {
    super(records);
  }

  /**
   * @description The type this domain owns.
   * @return `Log_Event__e.SObjectType`.
   */
  public override SObjectType getSObjectType() {
    return Log_Event__e.SObjectType;
  }

  /**
   * @description Upserts one `Log__c` per event, with `LogBuffer` suppressed throughout.
   * @throws EventBus.RetryableException If the commit fails and the batch can still be retried.
   */
  public override void onAfterInsert() {
    LogBuffer.suppress();
    try {
      persist(toLogs());
    } finally {
      LogBuffer.resume();
    }
  }

  /**
   * @description The upsert key of an event: `Request_Id__c-Sequence__c`, or `uuid-<EventUuid>`
   * when either part is missing.
   * @param event The event.
   * @return The key, or null when the event has neither; a null key inserts a new row.
   */
  public static String keyOf(Log_Event__e event) {
    if (String.isNotBlank(event.Request_Id__c) && event.Sequence__c != null) {
      return event.Request_Id__c + KEY_SEPARATOR + event.Sequence__c.intValue();
    }
    return String.isBlank(event.EventUuid) ? null : UUID_KEY_PREFIX + event.EventUuid;
  }

  // One row per key: an upsert list with a repeated key fails the whole batch. Last one wins.
  private List<Log__c> toLogs() {
    List<Log__c> rows = new List<Log__c>();
    Map<String, Log__c> rowsByKey = new Map<String, Log__c>();
    for (Log_Event__e event : (List<Log_Event__e>) records) {
      Log__c row = toLog(event);
      if (row.Log_Key__c == null) {
        rows.add(row);
      } else {
        rowsByKey.put(row.Log_Key__c, row);
      }
    }
    rows.addAll(rowsByKey.values());
    return rows;
  }

  private static Log__c toLog(Log_Event__e event) {
    return new Log__c(
      Log_Key__c = keyOf(event),
      Level__c = event.Level__c,
      Message__c = event.Message__c,
      Exception_Type__c = event.Exception_Type__c,
      Exception_Message__c = event.Exception_Message__c,
      Stack_Trace__c = event.Stack_Trace__c,
      Request_Id__c = event.Request_Id__c,
      Sequence__c = event.Sequence__c,
      Quiddity__c = event.Quiddity__c,
      Logged_At__c = event.Logged_At__c,
      Logged_By__c = event.CreatedById
    );
  }

  private static void persist(List<Log__c> rows) {
    try {
      IUnitOfWork unitOfWork = Application.UnitOfWork.newInstance(
        new List<SObjectType>{ Log__c.SObjectType },
        new SystemDml()
      );
      unitOfWork.registerUpsert(rows, Log__c.Log_Key__c);
      unitOfWork.commitWork();
    } catch (Exception commitFailure) {
      Integer retries = retries();
      if (retries < MAX_RETRIES) {
        throw new EventBus.RetryableException(
          'Log persistence failed on attempt ' +
            (retries + 1) +
            ' of ' +
            (MAX_RETRIES + 1) +
            ': ' +
            commitFailure.getMessage()
        );
      }
      giveUp(rows, commitFailure);
    }
  }

  private static void giveUp(List<Log__c> rows, Exception cause) {
    fallbackLogger.error(
      'Log persistence gave up after ' + MAX_RETRIES + ' retries; ' + rows.size() + ' entries follow in the debug log.',
      cause
    );
    for (Log__c row : rows) {
      fallbackLogger.warn('Unpersisted log ' + row.Log_Key__c + ' [' + row.Level__c + '] ' + row.Message__c);
    }
  }

  private static Integer retries() {
    if (retriesOverride != null) {
      return retriesOverride;
    }
    return EventBus.TriggerContext.currentContext().retries;
  }

  /** @description Builds the domain for `DomainFactory` (bound by `DI_Binding.Log_Events_Domain`). */
  public class Constructor implements IDomainConstructor {
    /**
     * @description Creates the domain.
     * @param records The events.
     * @return A `LogEventsDomain`.
     */
    public IDomain construct(List<SObject> records) {
      return new LogEventsDomain(records);
    }
  }
}
