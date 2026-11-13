/**
 * @description Tests for `RecycleBinPurge`: emptied rows can't be undeleted, an empty list costs
 * no DML, and a failed result throws so the Unit of Work rolls back.
 */
@IsTest
private class RecycleBinPurgeTest {
  @IsTest
  static void doWork_deletedRows_cannotBeUndeleted() {
    List<Log__c> rows = new List<Log__c>{ new Log__c(), new Log__c() };
    insert as system rows;
    delete as system rows;

    new RecycleBinPurge(rows).doWork();

    for (Database.UndeleteResult result : Database.undelete(rows, false, AccessLevel.SYSTEM_MODE)) {
      Assert.isFalse(result.isSuccess(), 'An emptied row is out of the Recycle Bin');
      Assert.areEqual(StatusCode.UNDELETE_FAILED, result.getErrors()[0].getStatusCode(), 'Status');
    }
  }

  @IsTest
  static void doWork_nullOrEmpty_usesNoDml() {
    Integer before = Limits.getDmlStatements();

    new RecycleBinPurge(null).doWork();
    new RecycleBinPurge(new List<Log__c>()).doWork();

    Assert.areEqual(before, Limits.getDmlStatements(), 'Nothing to purge, no DML');
  }

  @IsTest
  static void doWork_rowNotDeleted_throws() {
    Log__c live = new Log__c();
    insert as system live;

    try {
      new RecycleBinPurge(new List<Log__c>{ live }).doWork();
      Assert.fail('A live row can not be emptied from the Recycle Bin');
    } catch (DmlException expected) {
      Assert.isTrue(expected.getMessage().contains('1 of 1 records'), 'Message: ' + expected.getMessage());
    }
  }
}
