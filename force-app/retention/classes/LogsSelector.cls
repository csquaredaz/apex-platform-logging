/**
 * @description Selects `Log__c` rows for `LogRetentionBatch` (ADR 0007).
 *
 * `without sharing` and system mode are deliberate. `Log__c` is OWD Private and its rows are owned
 * by the Automated Process user, and the batch runs as whoever scheduled it. A probe in a scratch
 * org showed that a system-mode query in a `with sharing` class sees no rows for a user without
 * View All, while the same query `without sharing` sees them all. This selector is the second
 * documented exception to the repository's user-mode rule, after the subscriber's `SystemDml`
 * (ADR 0005). The inherited `selectSObjectsById` stays user mode.
 *
 * The filter is on `CreatedDate`: it is indexed and never null, whereas `Logged_At__c` is neither.
 * @group Retention
 */
public without sharing class LogsSelector extends SObjectSelector implements ILogsSelector {
  /** Matches no row; used when there is no cutoff. */
  private static final String NO_ROWS = 'Id = null';

  /**
   * @description The type this selector queries.
   * @return `Log__c.SObjectType`.
   */
  public override SObjectType getSObjectType() {
    return Log__c.SObjectType;
  }

  /**
   * @description The fields retention needs: the Id to delete and the date it was judged by.
   * @return `Id` and `CreatedDate`.
   */
  public override List<SObjectField> getSObjectFieldList() {
    return new List<SObjectField>{ Log__c.Id, Log__c.CreatedDate };
  }

  /**
   * @description Oldest first, so an interrupted run has removed the oldest rows.
   * @return `CreatedDate, Id`.
   */
  public override String getOrderBy() {
    return 'CreatedDate, Id';
  }

  /**
   * @description See `ILogsSelector.queryLocatorCreatedBefore`. Limits: none until the batch
   * starts; a query locator can return up to 50 million rows.
   * @param cutoff Rows created before this are selected; null selects nothing.
   * @return The locator.
   */
  public Database.QueryLocator queryLocatorCreatedBefore(Datetime cutoff) {
    return Database.getQueryLocatorWithBinds(
      buildSoql(cutoff == null ? NO_ROWS : 'CreatedDate < :cutoff'),
      new Map<String, Object>{ 'cutoff' => cutoff },
      AccessLevel.SYSTEM_MODE
    );
  }
}
