#include <stdio.h>
#include <stdlib.h>
#include <time.h>

int main(void) {
    setenv("TZ", "America/Managua", 1);
    tzset();
    time_t t = 725868000;
    struct tm *tm = localtime(&t);
    printf("TZ=%s zone=%s offset=%ld\n", getenv("TZ"), tm->tm_zone, tm->tm_gmtoff);
    return tm->tm_gmtoff != -18000;
}
