/**
 * @description Example consumer, never packaged: confirms orders and logs through A's `ILogger`
 * port, which this package binds to `PlatformEventLogger`. The service doesn't know that, and it
 * has no compile-time dependency on this package's classes.
 *
 * The messages describe attempts, not outcomes (ADR 0003): entries are published immediately, so
 * the ERROR entry and the INFO entry before it survive the rollback of the failed confirmation.
 * The ERROR becomes a CRITICAL alert in the subscriber (ADR 0006).
 * @group Example
 */
public with sharing class OrderConfirmationService {
  /** @description Written to `Order.Description` when an order is confirmed. */
  public static final String CONFIRMED_NOTE = 'Confirmed for fulfilment.';

  /**
   * @description Marks the orders confirmed, in one Unit of Work in user mode.
   * Limits: 1 DML statement (plus the savepoint) and one publish call per flush.
   * @param orders Orders with Ids; null or empty does nothing.
   * @throws DmlException If the update fails, after logging it at ERROR.
   */
  public void confirm(List<Order> orders) {
    if (orders == null || orders.isEmpty()) {
      return;
    }
    ILogger logger = (ILogger) Application.Service.newInstance(ILogger.class);
    logger.info('Confirming ' + orders.size() + ' order(s) for fulfilment');
    try {
      IUnitOfWork unitOfWork = Application.UnitOfWork.newInstance(new List<SObjectType>{ Order.SObjectType });
      for (Order record : orders) {
        unitOfWork.registerDirty(new Order(Id = record.Id, Description = CONFIRMED_NOTE));
      }
      unitOfWork.commitWork();
    } catch (DmlException failure) {
      logger.error('Order confirmation failed for ' + orders.size() + ' order(s)', failure);
      throw failure;
    } finally {
      logger.flush();
    }
  }
}
