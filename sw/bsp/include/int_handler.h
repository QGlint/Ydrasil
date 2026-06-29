#ifndef __INT_HANDLER_H__
#define __INT_HANDLER_H__

#ifdef __cplusplus
extern "C"
{
#endif

    typedef enum IRQn
    {
        MachineSoftware_IRQn = 3,  /*!< Machine Software Interrupt */
        MachineTimer_IRQn = 7,     /*!< Machine Timer Interrupt */
        MachineExternal_IRQn = 11  /*!< Machine External Interrupt */
    } IRQn_Type;

    typedef enum PLIC_IRQn
    {
        Timer0_IRQn = 0,     /*!< Timer0 interrupt */
        Timer1_IRQn = 1,     /*!< Timer1 interrupt */
        Timer2_IRQn = 2,     /*!< Timer2 interrupt */
        Timer3_IRQn = 3,     /*!< Timer3 interrupt */
        SPI_IRQn = 4,        /*!< SPI interrupt */
        I2C0_IRQn = 5,       /*!< I2C0 interrupt */
        I2C1_IRQn = 6,       /*!< I2C1 interrupt */
        UART0_IRQn = 7,      /*!< UART0 interrupt */
        UART1_IRQn = 8,      /*!< UART1 interrupt */
        GPIO0_IRQn = 9,      /*!< GPIO0 interrupt */
        GPIO1_IRQn = 10      /*!< GPIO1 interrupt */
    } PLIC_IRQn_Type;

    void timer0_event_handler(void);
    void timer1_event_handler(void);
    void timer2_event_handler(void);
    void timer3_event_handler(void);
    void spi_event_handler(void);
    void i2c0_interrupt_handler(void);
    void i2c1_interrupt_handler(void);
    void uart0_event_handler(void);
    void uart1_event_handler(void);
    void gpio0_int_handler(void);
    void gpio1_int_handler(void);
    void machine_software_interrupt_handler(void);
    void machine_timer_interrupt_handler(void);
    void machine_external_interrupt_handler(void);

#ifdef __cplusplus
}
#endif

#endif // __INT_HANDLER_H__