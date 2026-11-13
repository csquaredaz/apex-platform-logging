/**
 * @description Tests for `LogsSelector`: the binding, the query shape, and that the locator
 * returns only rows created before the cutoff.
 */
@IsTest
private class LogsSelectorTest {
  private static Integer count(Database.QueryLocator locator) {
    Integer total = 0;
    Database.QueryLocatorIterator rows = locator.iterator();
    while (rows.hasNext()) {
      rows.next();
      total++;
    }
    return total;
  }

  @IsTest
  static void binding_forLog_resolvesLogsSelector() {
    Assert.isInstanceOfType(
      Application.Selector.newInstance(Log__c.SObjectType),
      LogsSelector.class,
      'DI_Binding.Logs_Selector binds the selector'
    );
  }

  @IsTest
  static void buildSoql_cutoff_selectsIdAndCreatedDateOldestFirst() {
    Assert.areEqual(
      'SELECT Id, CreatedDate FROM Log__c WHERE CreatedDate < :cutoff ORDER BY CreatedDate, Id',
      new LogsSelector().buildSoql('CreatedDate < :cutoff'),
      'Query shape'
    );
  }

  @IsTest
  static void queryLocatorCreatedBefore_mixedAges_returnsOnlyOlderRows() {
    Datetime now = Datetime.now();
    List<Log__c> rows = new List<Log__c>{ new Log__c(), new Log__c(), new Log__c() };
    insert as system rows;
    Test.setCreatedDate(rows[0].Id, now.addDays(-40));
    Test.setCreatedDate(rows[1].Id, now.addDays(-31));
    Test.setCreatedDate(rows[2].Id, now.addDays(-1));

    Assert.areEqual(2, count(new LogsSelector().queryLocatorCreatedBefore(now.addDays(-30))), 'Older than 30 days');
    Assert.areEqual(0, count(new LogsSelector().queryLocatorCreatedBefore(now.addDays(-50))), 'None older than 50');
  }

  @IsTest
  static void queryLocatorCreatedBefore_nullCutoff_selectsNothing() {
    insert as system new Log__c();

    Assert.areEqual(0, count(new LogsSelector().queryLocatorCreatedBefore(null)), 'No cutoff, no rows');
  }
}
