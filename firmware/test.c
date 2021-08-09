#include <stdio.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "wave_array.h"


int main()
{
    init_platform();

    print("Hello World\n\r");
    Xil_Out32(REG_LEDS, 0x01);
    Xil_Out32(REG_UART_TX, 0x33);

    cleanup_platform();
    return 0;
}
