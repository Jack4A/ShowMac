#include "CSMC.h"
#include <assert.h>
#if !APP_STORE
#error This check must compile the App Store variant.
#endif
int main(void) {
    TSValue value={0};value.size=1;value.type=0x75693820;value.bytes[0]=1;
    assert(ts_smc_write(1,"F0Md",&value)!=0);
    int fd=42;
    assert(ts_privileged_session_launch("/no-helper",2,501,&fd)!=0);
    assert(fd==-1);
    return 0;
}
