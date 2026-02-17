#include <stdio.h>

int main(void) {
    int a = 21;
    int b = 6;
    double x = 7.5;
    double y = 2.0;

    printf("a=%d, b=%d\n", a, b);
    printf("a + b = %d\n", a + b);
    printf("a - b = %d\n", a - b);
    printf("a * b = %d\n", a * b);
    printf("a / b = %d\n", a / b);
    printf("a %% b = %d\n", a % b);
    printf("x / y = %.3f\n", x / y);
    return 0;
}
