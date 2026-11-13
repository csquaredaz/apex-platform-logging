/**
 * @description Real selector, Unit of Work, DML and batch (ADR 0007): old rows are hard-deleted,
 * recent ones are kept, and a Minimum Access user with no `Log__c` permission can still run
 * retention, because it runs in system mode and without sharing.
 */
@IsTest
private class LogRetentionIntegrationTest {
  private static final Integer OLD_ROWS = 200;
  private static final Integer RECENT_ROWS = 5;

  private static List<Log__c> oldRows;
  private static List<Log__c> recentRows;

  /** Rows owned by the test's admin; with OWD Private, another user can't see them through sharing. */
  private static void insertRows() {
    Logging_Setting__mdt row = LoggerTestFixtures.settings('DEBUG', 50);
    row.Retention_Days__c = 30;
    LoggingSettings.useRow(row);
    oldRows = new List<Log__c>();
    recentRows = new List<Log__c>();
    for (Integer i = 0; i < OLD_ROWS; i++) {
      oldRows.add(new Log__c(Level__c = 'DEBUG', Log_Key__c = 'old-' + i));
    }
    for (Integer i = 0; i < RECENT_ROWS; i++) {
      recentRows.add(new Log__c(Level__c = 'DEBUG', Log_Key__c = 'recent-' + i));
    }
    insert as system oldRows;
    insert as system recentRows;
    for (Log__c old : oldRows) {
      Test.setCreatedDate(old.Id, Datetime.now().addDays(-31));
    }
  }

  private static Set<Id> idsOf(List<Log__c> rows) {
    return new Map<Id, Log__c>(rows).keySet();
  }

  private static void runRetention() {
    Test.startTest();
    Database.executeBatch(new LogRetentionBatch(), LogRetentionBatch.BATCH_SIZE);
    Test.stopTest();
  }

  private static void assertOldPurgedAndRecentKept() {
    Set<Id> oldIds = idsOf(oldRows);
    Set<Id> recentIds = idsOf(recentRows);
    Assert.areEqual(0, [SELECT COUNT() FROM Log__c WHERE Id IN :oldIds WITH SYSTEM_MODE], 'Old rows are gone');
    Assert.areEqual(
      RECENT_ROWS,
      [SELECT COUNT() FROM Log__c WHERE Id IN :recentIds WITH SYSTEM_MODE],
      'Recent rows stay'
    );
    for (Database.UndeleteResult result : Database.undelete(oldRows, false, AccessLevel.SYSTEM_MODE)) {
      Assert.isFalse(result.isSuccess(), 'Hard-deleted: not in the Recycle Bin');
    }
    AsyncApexJob run = [
      SELECT Status, NumberOfErrors
      FROM AsyncApexJob
      WHERE JobType = 'BatchApex' AND ApexClass.Name = 'LogRetentionBatch'
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    Assert.areEqual('Completed', run.Status, 'The run completed');
    Assert.areEqual(0, run.NumberOfErrors, 'No chunk threw');
  }

  @IsTest
  static void retention_twoHundredOldRows_hardDeletesThemAndKeepsRecentOnes() {
    insertRows();
    Assert.areEqual(
      OLD_ROWS + RECENT_ROWS,
      [SELECT COUNT() FROM Log__c WITH SYSTEM_MODE],
      'Seeded: 200 older than the retention, 5 recent'
    );

    runRetention();

    assertOldPurgedAndRecentKept();
  }

  @IsTest
  static void retention_minimumAccessUser_purgesInSystemMode() {
    User minimumAccess = LoggerTestFixtures.minimumAccessUser();
    System.runAs(new User(Id = UserInfo.getUserId())) {
      insertRows();
    }
    Assert.isFalse(
      [SELECT Id FROM Profile WHERE Id = :minimumAccess.ProfileId WITH SYSTEM_MODE].isEmpty(),
      'Minimum Access profile'
    );

    System.runAs(minimumAccess) {
      Assert.isFalse(Schema.SObjectType.Log__c.isDeletable(), 'The user has no delete access to Log__c');
      runRetention();
    }

    assertOldPurgedAndRecentKept();
  }
}
