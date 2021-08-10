#include <stdio.h>
#include <stdint.h>
#include "platform.h"
#include "xil_printf.h"
#include "xil_io.h"
#include "wave_array.h"


int main()
{
	uint32_t frequency = 440;

    init_platform();

    Xil_Out32(REG_FILE_LEDS, 0x01);
    print("Hello World\n\r");

    while (1) {

    	uint32_t slope = frequency << 16 / SAMPLE_RATE;
    	Xil_Out32(REG_FILE_SAW_SLOPE, slope);

        if (Xil_In32(REG_UART_STATUS) & 0x1) {

            char recv_byte = Xil_In32(REG_UART_RX);
            Xil_Out32(REG_UART_TX, recv_byte);

            switch (recv_byte) {
            	case 'a':
            		frequency = 440;
            		break;
            	case 'b':
            		frequency = 494;
            		break;
            	case 'c':
            		frequency = 523;
            		break;
            	case 'd':
            		frequency = 587;
            		break;
            	case 'e':
            		frequency = 659;
            		break;
            	case 'f':
            		frequency = 698;
            		break;
            	case 'g':
            		frequency = 784;
            		break;
            	default:
            		break;
            }
        }
    }

    cleanup_platform();
    return 0;
}
