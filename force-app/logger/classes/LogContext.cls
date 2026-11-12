/**
 * @description Per-transaction identity for log entries: the Apex request Id, the execution
 * context (Quiddity) and a sequence number. `Request_Id__c` plus `Sequence__c` identifies an
 * entry, so persistence can upsert on it and a replayed event never makes a duplicate row.
 *
 * State is static, so it lasts exactly one transaction. Every async job starts a new request
 * with its own Id and a sequence starting at 1.
 * @group Logging
 */
public with sharing class LogContext {
  private static String requestId;
  private static String quiddity;
  private static Integer sequence = 0;

  /**
   * @description The Apex request Id of the current transaction.
   * @return The request Id; never blank.
   */
  public static String requestId() {
    load();
    return requestId;
  }

  /**
   * @description The execution context of the current transaction.
   * @return The `System.Quiddity` name, for example `SYNCHRONOUS` or `QUEUEABLE`.
   */
  public static String quiddity() {
    load();
    return quiddity;
  }

  /**
   * @description Claims the next sequence number in this transaction.
   * @return 1 on the first call, then 2, 3, and so on.
   */
  public static Integer nextSequence() {
    sequence += 1;
    return sequence;
  }

  private static void load() {
    if (requestId != null) {
      return;
    }
    Request current = Request.getCurrent();
    requestId = current.getRequestId();
    quiddity = current.getQuiddity().name();
  }
}
