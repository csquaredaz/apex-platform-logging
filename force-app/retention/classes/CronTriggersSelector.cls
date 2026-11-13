/**
 * @description Selects scheduled jobs (`CronTrigger`) by name, for `LogRetentionSchedule`. User
 * mode: whoever schedules or unschedules retention can see the jobs. It isn't bound through
 * `DI_Binding__mdt`, because tests use real scheduled jobs.
 * @group Retention
 */
public with sharing class CronTriggersSelector extends SObjectSelector {
  /**
   * @description The type this selector queries.
   * @return `CronTrigger.SObjectType`.
   */
  public override SObjectType getSObjectType() {
    return CronTrigger.SObjectType;
  }

  /**
   * @description The fields a caller needs to report or abort a job.
   * @return `Id`, `CronExpression`, `State` and `NextFireTime`.
   */
  public override List<SObjectField> getSObjectFieldList() {
    return new List<SObjectField>{
      CronTrigger.Id,
      CronTrigger.CronExpression,
      CronTrigger.State,
      CronTrigger.NextFireTime
    };
  }

  /**
   * @description Selects the scheduled jobs with this name. Limits: 1 SOQL.
   * @param jobName The job name given to `System.schedule`.
   * @return The jobs; empty when none has the name.
   */
  public List<CronTrigger> selectByJobName(String jobName) {
    return (List<CronTrigger>) query('CronJobDetail.Name = :jobName', new Map<String, Object>{ 'jobName' => jobName });
  }
}
