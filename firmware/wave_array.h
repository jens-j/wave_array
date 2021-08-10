#define SAMPLE_RATE				48000
#define REG_UART_BASE           0x40600000
#define REG_UART_RX             (REG_UART_BASE + 0x0)
#define REG_UART_TX             (REG_UART_BASE + 0x4)
#define REG_UART_STATUS         (REG_UART_BASE + 0x8)
#define REG_UART_CONTROL        (REG_UART_BASE + 0xC)
#define REG_FILE_BASE           0x44A00000
#define REG_FILE_SWITCHES       (REG_FILE_BASE + 0x0)
#define REG_FILE_LEDS           (REG_FILE_BASE + 0x4)
#define REG_FILE_SAW_SLOPE      (REG_FILE_BASE + 0x8)
