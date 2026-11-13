/**
 * @description Unit tests for `LogRetentionBatch` with a mock selector and Unit of Work: the
 * cutoff, the kill switch in `start` and `execute`, the delete-then-purge registration, and that
 * every failure is a WARN, never an ERROR (D15, D22).
 */
@IsTest
private class LogRetentionBatchTest {
  private static final Datetime NOW = Datetime.newInstanceGmt(2026, 11, 13, 2, 0, 0);
  private static Mocks selectorMock;
  private static Mocks unitOfWorkMock;
  private static RecordingLogger logger;

  private static void useMocks(Integer retentionDays, Boolean retentionEnabled) {
    Logging_Setting__mdt row = LoggerTestFixtures.settings('DEBUG', 50);
    row.Retention_Days__c = retentionDays;
    row.Is_Retention_Enabled__c = retentionEnabled;
    LoggingSettings.useRow(row);
    LogRetentionBatch.nowOverride = NOW;
    selectorMock = new Mocks();
    selectorMock.stubReturn('getSObjectType', Log__c.SObjectType);
    selectorMock.stubReturn('queryLocatorCreatedBefore', Database.getQueryLocator('SELECT Id FROM Log__c LIMIT 0'));
    Application.Selector.setMock(Log__c.SObjectType, (ISelector) selectorMock.stub(ILogsSelector.class));
    unitOfWorkMock = new Mocks();
    Application.UnitOfWork.setMock((IUnitOfWork) unitOfWorkMock.stub(IUnitOfWork.class));
    logger = new RecordingLogger();
    Application.Service.setMock(ILogger.class, logger);
  }

  private static List<Log__c> chunk(Integer size) {
    List<Log__c> rows = new List<Log__c>();
    for (Integer i = 0; i < size; i++) {
      rows.add(new Log__c(Id = FakeId.generate(Log__c.SObjectType)));
    }
    return rows;
  }

  private static void assertNoErrors() {
    Assert.areEqual(0, logger.entries(LoggingLevel.ERROR).size(), 'Retention never logs at ERROR (D15)');
  }

  @IsTest
  static void start_enabled_queriesRowsOlderThanTheRetention() {
    useMocks(10, true);

    new LogRetentionBatch().start(null);

    selectorMock.verify('queryLocatorCreatedBefore', 1);
    Assert.areEqual(
      NOW.addDays(-10),
      (Datetime) selectorMock.argumentsOf('queryLocatorCreatedBefore', 0)[0],
      'Cutoff is now minus the retention days'
    );
  }

  @IsTest
  static void start_disabled_selectsNothingAndFinishSaysSo() {
    useMocks(10, false);
    LogRetentionBatch batch = new LogRetentionBatch();

    batch.start(null);
    batch.finish(null);

    Assert.isNull(selectorMock.argumentsOf('queryLocatorCreatedBefore', 0)[0], 'A null cutoff selects nothing');
    List<RecordingLogger.Entry> infos = logger.entries(LoggingLevel.INFO);
    Assert.areEqual(1, infos.size(), 'One summary');
    Assert.isTrue(infos[0].message.contains('switched off'), 'The summary says retention is off: ' + infos[0].message);
    assertNoErrors();
  }

  @IsTest
  static void execute_chunk_registersDeleteThenPurgeInOneCommit() {
    useMocks(30, true);
    List<Log__c> rows = chunk(3);

    new LogRetentionBatch().execute(null, rows);

    unitOfWorkMock.verify('registerDeleted', 1);
    Assert.areEqual(rows, unitOfWorkMock.argumentsOf('registerDeleted', 0)[0], 'The whole chunk is deleted');
    unitOfWorkMock.verify('registerWork', 1);
    Assert.isInstanceOfType(
      unitOfWorkMock.argumentsOf('registerWork', 0)[0],
      RecycleBinPurge.class,
      'The deleted rows are emptied from the Recycle Bin'
    );
    unitOfWorkMock.verify('commitWork', 1);
    Assert.areEqual(0, logger.entries().size(), 'A good chunk logs nothing');
  }

  @IsTest
  static void execute_switchedOffDuringTheRun_skipsTheChunk() {
    useMocks(30, true);
    LogRetentionBatch batch = new LogRetentionBatch();
    batch.start(null);
    Logging_Setting__mdt off = LoggerTestFixtures.settings('DEBUG', 50);
    off.Is_Retention_Enabled__c = false;
    LoggingSettings.useRow(off);

    batch.execute(null, chunk(2));
    batch.finish(null);

    unitOfWorkMock.verify('commitWork', 0);
    String summary = logger.entries(LoggingLevel.INFO)[0].message;
    Assert.isTrue(summary.contains('deleted 0 rows'), 'Nothing deleted: ' + summary);
    Assert.isTrue(summary.contains('1 chunk(s) were skipped'), 'The skip is reported: ' + summary);
  }

  @IsTest
  static void execute_commitFails_logsWarnAndTheRunContinues() {
    useMocks(30, true);
    unitOfWorkMock.stubThrow('commitWork', new DmlException('UNABLE_TO_LOCK_ROW'));
    LogRetentionBatch batch = new LogRetentionBatch();
    batch.start(null);

    batch.execute(null, chunk(4));
    batch.execute(null, chunk(5));
    batch.finish(null);

    unitOfWorkMock.verify('commitWork', 2);
    List<RecordingLogger.Entry> warnings = logger.entries(LoggingLevel.WARN);
    Assert.areEqual(3, warnings.size(), 'One WARN per failed chunk, plus the summary WARN');
    Assert.isTrue(warnings[0].message.contains('a chunk of 4 rows'), 'Chunk size: ' + warnings[0].message);
    Assert.isTrue(
      warnings[0].message.contains('System.DmlException: UNABLE_TO_LOCK_ROW'),
      'Cause: ' + warnings[0].message
    );
    Assert.isTrue(warnings[2].message.contains('2 chunk(s), 9 rows, failed'), 'Totals: ' + warnings[2].message);
    Assert.isTrue(
      logger.entries(LoggingLevel.INFO)[0].message.contains('deleted 0 rows'),
      'Nothing counted as deleted'
    );
    Assert.isTrue(logger.flushCount() >= 3, 'Each chunk and the summary flush their own lines');
    assertNoErrors();
  }

  @IsTest
  static void finish_afterGoodChunks_logsTheTotalAndTheCutoff() {
    useMocks(30, true);
    LogRetentionBatch batch = new LogRetentionBatch();
    batch.start(null);

    batch.execute(null, chunk(2));
    batch.execute(null, chunk(3));
    batch.finish(null);

    List<RecordingLogger.Entry> infos = logger.entries(LoggingLevel.INFO);
    Assert.areEqual(1, infos.size(), 'One summary');
    Assert.areEqual(
      LogRetentionBatch.LOG_PREFIX + 'deleted 5 rows created before 2026-10-14 02:00 GMT.',
      infos[0].message,
      'Total and cutoff'
    );
    Assert.areEqual(0, logger.entries(LoggingLevel.WARN).size(), 'No warning without a failure');
  }

  @IsTest
  static void cutoffFor_noClockOverride_usesNow() {
    Datetime before = Datetime.now().addDays(-7);

    Datetime cutoff = LogRetentionBatch.cutoffFor(7);

    Assert.isTrue(cutoff >= before && cutoff <= Datetime.now().addDays(-7), 'Now minus 7 days');
  }
}
