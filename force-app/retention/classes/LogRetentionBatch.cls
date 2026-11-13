/**
 * @description Hard-deletes `Log__c` rows older than `Logging_Setting__mdt.Retention_Days__c`
 * (ADR 0007). Storage is the binding limit of a persisted log (R4), so retention keeps it bounded.
 * `LogRetentionSchedule` starts it; it can also be run once with
 * `Database.executeBatch(new LogRetentionBatch(), LogRetentionBatch.BATCH_SIZE)`.
 *
 * - **Start.** Computes the cutoff once (now minus the retention days) and queries through the
 *   `ILogsSelector` binding: system mode, without sharing, `CreatedDate` before the cutoff. With
 *   retention switched off it selects nothing.
 * - **Execute.** Re-reads the kill switch, so unticking `Is_Retention_Enabled__c` stops a run in
 *   progress. Each chunk is one Unit of Work with `SystemDml`: the delete, then a `RecycleBinPurge`.
 *   Limits per chunk of 2,000: 3 DML statements (savepoint, delete, purge), 4,000 DML rows, no SOQL.
 * - **Failures (D22).** A chunk that fails is rolled back, logged at WARN with its size and cause,
 *   and the run continues. `finish` logs an INFO summary, plus a WARN when any chunk failed. Nothing
 *   logs at ERROR, so retention can never raise a Slack alert (D15). An uncatchable failure (a
 *   `LimitException`) shows only as a failed `AsyncApexJob`.
 *
 * Running user: whoever scheduled it. It needs no `Log__c` permission, because the selector and
 * `SystemDml` run in system mode. It needs `Log_Event_Publisher` for its own log lines to reach
 * `Log__c`; without it they go to the debug log (ADR 0003).
 * @group Retention
 */
public with sharing class LogRetentionBatch implements Database.Batchable<SObject>, Database.Stateful {
  /** @description Rows per chunk: the most a query locator batch allows. */
  public static final Integer BATCH_SIZE = 2000;
  /** @description Prefixes every line the batch logs, so its entries can be found in `Log__c`. */
  public static final String LOG_PREFIX = 'Log retention: ';

  /** Test seam: the clock, so the cutoff can be asserted. */
  @TestVisible
  private static Datetime nowOverride;

  private Datetime cutoff;
  private Integer deletedRows = 0;
  private Integer failedChunks = 0;
  private Integer failedRows = 0;
  private Integer skippedChunks = 0;

  /**
   * @description Selects the rows to delete.
   * @param context The batch context.
   * @return A locator over the rows created before the cutoff, or over nothing when retention is off.
   */
  public Database.QueryLocator start(Database.BatchableContext context) {
    LoggingSettings settings = LoggingSettings.current();
    cutoff = settings.isRetentionEnabled ? cutoffFor(settings.retentionDays) : null;
    return ((ILogsSelector) Application.Selector.newInstance(Log__c.SObjectType)).queryLocatorCreatedBefore(cutoff);
  }

  /**
   * @description Hard-deletes one chunk, unless retention was switched off since the run started.
   * Never throws: a failed chunk is rolled back and logged at WARN.
   * @param context The batch context.
   * @param scope The rows of this chunk.
   */
  public void execute(Database.BatchableContext context, List<SObject> scope) {
    if (!LoggingSettings.current().isRetentionEnabled) {
      skippedChunks++;
      return;
    }
    try {
      IUnitOfWork unitOfWork = Application.UnitOfWork.newInstance(
        new List<SObjectType>{ Log__c.SObjectType },
        new SystemDml()
      );
      unitOfWork.registerDeleted(scope);
      unitOfWork.registerWork(new RecycleBinPurge(scope));
      unitOfWork.commitWork();
      deletedRows += scope.size();
    } catch (Exception chunkFailure) {
      failedChunks++;
      failedRows += scope.size();
      ILogger logger = logger();
      logger.warn(
        LOG_PREFIX +
          'a chunk of ' +
          scope.size() +
          ' rows was not deleted and will be retried on the next run: ' +
          chunkFailure.getTypeName() +
          ': ' +
          chunkFailure.getMessage()
      );
      logger.flush();
    }
  }

  /**
   * @description Logs the run's summary at INFO, and a WARN when any chunk failed.
   * @param context The batch context.
   */
  public void finish(Database.BatchableContext context) {
    ILogger logger = logger();
    logger.info(summary());
    if (failedChunks > 0) {
      logger.warn(
        LOG_PREFIX + failedChunks + ' chunk(s), ' + failedRows + ' rows, failed; see the WARN entries above.'
      );
    }
    logger.flush();
  }

  /**
   * @description The cutoff for a retention: rows created before it are deleted.
   * @param retentionDays Days to keep.
   * @return Now minus `retentionDays`.
   */
  @TestVisible
  private static Datetime cutoffFor(Integer retentionDays) {
    Datetime now = nowOverride == null ? Datetime.now() : nowOverride;
    return now.addDays(-retentionDays);
  }

  private String summary() {
    if (cutoff == null) {
      return LOG_PREFIX + 'switched off (Logging_Setting__mdt.Is_Retention_Enabled__c); nothing deleted.';
    }
    String text =
      LOG_PREFIX +
      'deleted ' +
      deletedRows +
      ' rows created before ' +
      cutoff.formatGmt('yyyy-MM-dd HH:mm') +
      ' GMT';
    if (skippedChunks > 0) {
      text += '; switched off during the run, so ' + skippedChunks + ' chunk(s) were skipped';
    }
    return text + '.';
  }

  private static ILogger logger() {
    return (ILogger) Application.Service.newInstance(ILogger.class);
  }
}
