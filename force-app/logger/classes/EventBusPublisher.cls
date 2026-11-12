/**
 * @description Publishes log events on the event bus. `Log_Event__e` is Publish Immediately, so
 * each call uses one of the transaction's publish-immediate calls and survives a rollback
 * (ADR 0003).
 * @group Logging
 */
public with sharing class EventBusPublisher implements ILogEventPublisher {
  /**
   * @description See `ILogEventPublisher.publish`.
   * @param events The events to publish.
   * @return One result per event, in order.
   */
  public List<Database.SaveResult> publish(List<Log_Event__e> events) {
    return EventBus.publish(events);
  }
}
