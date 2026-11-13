/**
 * @description Queries over `Log__c` for retention (ADR 0007). Bound to `LogsSelector` by the
 * `DI_Binding.Logs_Selector` row, so tests can stand in a mock through `Application.Selector`.
 * @group Retention
 */
public interface ILogsSelector extends ISelector {
  /**
   * @description A query locator over every `Log__c` row created before the cutoff, in system mode
   * and without sharing, oldest first. Selects `Id` and `CreatedDate` only.
   * @param cutoff Rows created before this are selected; null selects nothing.
   * @return The locator, for a batch's `start` method.
   */
  Database.QueryLocator queryLocatorCreatedBefore(Datetime cutoff);
}
